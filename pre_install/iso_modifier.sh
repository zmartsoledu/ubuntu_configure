#!/bin/sh

function func_print_help() {
	printf "
  usage:
	--iso: original iso img path
	--usb: usb device to install to, ie /dev/sdc. if omitted, only local iso is created.
	--ncl: no cleanup, which means do not delete the modified copy of the iso contents
	

	if you are unsure;
	
	- ubuntu images can be downloaded from http://cdimage.ubuntu.com/releases or http://releases.ubuntu.com/, 
	  and it is recommended that you pick a non-live server image ie:
	wget http://cdimage.ubuntu.com/releases/18.04.2/release/ubuntu-18.04.2-server-amd64.iso
	wget http://releases.ubuntu.com/18.04/ubuntu-18.04.2-desktop-amd64.iso

	- available usb drives, without the /dev/ prefix, can be listed by:
	lsblk -do name,tran | grep \"usb\" | grep -E \"^sd\" | cut -d\" \" -f1
	\n"
}

function check_return_code() {
	local __val_to_check="$1"
	if [ "$__val_to_check" != '0' ]; then
		echo "[err]: problem detected, exiting..."
		exit 127
	fi
}

function list_usb_mediums() {
	echo ""
	echo "installation candidate usb mediums: "
	lsblk -do name,tran | grep "usb" | grep -E "^sd" | cut -d" " -f1
}

#https://askubuntu.com/questions/109898/how-to-change-the-password-of-an-encrypted-lvm-system-done-with-the-alternate-i
#https://linuxconfig.org/legacy-bios-uefi-and-secureboot-ready-ubuntu-live-image-customization

# generate key for usb
# add new lvm for the second disk

if [ `id -u` -ne '0' ]; then
	func_print_help
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

ORIG_IMG=""
TARGET_USB_MEDIUM=""

if [ "$#" -eq 0 ]; then
	echo "not enough parameters supplied"
	func_print_help
	exit 127
fi

unset NCL_STATUS
while [ "$#" -gt 0 ]; do
  case $1 in
    --iso)
      ORIG_IMG="$2"
      shift
      ;;
    --usb)
      TARGET_USB_MEDIUM="$2"
      shift
      ;;
    --ncl)
      NCL_STATUS="1"
      ;;
    --help|*)
      func_print_help
      exit 127
      ;;
  esac
  shift
done

if [ ! -f "$ORIG_IMG" ]; then
	echo "there is no valid img file provided: $ORIG_IMG"
	func_print_help
	exit 127
fi

if [ -z "$TARGET_USB_MEDIUM" ]; then
	list_usb_mediums

	echo ""
	echo -e "no usb installation medium is provided. if this is unintended, next time run with the --usb option.\n"
elif [ ! -e "${TARGET_USB_MEDIUM}" ]; then
	echo "not a valid usb medium: ${TARGET_USB_MEDIUM}"
	list_usb_mediums
	exit 127

fi

iso_ver_num=$(echo "${ORIG_IMG}" | grep -Eo "[0-9]{2}\.[0-9]{2}(\.[0-9]{1,3})?")
iso_flavour=$(echo "${ORIG_IMG}" | sed -r 's@.*-(.*)-.*@\1@')

echo "flavour: ${iso_flavour}, version: ${iso_ver_num}"

ORIG_ISO_MOUNT_POINT="/mnt/ubuntu_orig_iso_${iso_ver_num}"
MODIFIED_ISO_CONTENTS="/tmp/ubuntu_${iso_ver_num}_iso_modified"
MODIFIED_ISO="/tmp/ubuntu-${iso_ver_num}-modified.iso"
USB_MOUNT_POINT="/mnt/target_usb_med"

echo "installing required binaries for iso modifications"
apt-get update -y && apt-get install -y genisoimage isolinux unetbootin parted xorriso dumpet squashfs-tools gddrescue util-linux e2fsprogs
check_return_code "$?"

echo "mounting the original iso"
rm -rf ${MODIFIED_ISO_CONTENTS}
mkdir -p ${MODIFIED_ISO_CONTENTS}
xorriso -osirrox on -indev ${ORIG_IMG} -extract / ${MODIFIED_ISO_CONTENTS}
check_return_code "$?"

echo "copying custom files into iso"
cp *.seed ${MODIFIED_ISO_CONTENTS}/preseed/.
check_return_code "$?"

cp target_skeleton ${MODIFIED_ISO_CONTENTS}/. -R
check_return_code "$?"

if [ "${iso_flavour}" == "server" ]; then
	cp txt.cfg ${MODIFIED_ISO_CONTENTS}/isolinux/.
	check_return_code "$?"

	cp grub.cfg ${MODIFIED_ISO_CONTENTS}/boot/grub/.
	check_return_code "$?"
fi

if [ '0' -eq '1' ]; then
	echo "modifying the squashfs-root"
	rm -rf squashfs-root

	ORIG_SQUASHFS_LOCATION="${MODIFIED_ISO_CONTENTS}/install/filesystem.squashfs"
	if [ ! -f "${ORIG_SQUASHFS_LOCATION}" ]; then
		ORIG_SQUASHFS_LOCATION="${MODIFIED_ISO_CONTENTS}/casper/filesystem.squashfs"
	fi
	echo "identified the orig squashfs location as: ${ORIG_SQUASHFS_LOCATION}"

	unsquashfs ${ORIG_SQUASHFS_LOCATION}
	check_return_code "$?"

	cp target_skeleton/* squashfs-root/. -R
	check_return_code "$?"

	mksquashfs squashfs-root/ ${ORIG_SQUASHFS_LOCATION}
	check_return_code "$?"

	if [ -z "$NCL_STATUS" ]; then
		rm -rf squashfs-root
	else
		echo "NCL is set, not deleting the modified squashfs-root"
	fi
else
	echo "skipping the squashfs modifications"
fi

echo "extracting the hybrid MBR"
dd if=${ORIG_IMG} bs=512 count=1 of=${MODIFIED_ISO_CONTENTS}/isolinux/isohdpfx.bin
check_return_code "$?"

echo "packing the modified iso: ${MODIFIED_ISO}"
cd ${MODIFIED_ISO_CONTENTS}/
echo "changed dir to: $PWD"
xorriso -as mkisofs -isohybrid-mbr isolinux/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -o ${MODIFIED_ISO} .

check_return_code "$?"
cd -
echo "changed dir to: $PWD"

echo ">>>>>>>>>> dumping info for: ${MODIFIED_ISO}"
fdisk -lu ${MODIFIED_ISO}
dumpet -i  ${MODIFIED_ISO}
isoinfo -d -i ${MODIFIED_ISO}
xorriso -indev ${MODIFIED_ISO} -toc -pvd_info
echo "end of info for: ${MODIFIED_ISO} <<<<<<<<<<"

if [ ! -z "$TARGET_USB_MEDIUM" ]; then
	echo "unmounting ${TARGET_USB_MEDIUM}"
	umount ${TARGET_USB_MEDIUM}* > /dev/null 2>&1

	echo "writing ${MODIFIED_ISO} to ${TARGET_USB_MEDIUM}"
	ddrescue ${MODIFIED_ISO} ${TARGET_USB_MEDIUM} --force -D
	check_return_code "$?"
fi

if [ -z "$NCL_STATUS" ]; then
	echo "final clean ups"
	umount $ORIG_ISO_MOUNT_POINT > /dev/null 2>&1
	rm -rf ${MODIFIED_ISO_CONTENTS}
else
	echo "NCL is set, not deleting ${MODIFIED_ISO_CONTENTS}"
fi

if [ ! -z "$TARGET_USB_MEDIUM" ]; then
	echo "allocating all the free space on ${TARGET_USB_MEDIUM} to a new partition"
	# this isn't elegant at all but hey ho...
	echo -e "n\np\n\n\n\nw" | fdisk ${TARGET_USB_MEDIUM}

	new_partition=$(fdisk -l ${TARGET_USB_MEDIUM} | tail -n1 | cut -d" " -f1)

	umount ${TARGET_USB_MEDIUM}* > /dev/null 2>&1
	blockdev --rereadpt ${TARGET_USB_MEDIUM}
	hdparm -z ${TARGET_USB_MEDIUM}
	if [ -e "${new_partition}" ]; then
		echo "formatting ${new_partition}"
		mkfs.ext4 -F ${new_partition}
		e2label ${new_partition} XTRA_SPC
	fi

	ls -l ${TARGET_USB_MEDIUM}*
	fdisk -l ${TARGET_USB_MEDIUM}
	lsblk ${TARGET_USB_MEDIUM} -o NAME,SIZE,LABEL
fi

echo ""
echo "you can test the iso and pendrive with following"
echo "sudo apt-get -y update && sudo apt-get install -y qemu qemu-kvm ovmf"
echo "qemu-img create myimage.img 10G"
echo "or, if you have enough free space,"
echo "qemu-img create myimage.img 30G"
echo "depending on the available free memory on your system, you might want to increase the memory assigned to qemu by changing the value afer -m, it is in MBs"
echo "sudo qemu-system-x86_64 -m 2000 -boot d -drive id=disk,file=myimage.img,if=none,format=raw -device ahci,id=ahci -device ide-drive,drive=disk,bus=ahci.0 --enable-kvm -cdrom ${MODIFIED_ISO}"

if [ ! -z "$TARGET_USB_MEDIUM" ]; then
	echo "sudo qemu-system-x86_64 -m 2000 -boot d -drive id=disk,file=myimage.img,if=none,format=raw -device ahci,id=ahci -device ide-drive,drive=disk,bus=ahci.0 --enable-kvm -cdrom ${TARGET_USB_MEDIUM}"
fi

echo "if you finish the installation and decide to boot the installed image, change the the -boot d option to -boot c"
echo "to use (u)efi, you can copy the /usr/share/qemu/OVMF.fd file to local directory and pass the -bios OVMF.fd option"
echo "sudo rm -rf myimage.img"

echo ""
echo "[ok]: finished without errors, good luck..."
exit 0
