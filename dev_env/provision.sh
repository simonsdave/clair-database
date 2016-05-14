#!/usr/bin/env bash
#
# this script provisions a development environment
#

set -e

apt-get update -y

apt-get install -y docker.io
sed -i -e 's|#DOCKER_OPTS="--dns 8.8.8.8 --dns 8.8.4.4"|DOCKER_OPTS="-H tcp://172.17.42.1:2375 -H unix:///var/run/docker.sock"|g' /etc/default/docker
service docker restart

apt-get install -y git

timedatectl set-timezone EST

curl -s -L --output /etc/jq 'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64'
chown root.root /etc/jq
chmod a+x /etc/jq

apt-get install -y golang-go
mkdir ~vagrant/.gopath
chown vagrant:vagrant ~vagrant/.gopath
echo 'export GOPATH=$HOME/.gopath' >> ~vagrant/.profile
echo 'PATH="$GOPATH/bin:$PATH"' >> ~vagrant/.profile

# instructions from https://cloud.google.com/sdk/#debubu
export CLOUD_SDK_REPO=cloud-sdk-`lsb_release -c -s`
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt-get update && apt-get install google-cloud-sdk

cp /vagrant/.vimrc ~vagrant/.vimrc
chown vagrant:vagrant ~vagrant/.vimrc

echo 'export VISUAL=vim' >> ~vagrant/.profile
echo 'export EDITOR="$VISUAL"' >> ~vagrant/.profile

if [ $# == 2 ]; then
    su - vagrant -c "git config --global user.name \"${1:-}\""
    su - vagrant -c "git config --global user.email \"${2:-}\""
fi

exit 0