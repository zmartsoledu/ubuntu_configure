#!/bin/bash

if [ `id -u` != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit -1
fi

source ./common_bash_funcs.sh

enc_selection="";
while [ "$enc_selection" != "y" ] && [ "$enc_selection" != "n" ]; do
	read -t 10 -p "Do you want to add other internal disks to the encrypted volumes [y/N]: " enc_selection;
	enc_selection=${enc_selection,,};
	if [ -z "$enc_selection" ]; then
		enc_selection="n"
	fi
done

if [ "${enc_selection}" == "n" ]; then
	echo "skipping adding other disks to the encrypted volumes"
else
	main_vg=$(vgscan | sed -r 's@.*"(.*)".*@\1@' | head -n2 | tail -n1)
	luks_key_folder="/etc/luks-keys"
	mkdir -p ${luks_key_folder}

	for hdd_drv in `lsblk -do name,tran | grep "sata" | grep -E "^sd" | cut -d" " -f1`; do
		device_to_crypt="/dev/${hdd_drv}"
		pvdisplay | grep "/dev" | grep "${hdd_drv}"
		if [ "$?" -eq '0' ]; then
			echo "${device_to_crypt} is already in a vg, skipping"
		else
			echo "${device_to_crypt} is not in a vg"

			fdisk -l ${device_to_crypt}
			wipe_selection="";
			while [ "$wipe_selection" != "y" ] && [ "$wipe_selection" != "n" ]; do
				read -p "Wipe data on ${device_to_crypt}? [y/n]: " wipe_selection;
				wipe_selection=${wipe_selection,,};
			done

			if [ "${wipe_selection}" == "y" ]; then
				echo "wiping ${device_to_crypt}"

				dd if=/dev/zero of=${device_to_crypt} bs=1 count=64 seek=446 conv=notrunc
				for v_partition in $(parted -s ${device_to_crypt} print|awk '/^ / {print $1}')
				do
					umount ${device_to_crypt}${v_partition} > /dev/null 2>&1
					parted -s ${device_to_crypt} rm ${v_partition} > /dev/null 2>&1
				done

				parted ${device_to_crypt} --script -- mklabel gpt
				parted ${device_to_crypt} --script --align optimal -- mkpart primary ext4 0% 100%
				parted ${device_to_crypt} print
			fi

			for partition_full_path in `ls ${device_to_crypt}[0-9]`; do
				partition_name=`echo "${partition_full_path##*/}"`
				crypt_end_point=${partition_name}_crypt
				mount_name="${crypt_end_point}"

				crypt_device="/dev/mapper/${crypt_end_point}"
				secret_key_file_path="${luks_key_folder}/secret_key_${crypt_end_point}"

				echo "umounting ${partition_full_path} and ${crypt_device}"
				umount ${partition_full_path} > /dev/null 2>&1
				umount ${crypt_device} > /dev/null 2>&1

				luks_selection="n";
				cryptsetup isLuks ${partition_full_path} > /dev/null 2>&1
				is_luks="$?"
				if [ "$is_luks" == "0" ]; then
					luks_selection="";
					while [ "$luks_selection" != "y" ] && [ "$luks_selection" != "n" ]; do
						read -p "Partition ${partition_full_path} is already luks, do you want to retain it [y/n]: " luks_selection;
						luks_selection=${luks_selection,,};
					done
				fi

				if [ "${luks_selection}" == "n" ]; then
					echo "luks formatting ${partition_full_path}"
					#cryptsetup luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 --verify-passphrase ${partition_full_path}
					cryptsetup -q luksFormat ${partition_full_path}

					echo "luksOpen ${partition_full_path} as ${crypt_end_point}"
					cryptsetup luksOpen ${partition_full_path} ${crypt_end_point}

					echo "running mkfs on ${crypt_device}"
					mkfs.ext4 -F ${crypt_device}
				else
					cryptsetup luksClose ${crypt_end_point} > /dev/null 2>&1

					echo "luksOpen ${partition_full_path} as ${crypt_end_point}"
					cryptsetup luksOpen ${partition_full_path} ${crypt_end_point}
					if [ "$?" -eq '0' ]; then
						blkid | grep "${crypt_device}:" | grep "TYPE=\"ext"
						if [ "$?" != "0" ]; then
							format_selection="";
							while [ "$format_selection" != "y" ] && [ "$format_selection" != "n" ]; do
								read -p "${crypt_device} is not ext formatted. Do you want to format it [y/n]: " format_selection;
								format_selection=${format_selection,,};
							done

							if [ "${format_selection}" == "y" ]; then
								echo "wiping any previous lvm info off ${crypt_device}"
								pvremove -y -ff ${crypt_device}
								vgreduce -y -f $main_vg ${crypt_device}
								vgreduce -y -f $main_vg --removemissing
								pvremove -y -ff ${crypt_device}

								echo "running mkfs on ${crypt_device}"
								mkfs.ext4 -F ${crypt_device}
							else
								cryptsetup luksClose ${crypt_end_point} > /dev/null 2>&1
								continue;
							fi
						fi
					else
						echo "failed luksOpen ${crypt_device}"
						continue;
					fi
				fi

				device_to_crypt_uuid=$(blkid ${partition_full_path} | sed -r 's@.*UUID="(.*)" TYPE.*@\1@')
				sed -i '/'${device_to_crypt_uuid}'/d' /etc/crypttab

				cryptsetup -v luksKillSlot ${partition_full_path} 1

				dd if=/dev/urandom of=${secret_key_file_path} bs=512 count=8
				cryptsetup -v luksAddKey ${partition_full_path} ${secret_key_file_path}

				cryptsetup -v luksClose ${crypt_end_point}
				cryptsetup -v luksOpen ${partition_full_path} ${crypt_end_point} --key-file=${secret_key_file_path}
				cryptsetup -v luksClose ${crypt_end_point}

				if [ "$?" -eq '0' ]; then
					echo "success: ${secret_key_file_path} can decrypt ${partition_full_path}"
				fi

				crypttab_entry="${crypt_end_point} UUID=${device_to_crypt_uuid} ${secret_key_file_path} luks"
				echo "${crypttab_entry}" >> /etc/crypttab
				echo "added to crypttab: ${crypttab_entry}"
				cryptdisks_start ${crypt_end_point}

				fstab_entry="${crypt_device} /media/${mount_name} ext4    defaults   0       2"
				sed -i '/'${mount_name}\ '/d' /etc/fstab
				echo "${fstab_entry}" >> /etc/fstab
				echo "added to fstab: ${fstab_entry}"

				mkdir -p /media/${mount_name}
				umount /media/${mount_name} > /dev/null 2>&1
				mount ${crypt_device}
				chown $USER:$USER /media/${mount_name} -R
			done
		fi
	done
	echo ""
	mount
	pvdisplay
	vgdisplay
	lvmdiskscan
	blkid
fi

func_print_info_message "script end `basename "$0"`"
