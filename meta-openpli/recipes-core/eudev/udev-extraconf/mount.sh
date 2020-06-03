#!/bin/sh
#
# Called from udev
#
# Attempt to mount any added block devices and umount any removed devices


MOUNT="/bin/mount"
PMOUNT="/usr/bin/pmount"
UMOUNT="/bin/umount"
for line in `grep -h -v ^# /etc/udev/mount.blacklist /etc/udev/mount.blacklist.d/*`
do
	if [ ` expr match "$DEVNAME" "$line" ` -gt 0 ];
	then
		logger "udev/mount.sh" "[$DEVNAME] is blacklisted, ignoring"
		exit 0
	fi
done

automount() {
	# Device name and base device
	NAME="`basename "$DEVNAME"`"
	DEVBASE=${NAME:0:7}
	if [ ! -d /sys/block/${DEVBASE} ]; then
		DEVBASE=${NAME:0:3}
	fi

	# Get the device model
	if [ -f /sys/block/$DEVBASE/device/model ]; then
		MODEL=`cat /sys/block/$DEVBASE/device/model`
	else
		MODEL="unknown device"
	fi

	# external?
	readlink -fn /sys/block/$DEVBASE/device | grep -qs 'pci\|ahci\|sata'
	EXTERNAL=$?

	# Bus the device is connected to
	BUS="`basename "$ID_BUS"`"
	if [ -z "$BUS" ]; then
		# if not specified, make one up
		if [ "$REMOVABLE" -eq "1" ]; then
			BUS=usb
		fi
	fi

	# Figure out a mount point to use
	LABEL=${ID_FS_LABEL}

	# If no label, try to come up with one
	if [[ -z "${LABEL}" ]]; then

		if [ "${EXTERNAL}" -eq "0" ]; then
			# we assume it's the internal harddisk
			LABEL="hdd"
		else
			# mount mmc block devices on /media/mcc
			if [ ${DEVBASE:0:6} = "mmcblk" ]; then
				LABEL="mmc"
			else
				if [ "$MODEL" == "USB CF Reader   " ]; then
					LABEL="cf"
				elif [ "$MODEL" == "Compact Flash   " ]; then
					LABEL="cf"
				elif [ "$MODEL" == "USB SD Reader   " ]; then
					LABEL="mmc"
				elif [ "$MODEL" == "USB SD  Reader  " ]; then
					LABEL="mmc"
				elif [ "$MODEL" == "SD/MMC          " ]; then
					LABEL="mmc"
				elif [ "$MODEL" == "USB MS Reader   " ]; then
					LABEL="mmc"
				elif [ "$MODEL" == "SM/xD-Picture   " ]; then
					LABEL="mmc"
				elif [ "$MODEL" == "USB SM Reader   " ]; then
					LABEL="mmc"
				elif [ "$MODEL" == "MS/MS-Pro       " ]; then
					LABEL="mmc"
				else
					LABEL="usb"
				fi
			fi
		fi
	fi

	# Check if we already have this mount point
	if [ ! -z "${LABEL}" ] && [ -d /media/$LABEL ]; then
		LABEL=
	fi

	# If no label, use the device name
	if [[ -z "${LABEL}" ]]; then
		LABEL="$NAME"
	fi

	# Create the mountpoint for the device	
	! test -d "/media/$LABEL" && mkdir -p "/media/$LABEL"

	# Silent util-linux's version of mounting auto
	if [ "x`readlink $MOUNT`" = "x/bin/mount.util-linux" ]; then
		MOUNT="$MOUNT -o silent"
	fi

	# If filesystem type is vfat, change the ownership group to 'disk', and
	# grant it with  w/r/x permissions.
	case $ID_FS_TYPE in
	vfat|fat)
		MOUNT="$MOUNT -o umask=007,gid=`awk -F':' '/^disk/{print $3}' /etc/group`"
		;;
	# TODO
	*)
		;;
	esac

	if ! $MOUNT -t auto $DEVNAME "/media/$LABEL"
	then
		logger "mount.sh/automount" "$MOUNT -t auto $DEVNAME \"/media/$LABEL\" failed!"
		rm_dir "/media/$LABEL"
	else
		logger "mount.sh/automount" "Auto-mount of [/media/$LABEL] successful"
		touch "/tmp/.automount-$LABEL"
	fi
}

rm_dir() {
	# We do not want to rm -r populated directories
	if test "`find "$1" | wc -l | tr -d " "`" -lt 2 -a -d "$1"
	then
		! test -z "$1" && rm -r "$1"
	else
		logger "mount.sh/automount" "Not removing non-empty directory [$1]"
	fi
}

# No ID_FS_TYPE for cdrom device, yet it should be mounted
name="`basename "$DEVNAME"`"
[ -e /sys/block/$name/device/media ] && media_type=`cat /sys/block/$name/device/media`

if [ "$ACTION" = "add" ] && [ -n "$DEVNAME" ] && [ -n "$ID_FS_TYPE" -o "$media_type" = "cdrom" ]; then
	if [ -x "$PMOUNT" ]; then
		$PMOUNT $DEVNAME 2> /dev/null
	elif [ -x $MOUNT ]; then
		$MOUNT $DEVNAME 2> /dev/null
	fi

	# If the device isn't mounted at this point, it isn't
	# configured in fstab (note the root filesystem can show up as
	# /dev/root in /proc/mounts, so check the device number too)
	if expr $MAJOR "*" 256 + $MINOR != `stat -c %d /`; then
		grep -q "^$DEVNAME " /proc/mounts || automount
	fi
fi

if [ "$ACTION" = "remove" ] || [ "$ACTION" = "change" ] && [ -x "$UMOUNT" ] && [ -n "$DEVNAME" ]; then
	for mnt in `cat /proc/mounts | grep "$DEVNAME" | cut -f 2 -d " " `
	do
		$UMOUNT $mnt
	done

	LABEL=`echo $mnt | cut -c 8-`
	# logger "remove device $LABEL"
	# Remove empty directories from auto-mounter
	test -e "/tmp/.automount-$LABEL" && rm_dir "/media/$LABEL"
fi