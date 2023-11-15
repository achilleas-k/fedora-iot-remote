#!/usr/bin/env bash

set -xeuo pipefail

remoteinfo() {
    sudo ostree remote list
    sudo ostree remote summary fedora-iot || echo "remote fedora-iot not configured"

    if grep -qF 'remote "fedora-iot"'  /etc/ostree/remotes.d/fedora-iot.conf 2>/dev/null; then
        echo "Remote config found in /sysroot/ostree/repo/config/fedora-iot.conf" && cat /etc/ostree/remotes.d/fedora-iot.conf
    fi
    if grep -qF 'remote "fedora-iot"' /sysroot/ostree/repo/config; then
        echo "Remote config found in /sysroot/ostree/repo/config" && cat /sysroot/ostree/repo/config
    fi
}

# check existing config
remoteinfo


# replace remote config
sudo ostree remote add --force --no-gpg-verify --no-sign-verify fedora-iot http://10.0.2.2:8080

# check remote config
remoteinfo

echo "now try rpm-ostree upgrade"
