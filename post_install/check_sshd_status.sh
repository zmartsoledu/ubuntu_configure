#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

systemctl status ssh > /dev/null 2>&1
if [ "$?" -eq '0' ]; then
	echo -e "ssh-server is running\n"
	offser_ssh_port_change="y"
	if [ -z "$SSH_TTY" ] && [ -z `pstree -ps $$ | grep "sshd("` ]; then
		ssh_disable_selection="";
		while [ "$ssh_disable_selection" != "y" ] && [ "$ssh_disable_selection" != "n" ]; do
		    read -t 10 -p "ssh server is enabled, do you want to disable it [Y/n]: " ssh_disable_selection;
		    ssh_disable_selection=${ssh_disable_selection,,};
		    if [ -z "$ssh_disable_selection" ]; then
			ssh_disable_selection="y"
		    fi
		done

		if [ "${ssh_disable_selection}" == "y" ]; then
		    echo "disabling ssh-server"
		    sudo systemctl stop ssh && sudo systemctl disable ssh && sudo systemctl status ssh
		    offser_ssh_port_change="n"
		else
		    echo "leaving ssh-server enabled"
		fi
	else
		echo "Seems like you are connected via ssh, not offering to disable. You can disable it manually by running the line below"
		echo -e "sudo systemctl stop ssh && sudo systemctl disable ssh && sudo systemctl status ssh\n"
	fi

	if [ "$offser_ssh_port_change" == "y" ]; then
	    ssh_new_port="";
	    while ! [ "$ssh_new_port" -eq "$ssh_new_port" ] 2>/dev/null; do
		read -t 10 -p "enter ssh-server port number [22]: " ssh_new_port;
		if [ -z "$ssh_new_port" ]; then
		    ssh_new_port='22'
		fi
	    done

	    if [ ! -z "$ssh_new_port" ] && [ "$ssh_new_port" != "22" ]; then
		sed -ri 's@^#?(Port ).*@\1'$ssh_new_port'@' /etc/ssh/sshd_config
		echo "new ssh " `grep -E "^Port " /etc/ssh/sshd_config` " . Restart the system or sshd to take effect"
	    fi
	fi
else
	echo "ssh-server is not running"
fi

func_print_info_message "script end `basename "$0"`"
