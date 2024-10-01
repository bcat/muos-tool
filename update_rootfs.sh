#!/bin/sh

REPO_DIR="Repo/MustardOS"

if [ "$#" -ne 2 ]; then
	printf "Usage: %s <image_dir> <rootfs_image>\n" "$0"
	exit 1
fi

DIR=$1
if [ ! -d "$DIR" ]; then
	printf "No valid image directory found at '%s'\n" "$DIR"
	exit 1
fi

ROOTFS=$2
if [ ! -f "$ROOTFS" ]; then
	printf "No valid RootFS found at '%s'\n" "$ROOTFS"
	exit 1
fi

IMG_TOTAL=$(find "$DIR" -maxdepth 1 -name '*.img' -type f | wc -l)
if [ "$IMG_TOTAL" -eq 0 ]; then
	printf "No image files found in '%s'\n" "$DIR"
	exit 1
fi

sudo -v

printf "\n=============== \033[1mRootFS Processing\033[0m ==============\n\n"
printf "\033[1mProcessing RootFS:\033[0m %s\n" "$ROOTFS"

MOUNT_POINT=$(mktemp -d)
if ! sudo mount -o loop,rw "$ROOTFS" "$MOUNT_POINT"; then
	printf "\t\033[1m- Failed to mount RootFS:\033[0m '%s' at '%s'\n" "$ROOTFS" "$MOUNT_POINT"
	rmdir "$MOUNT_POINT"
	exit 1
else
	printf "\t\033[1m- Mounted RootFS:\033[0m '%s' at '%s'\n" "$ROOTFS" "$MOUNT_POINT"
fi

printf "\t\033[1m- Calculating Random Checksum\033[0m\n"
IMG_CS=$(dd if=/dev/urandom bs=1 count=8 2>/dev/null | md5sum | cut -c1-8)
printf "\t\033[1m- Using Checksum:\033[0m %s\n" "$IMG_CS"

rm -rf "$MOUNT_POINT/opt/muos"
mkdir -p "$MOUNT_POINT/opt/muos"

printf "\t\033[1m- Updating muOS Internals\033[0m\n"
INTERNAL_STUFF="bin browse config device extra init script theme factory.mp3 silence.wav preload.txt"
for I in $INTERNAL_STUFF; do
	rsync -a --info=progress2 "$HOME/$REPO_DIR/internal/$I" "$MOUNT_POINT/opt/muos/"
done

printf "\n\t\033[1m- Updating muOS Frontend\033[0m\n"
rsync -a --info=progress2 "$HOME/$REPO_DIR/frontend/bin/" "$MOUNT_POINT/opt/muos/extra/"

printf "\n\t\033[1m- Removing Leftover Files\033[0m\n"
rm -rf "$MOUNT_POINT/opt/muos/.git" \
	"$MOUNT_POINT/opt/muos/LICENSE" \
	"$MOUNT_POINT/opt/muos/README.md" \
	"$MOUNT_POINT/opt/muos/.gitignore"
find "$MOUNT_POINT/opt/muos/." -name ".gitkeep" -delete

printf "\t\033[1m- Correcting File Permissions\033[0m\n"
sudo chmod -R 755 "$MOUNT_POINT/opt/muos"
sudo chown -R "$(whoami):$(whoami)" "$MOUNT_POINT/opt/muos"

printf "\t\033[1m- File Synchronisation\033[0m\n"
sync

printf "\t\033[1m- Unmounting Image\033[0m\n"
sudo umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

printf "\n==========\033[1m RootFS Processing Complete \033[0m==========\n"

sudo -v

printf "\n===============\033[1m Image Processing \033[0m===============\n\n"

for IMG in "$DIR"/*.img; do
	if [ -f "$IMG" ]; then
		printf "\033[1mProcessing Image:\033[0m %s\n" "$IMG"

		DEVICE=$(echo "$IMG" | sed -n 's/.*muOS-\([^/]*\)-[0-9]*\.[0-9]*-[^.]*\.img/\1/p')
		if [ -z "$DEVICE" ]; then
			printf "\t\033[1m- Failed to extract device name from image name\033[0m\n"
			continue
		else
			printf "\t\033[1m- Detected Device Type:\033[0m %s\n" "$DEVICE"
		fi

		MOUNT_POINT=$(mktemp -d)
		if ! sudo mount -o loop,rw "$ROOTFS" "$MOUNT_POINT"; then
			printf "\t\033[1m- Failed to mount RootFS:\033[0m '%s' at '%s'\n" "$ROOTFS" "$MOUNT_POINT"
			rmdir "$MOUNT_POINT"
			continue
		else
			printf "\t\033[1m- Mounted RootFS:\033[0m '%s' at '%s'\n" "$ROOTFS" "$MOUNT_POINT"
		fi

		printf "\t\033[1m- Updating Device Type\033[0m\n"
		echo "$DEVICE" | sudo tee "$MOUNT_POINT/opt/muos/config/device.txt" >/dev/null
		printf "\t\033[1m- Confirmed Device Type:\033[0m %s\n" "$(cat "$MOUNT_POINT/opt/muos/config/device.txt")"

		printf "\t\033[1m- Updating Version Information\033[0m\n"
		sed -i "2s/.*/$IMG_CS/" "$MOUNT_POINT/opt/muos/config/version.txt" >/dev/null

		printf "\t\033[1m- Updating Build Identification\033[0m\n"
		echo "$IMG_CS" >"$DIR/buildID.txt"
		printf "\t\033[1m- Confirmed Build Identification:\033[0m %s\n" "$IMG_CS"

		printf "\t\033[1m- Correcting File Permissions\033[0m\n"
		sudo chmod -R 755 "$MOUNT_POINT/opt/muos"
		sudo chown -R "$(whoami):$(whoami)" "$MOUNT_POINT/opt/muos"

		printf "\t\033[1m- File Synchronisation\033[0m\n"
		sync

		printf "\t\033[1m- Unmounting Image\033[0m\n"
		sudo umount "$MOUNT_POINT"
		rmdir "$MOUNT_POINT"

		sudo -v

		printf "\t\033[1m- Injecting modified RootFS\033[0m\n"
		dd if="$ROOTFS" of="$IMG" bs=4M seek=319488 conv=notrunc,noerror status=progress

		printf "\n"

		sudo -v
	fi
done

printf "==========\033[1m Image Processing Complete \033[0m===========\n\n"