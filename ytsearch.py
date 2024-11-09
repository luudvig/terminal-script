#!/usr/bin/env python3

from argparse import ArgumentParser
from json import dump, loads
from os import environ, remove
from os.path import splitext
from re import fullmatch
from requests import get
from subprocess import CalledProcessError, PIPE, Popen, run
from sys import exit
from tempfile import NamedTemporaryFile

quality_choices = [4320, 2160, 1440, 1080, 720, 480, 360, 240, 144]

parser = ArgumentParser()
parser.add_argument('-d', '--download', action='store_true', help='download selected video')
parser.add_argument('-i', '--id', action='store_true', help='query argument is treated as video id')
parser.add_argument('-q', '--quality', default=720, type=int, choices=quality_choices, help='max quality (default: 720)', metavar='QUALITY')
parser.add_argument('-r', '--results', default=10, type=int, choices=range(1, 51), help='max results when searching (default: 10)', metavar='RESULTS')
parser.add_argument('-s', '--sort', action='store_const', const='date', default='relevance', help='sort by date when searching')
required_args = parser.add_argument_group('required arguments')
required_args.add_argument('-k', '--api-key', required=True, help='api key to use when searching')
required_args.add_argument('query', nargs='+', help='query to use when searching or url to stream/download')
args = parser.parse_args()

bin_vlc, bin_ytdlp = run(['which', 'vlc', 'yt-dlp'], stdout=PIPE, check=True, text=True).stdout.splitlines()
url_query = fullmatch(r'https:\/\/(www\.)?youtu\.?be(\.com)?\/(watch\?v=)?[a-zA-Z0-9-_]{11}', args.query[0])

if args.id or url_query:
    webpage_id = args.query[0][-11:]
else:
    locator = 'https://www.googleapis.com/youtube/v3'
    headers = {'accept': 'application/json'}

    search_payload = {'part': 'id', 'maxResults': args.results, 'order': args.sort, 'q': ' '.join(args.query), 'type': 'video', 'key': args.api_key}
    search_response = get('{0}/search'.format(locator), headers=headers, params=search_payload)

    videos_payload = {'part': ['contentDetails', 'snippet'], 'id': [i['id']['videoId'] for i in search_response.json()['items']], 'key': args.api_key}
    videos_response = get('{0}/videos'.format(locator), headers=headers, params=videos_payload)
    videos_items = videos_response.json()['items']

    for c, i in enumerate(videos_items):
        print('{0:>{1}}. [{2} {3} {4}] {5} ({6})'.format(c, 1 if len(videos_items) <= 10 else 2, i['snippet']['publishedAt'][:10], i['id'],
            i['snippet']['channelTitle'], i['snippet']['title'], i['contentDetails']['duration'][2:].lower()))

    try:
        webpage_id = videos_items[int(input('[ytsearch] Select video to stream/download [0]: ') or '0')]['id']
    except KeyboardInterrupt:
        exit('')

ytdlp_selector = ''.join(['bestvideo{1}[vcodec^=av01]+bestaudio{0}/best{1}{2}/bestvideo{1}{2}+bestaudio{0}/'
    .format('[ext=m4a]', '[height<={0}][height>{1}]'.format(quality_choices[c - 1], q), '[vcodec^=avc1]')
    for c, q in enumerate(quality_choices + [0]) if q < args.quality])[:-1]

ytdlp_url = 'https://www.youtube.com/watch?v={0}'.format(webpage_id)
if not url_query:
    print('[ytsearch] {0}'.format(ytdlp_url))

try:
    ytdlp_process = run([bin_ytdlp, '--dump-json', '--format', ytdlp_selector, ytdlp_url], stdout=PIPE, check=True, text=True)
except CalledProcessError:
    exit()

ytdlp_result = loads(ytdlp_process.stdout)

if not args.download:
    ytdlp_format_ids = ytdlp_result['format_id'].split('+')
    ytdlp_urls = [f['url'] for f in ytdlp_result['formats'] if f['format_id'] in ytdlp_format_ids]

    vlc_command = [bin_vlc, '--meta-title', splitext(ytdlp_result['_filename'])[0], ytdlp_urls[0]]
    if len(ytdlp_urls) > 1:
        vlc_command.extend(['--input-slave', ytdlp_urls[1]])

    Popen(vlc_command, stdout=PIPE, stderr=PIPE)
elif ytdlp_result['is_live']:
    print('[ytsearch] Ignoring live stream')
else:
    with NamedTemporaryFile(mode='w', delete=False) as ytdlp_temp:
        dump(ytdlp_result, ytdlp_temp)

    try:
        run([bin_ytdlp, '--output', '{0}/Videos/{1}'.format(environ['HOME'], ytdlp_result['_filename']),
            '--load-info-json', ytdlp_temp.name, '--format', ytdlp_result['format_id']])
    except KeyboardInterrupt:
        exit()
    finally:
        remove(ytdlp_temp.name)
