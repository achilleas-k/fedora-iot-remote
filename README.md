# Fedora IoT remote configuration

Manifests and scripts to reproduce an issue with the packaged remote configuration for ostree-based Fedora systems built by Image Builder.

Large files (containers and images) can be found in this Google Drive folder:
https://drive.google.com/drive/folders/1pC0a5lggb3kt3eiB2j9eegFX-gA42W0b?usp=sharing

_NOTE: The **iot-container** image type is an ostree repo with a single commit in a container running nginx to serve it.

## Steps to reproduce

1. Build a Fedora `iot-container`.
2. Run the `iot-container` to serve the commit.
3. Build a Fedora `iot-container` as an upgrade to the first one.
4. Build a Fedora `iot-qcow2-image` using the first commit.
5. Create a local ostree repository that contains both Fedora IoT commits and serve it with a simple web server.
    - See `makerepo.sh`
    - The script uses `python -m http.server` which might fail when ostree content is being pulled from it, but it demonstrates our issue nonetheless.
6. Boot the `iot-qcow2-image`.
7. Remove the ostree remote and add it again with the URL pointing to the new ostree repository with the two commits.
    - Alternatively, force add it using `ostree remote add --force --no-gpg-verify --no-sign-verify fedora-iot http://10.0.2.2:8080`
8. Run `rpm-ostree upgrade`.

For the last three steps, see `test.sh`.

## Outcomes

There are three sets of manifests:
- Static
- Packaged
- None

**Static**: This is built with **osbuild/images@main** and sets a remote statically while creating the `iot-qcow2-image` as part of the image definition.

**Packaged**: This is build with **osbuild/images@iot-remote** and does not set a remote when building the image.  It includes the `fedora-iot-config` package in the base package set for the `iot-commit` and `iot-container` image types (the base image).

**None**: This is build with **osbuild/images@iot-remote** but the package is removed from the package list.  No remote is configured in the image.  This is meant to control for any other changes made in the `iot-remote` branch.

The `rpm-ostree upgrade` command will detect and pull an upgrade only when an ostree remote is not configured through a package.  It works in the **Static** and the **None** case, but not the **Packaged** case.

## Detailed steps

The images are already built and available in the linked Google Drive folder, so build steps can be skipped, but they are described for full clarity.
With the images available, you can skip to step 5.
If you don't have access to the images, you can build them without needing the code using the manifests and osbuild.
We will use the code from my fork that includes the `iot-remote` branch.

### Static

0. Clone the repository
```
git clone https://github.com/achilleas-k/images ./osbuild-images
cd ./osbuild-images
```

1. Build a Fedora `iot-container` with an empty config.
```
go build -o ./bin/build ./cmd/build
sudo ./bin/build --distro fedora-39 --image iot-container --output ../static --config ../configs/base.json
```

2. Pull the `iot-container` and run it to serve the commit
```
podman tag $(podman pull oci-archive:static/fedora_39-x86_64-iot_container-base/container/container.tar) fedora-iot/static/base
podman run -d --rm -p8080:8080 --name ostree-repo fedora-iot/static/base
```

3. Build a Fedora `iot-container` as an upgrade to the first one.
(note that the upgrade commit includes some packages)
```
sudo ./bin/build --distro fedora-39 --image iot-container --output ../static --config ../configs/upgrade.json
```

4. Build a Fedora `iot-qcow2-image` using the first commit.
(note that the deployment includes a user with username `osbuild`, password `osbuild`, and an ssh key which can be found in the `keys/` directory, and is part of the `wheel` group)
```
sudo ./bin/build --distro fedora-39 --image iot-qcow2-image --output ../static --config ../configs/deployment.json
```

5. Create a local ostree repository that contains both Fedora IoT commits and serve it with a simple web server.
(from the root of this shared folder)
```
./makerepo.sh ./static
```
The repository is created in a directory that is deleted when the script exits (ctrl+c).
You can verify that the repo is ready and the server is running with:
```
$ curl http://localhost:8080/refs/heads/fedora/39/x86_64/iot
29ba825c36b8d59e1b94627ec0e73b0f9c50202086410702b2d9b51dfbb4a747

$ ostree --repo=./repository summary -v
OT: using fuse: 0
* fedora/39/x86_64/iot
    Latest Commit (19.6 kB):
      29ba825c36b8d59e1b94627ec0e73b0f9c50202086410702b2d9b51dfbb4a747
    Version (ostree.commit.version): 39
    Timestamp (ostree.commit.timestamp): 2023-11-15T13:12:21+01

Repository Mode (ostree.summary.mode): archive-z2
Last-Modified (ostree.summary.last-modified): 2023-11-15T13:39:30+01
Has Tombstone Commits (ostree.summary.tombstone-commits): No
ostree.summary.indexed-deltas: true
achilleas@Jack:/media/scratch/osbuild/issues/iot-remote

$ ostree --repo=./repository log fedora/39/x86_64/iot
commit 29ba825c36b8d59e1b94627ec0e73b0f9c50202086410702b2d9b51dfbb4a747
Parent:  210cbed651d1403a3cf5fb3dc62133833f8d27812054756495ea242ab58e432b
ContentChecksum:  c4858e7d35ab88f8af5efacdbb9449b6fe0a78b1ae2f47c11f7b292318712f55
Date:  2023-11-15 12:12:21 +0000
Version: 39
(no subject)

commit 210cbed651d1403a3cf5fb3dc62133833f8d27812054756495ea242ab58e432b
ContentChecksum:  da4f807e3197631a5abafb36beaad5fc374070dea649228cfd86fd86f4e39e81
Date:  2023-11-15 11:52:31 +0000
Version: 39
(no subject)
```

(commit SHAs will be different if the images are rebuilt)

6. Boot the `iot-qcow2-image`.
(note that we use `-snapshot` which will discard changes to the image when it is shut down)
```
qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -m 12G \
    -device virtio-net-pci,netdev=n0,mac="FE:0B:6E:23:3D:17" \
    -netdev user,id=n0,net=10.0.2.0/24,hostfwd=tcp::2224-:22 \
    -bios /usr/share/edk2-ovmf/x64/OVMF.fd \
    -snapshot \
    -drive file=./static/fedora_39-x86_64-iot_qcow2_image-deployment/qcow2/image.qcow2
```
copy the test script
```
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P2224 -i ./keys/key ./test.sh osbuild@localhost:test.sh

```
and log in
```
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p2224 -i ./keys/key osbuild@localhost
```
(or log in on the console with `osbuild`/`osbuild`)

7. Remove the ostree remote and add it again with the URL pointing to the new ostree repository with the two commits.
(note that the script prints some info before and after the configuration change)
```
./test.sh
```

8. Run `rpm-ostree upgrade`.
(note that if this starts downloading, it might fail because the python http server isn't _great_; trying a few times will resume the download and finish)

### Packaged

0. Switch to the `iot-remote` branch of the repo.
```
cd ./osbuild-images
git checkout iot-remote
```

Follow the same steps as above, replacing `static` in the `--output` options and the container name to `packaged` so as to not overwrite the existing images.

### None

0. Apply the following patch to the `iot-remote` branch of the repo.

```patch
diff --git a/pkg/distro/fedora/package_sets.go b/pkg/distro/fedora/package_sets.go
index cf080f3ad..e756a1b1c 100644
--- a/pkg/distro/fedora/package_sets.go
+++ b/pkg/distro/fedora/package_sets.go
@@ -101,7 +101,7 @@ func iotCommitPackageSet(t *imageType) rpmmd.PackageSet {
 			"dracut-network",
 			"e2fsprogs",
 			"efibootmgr",
-			"fedora-iot-config",
+			// "fedora-iot-config",
 			"fedora-release-iot",
 			"firewalld",
 			"fwupd",
```

Follow the same steps as above, replacing `static` in the `--output` options and the container name to `none` so as to not overwrite the existing images.
