#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# Switch from netplan to NetworkManager
netplan_used=0
which netplan > /dev/null
if [ $? -eq 0 ]; then
	netplan_used=1
	
	# Check if already configured for NetworkManager
	if [ -f /etc/netplan/01-network-manager-all.yaml ]; then
		func_print_info_message "NetworkManager already configured in netplan"
	else
		# Detect first available ethernet-style interface name
		iface=""
		for try in eno ens enp eth en* p*; do
			candidate=$(ls /sys/class/net 2>/dev/null | grep -E "^$try" | head -n1)
			if [ -n "$candidate" ]; then
				iface="$candidate"
				break
			fi
		done
		if [ -z "$iface" ]; then
			# fallback to first non-loopback interface
			iface=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -n1)
		fi
		if [ -z "$iface" ]; then
			func_print_warn_message "No network interface detected; writing minimal netplan config"
			iface=eth0
		fi
		# Create NetworkManager netplan config from repo template
		if [ -f "$(dirname "$0")/netplan_template.yaml" ]; then
			cp "$(dirname "$0")/netplan_template.yaml" /etc/netplan/01-network-manager-all.yaml
			sed -i "s/__IFACE__/$iface/" /etc/netplan/01-network-manager-all.yaml
		else
			cat > /etc/netplan/01-network-manager-all.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $iface:
      dhcp4: true
      dhcp6: false
      optional: true
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1, 8.8.4.4]
EOF
		fi
		# Set secure permissions (netplan requires restrictive perms)
		chmod 0600 /etc/netplan/01-network-manager-all.yaml || true
		# Disable old installer config (rename with trailing underscore)
		if [ -f /etc/netplan/00-installer-config.yaml ]; then
			mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml_ || true
		fi
		# Install NetworkManager early so netplan apply won't fail
		apt_update
		apt_install_auto_yes "network-manager"
		systemctl enable --now NetworkManager 2>/dev/null || true
		# Make other netplan YAMLs optional by renaming with trailing underscore
		for f in /etc/netplan/*.yaml; do
			if [ "$f" != "/etc/netplan/01-network-manager-all.yaml" ]; then
				mv "$f" "${f}_" || true
			fi
		done
		
		func_print_ok_message "Configured NetworkManager in netplan for interface $iface"
	fi
fi

# Apply NetworkManager configuration (idempotent; safe to run multiple times)
if [ $netplan_used -eq 1 ]; then
	rm -rf /etc/resolv.conf
	mkdir -p /run/resolvconf/
	touch /run/resolvconf/resolv.conf
	
	# Temporary DNS until NetworkManager takes over
	echo "nameserver 8.8.8.8" > /run/resolvconf/resolv.conf
	ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf
	
	netplan apply 2>/dev/null || true
	systemctl restart NetworkManager 2>/dev/null || true
	
	apt_group_install_auto_yes "resolvconf"
	sudo sed -i 's/#FallbackDNS=.*/FallbackDNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf
	
	# Second apply; guard NetworkManager start similarly
	if systemctl list-unit-files | grep -q "NetworkManager.service"; then
		netplan apply 2>/dev/null || true
		systemctl restart NetworkManager 2>/dev/null || true
		systemctl restart systemd-resolved 2>/dev/null || true
	else
		netplan generate 2>/dev/null || true
	fi
fi

func_print_info_message "script end `basename \"$0\"`"

exit 0
