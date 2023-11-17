#!/usr/bin/env bash

set -e -o pipefail -u -x

############################################################
# UPGRADE
############################################################
if ! grep -Pz "Start-Date: $(date +%F) .*\nCommandline: apt -y upgrade" /var/log/apt/history.log > /dev/null; then
  sudo apt update
  sudo DEBIAN_FRONTEND=noninteractive apt -y upgrade
  sudo snap refresh
  sudo reboot
fi

############################################################
# MISC
############################################################
install -m $(stat -c '%a' ~/.bashrc) /dev/null ~/.bash_aliases
ssh-keygen -f ~/.ssh/id_rsa -N ""
sudo DEBIAN_FRONTEND=noninteractive apt -y install unzip

############################################################
# ANSIBLE
############################################################
sudo add-apt-repository -y ppa:ansible/ansible
sudo DEBIAN_FRONTEND=noninteractive apt -y install ansible

############################################################
# DOCKER
############################################################
cd $(mktemp -d)
until wget -O get-docker.sh https://get.docker.com; do :; done
sudo sh get-docker.sh
sudo usermod -aG docker $USER

############################################################
# MULLVAD
############################################################
cd $(mktemp -d)
until wget https://mullvad.net/media/mullvad-code-signing.asc; do :; done
until wget --trust-server-names https://mullvad.net/download/app/deb/latest; do :; done
until wget --trust-server-names https://mullvad.net/download/app/deb/latest/signature; do :; done
gpg --import mullvad-code-signing.asc
gpg --verify MullvadVPN-*.deb.asc
sudo DEBIAN_FRONTEND=noninteractive apt -y install ./MullvadVPN-*.deb
mullvad lan set allow
echo "alias mullvad-status='mullvad status && curl https://am.i.mullvad.net/connected'" >> ~/.bash_aliases

############################################################
# SVTPLAY-DL & YT-DLP
############################################################
DOCKER_CMD="docker run -it --rm -v \"\$(pwd):/data\" --pull always"
YT_DLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
echo "alias svtplay-dl='$DOCKER_CMD -u \$(id -u):\$(id -g) spaam/svtplay-dl --all-subtitles --format-preferred hevc,h264 --resolution'" >> ~/.bash_aliases
echo "alias yt-dlp='$DOCKER_CMD --entrypoint sh spaam/svtplay-dl -c \"wget -P /usr/local/bin $YT_DLP_URL && chmod a+rx /usr/local/bin/yt-dlp && sh\"'" >> ~/.bash_aliases

############################################################
# TRANSMISSION
############################################################
mkdir ~/transmission
cat << EOF > ~/transmission/compose.yaml
services:
  transmission:
    image: linuxserver/transmission
    environment:
      - PUID=$(id -u)
      - PGID=$(id -g)
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    ports:
      - "51413:51413"
      - "51413:51413/udp"
    pull_policy: always
EOF
chmod a-w ~/transmission/compose.yaml

############################################################
# REBOOT
############################################################
sudo reboot
