#!/usr/bin/env bash

set -xeuo pipefail

image_directory="$1"

base_container="oci-archive:${image_directory}/fedora_39-x86_64-iot_container-base/container/container.tar"
upgrade_container="oci-archive:${image_directory}/fedora_39-x86_64-iot_container-upgrade/container/container.tar"
container_name="ostree-repo"

repodir="repository"

cleanup() {
    sudo rm -rf "${repodir}"
    podman stop "${container_name}" || true
}
trap cleanup EXIT
podman stop "${container_name}" || true  # make sure no container is running from earlier

ostree init --mode=archive --repo="${repodir}"
ostree --repo="${repodir}" remote add --no-gpg-verify --no-sign-verify fedora-iot http://localhost:8080/repo

podman run -d -p8080:8080 --rm --name  "${container_name}" "${base_container}"
sudo ostree --repo="${repodir}" pull --mirror fedora-iot fedora/39/x86_64/iot

podman stop "${container_name}"
sleep 3
podman run -d -p8080:8080 --rm --name "${container_name}" "${upgrade_container}"
sudo ostree --repo="${repodir}" pull --mirror fedora-iot fedora/39/x86_64/iot

sudo ostree --repo="${repodir}" summary -u
sudo ostree --repo="${repodir}" static-delta generate fedora/39/x86_64/iot

ostree --repo="${repodir}" summary -v
ostree --repo="${repodir}" refs
ostree --repo="${repodir}" log fedora/39/x86_64/iot

podman stop "${container_name}"
python -m http.server 8080 --directory "${repodir}"
