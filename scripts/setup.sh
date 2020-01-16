#!/usr/bin/env bash
set -e

go=false
java=false
js=false
py=false

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

case "$1" in
    --go*)
        go=true
        ;;
    --java*)
        java=true
        ;;
    --js*)
        js=true
        ;;
    --py*)
        py=true
        ;;
esac

function ostype {
  UNAME=$(uname)
  if [ "${UNAME}" = "Darwin" ]; then
      echo "darwin"
  elif [ "${UNAME}" = "Linux" ]; then
      echo "linux"
  else
      echo "unsupported"
      exit 1
  fi
}

function brew_install_or_upgrade {
    if brew ls --versions "$1" >/dev/null; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade "$1" || true
    else
        HOMEBREW_NO_AUTO_UPDATE=1 brew install "$1"
    fi
}

# Install pyenv
OS=ostype
if [ "${OS}" = "linux" ]; then
    if ! which sudo > /dev/null
    then
        apt-get update
        apt-get -y install sudo
    fi

    sudo apt-get update
    sudo apt-get install -y libffi-dev git
    if ! [ -x "$(command -v pyenv)" ]; then
      echo 'Installing pyenv'
      git clone https://github.com/pyenv/pyenv.git /opt/pyenv
      echo 'export PYENV_ROOT="$HOME/opt"' >> ~/.bashrc
      echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
      echo 'eval "$(pyenv init -)"' >> ~/.bashrc
      source ~/.bashrc
    fi
elif [ "${OS}" = "darwin" ]; then
    install_or_upgrade pyenv
fi


go get github.com/DATA-DOG/godog/cmd/godog
if ! $go
then
    go get -u github.com/algorand/go-algorand-sdk/...
    go generate github.com/algorand/go-algorand-sdk/...
fi


if $py
then
    pip3 install "$TRAVIS_BUILD_DIR" -q
else
    sudo apt-get install libffi-dev
    pushd /opt/pyenv/plugins/python-build/../..
    git pull origin master
    popd
    pyenv install --list
    pyenv install 3.7.1 -s # skip if already installed
    pyenv global 3.7.1
    pip3 install git+https://github.com/algorand/py-algorand-sdk/ -q
fi
pip3 install behave -q

# ensure correct nodejs version (>=10) if running on travis
# shellcheck source=shared.sh
source "$SCRIPTPATH/shared.sh"
ensure_nodejs_version

pushd js_cucumber
npm install --silent
if $js
then
    npm install "$TRAVIS_BUILD_DIR" --silent
fi
popd

pushd java_cucumber
if $java
then
    echo "Building java from : $TRAVIS_BUILD_DIR"
    pushd "$TRAVIS_BUILD_DIR"
    mvn package install -q -DskipTests
    ALGOSDK_VERSION=$(mvn -q -Dexec.executable=echo  -Dexec.args='${project.version}' --non-recursive exec:exec)
    popd
    #find "${TRAVIS_BUILD_DIR}/target" -type f -name "*.jar" -exec mvn install:install-file -q -Dfile={} -DpomFile="${TRAVIS_BUILD_DIR}/pom.xml" \;
else
    git clone https://github.com/algorand/java-algorand-sdk.git ~/java-algorand-sdk
    pushd ~/java-algorand-sdk
    mvn package install -q -DskipTests
    ALGOSDK_VERSION=$(mvn -q -Dexec.executable=echo  -Dexec.args='${project.version}' --non-recursive exec:exec)
    popd
    #find ~/java-algorand-sdk/target -type f -name "*.jar" -exec mvn install:install-file -q -Dfile={} -DpomFile="${HOME}/java-algorand-sdk/pom.xml" \;
    rm -rf ~/java-algorand-sdk
fi
mvn versions:use-dep-version -DdepVersion=$ALGOSDK_VERSION -Dincludes=com.algorand:algosdk -DforceVersion=true -q
popd


# test last release: change to config_stable here and in test.sh
# test current code: change to config_nightly here and in test.sh
# shellcheck source=shared.sh
source "$SCRIPTPATH/config_future"

mkdir -p ~/inst
rm -rf ~/inst/*
mkdir -p ~/inst/node
BIN_DIR=~/inst/node

# this is the link for linux; change this if on mac or windows
curl -L https://algorand-releases.s3.amazonaws.com/channel/nightly/install_nightly_linux-amd64_1.0.288.tar.gz -o ~/inst/installer.tar.gz
tar -xf ~/inst/installer.tar.gz -C ~/inst
~/inst/update.sh -i -c "$CHANNEL" -p "$BIN_DIR" -d "$BIN_DIR/data" -b algorand-releases -n
