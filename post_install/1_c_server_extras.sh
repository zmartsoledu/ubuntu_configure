#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# point /bin/sh to bash
ln -sf /bin/bash /bin/sh

# add some aliases
if [ ! -s ~/.bash_aliases ]; then
cat <<EOT >> ~/.bash_aliases
function cfind() {
    job_count=$((\`grep -c ^processor /proc/cpuinfo\`-2))
    find . -type f -name "\${1}" -print0 | xargs -0 -n1 -P\${job_count} grep "\${2}" -Hn"\${3}"
}

# docker aliases
# bitnami/git provides a more recent version but the size is ~600MB as opposed to ~30MB
alias d-git="docker run -ti --rm -v \${HOME}:/root -v \$(pwd):/git alpine/git:latest"
alias i="ip -c -brie a"
alias tpr="tput reset"
EOT
fi

echo '#!/bin/bash' > run_manually.sh
echo "sudo sed -ri 's@^#WaylandEnable@WaylandEnable@' /etc/gdm3/custom.conf > /dev/null 2>&1" >> run_manually.sh
echo "sudo sed -ri 's@\"quiet\"@\"\"@' /etc/default/grub > /dev/null 2>&1" >> run_manually.sh
echo "sudo update-grub" >> run_manually.sh

./check_sshd_status.sh
./general.sh
./docker.sh
./azure.sh
./groups.sh
./virtualbox.sh
./vagrant.sh
./libvirt_kvm.sh
./vagrant_plugins.sh
./katoolin.sh
./disk_man.sh

echo "removing i386 packages, please wait..."
apt-get purge ".*:i386" -y > /dev/null 2>&1
echo "continuing to remove i386 packages, please wait..."
dpkg --remove-architecture i386 > /dev/null 2>&1

if [ -f "run_manually.sh" ]; then
	chmod 755 run_manually.sh
	./run_manually.sh
fi

func_print_info_message "script end `basename "$0"`"

echo "server extras are completed. please restart your pc and continue with the pre-graph setup"

exit 0
