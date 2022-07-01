#!/bin/bash

INSTALL_DIR=$1
if [ -z "$INSTALL_DIR" ]; then
	INSTALL_DIR="$HOME/Anaconda"
fi

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

wget https://www.anaconda.com/distribution -O distribution
installer_dl_link=$(grep -o "https://.*Anaconda3.*Linux-x86_64.sh" distribution | cut -d"\"" -f1 | tail -n1)
rm -rf distribution
wget $installer_dl_link
installer_sh="${installer_dl_link##*/}"

exit_code="-1"
if [ -f $installer_sh ]; then
	chmod 755 $installer_sh
	sha256sum $installer_sh
	which conda > /dev/null 2>&1
	if [ "$?" != '0' ]; then
		echo "detected previous installation of conda, updating"
		update_flag="-u -f"
	else
		echo "installing conda fresh to $INSTALL_DIR"
		mkdir -p $INSTALL_DIR
	fi
	
	sudo -u $SUDO_USER sh -c "sh $installer_sh -b -p ${INSTALL_DIR} ${update_flag}"
	sudo -u $SUDO_USER sh -c "${INSTALL_DIR}/bin/conda shell.bash hook"
	echo "export PATH=\$PATH:${INSTALL_DIR}/condabin" >> run_manually.sh
	echo "conda init" >> run_manually.sh
	echo "conda install -y anaconda-clean" >> run_manually.sh
	echo "added required lines to run_manually_sh"
	sudo chown $SUDO_USER run_manually.sh
	chmod 755 run_manually.sh
	rm $installer_sh
	exit_code="0"
else
	func_print_fail_message "$installer_sh not found"
fi

func_print_info_message "script end `basename "$0"`"
exit $exit_code
