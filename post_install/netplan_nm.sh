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
		# Detect ethernet and wireless interfaces
		eth_iface=""
		for try in eno ens enp eth en* p*; do
			candidate=$(ls /sys/class/net 2>/dev/null | grep -E "^$try" | head -n1)
			if [ -n "$candidate" ]; then
				eval eth_iface="$candidate"
				break
			fi
		done
		# fallback to first non-loopback if no ethernet detected
		if [ -z "$eth_iface" ]; then
			eth_iface=$(ls /sys/class/net 2>/dev/null | grep -v lo | grep -v -E '^(lo|sit|tun|tap|docker|veth|br|virbr|vmnet)' | head -n1)
		fi
		# Collect wifi interfaces (presence of wireless dir)
		wifi_ifaces=""
		for i in $(ls /sys/class/net 2>/dev/null); do
			if [ -d "/sys/class/net/$i/wireless" ]; then
				wifi_ifaces="$wifi_ifaces $i"
			fi
		done
		# Build netplan file from templates
		base_template="$(dirname "$0")/netplan_base.yaml"
		eth_template="$(dirname "$0")/netplan_template.yaml"
		wifi_template="$(dirname "$0")/netplan_wifi_template.yaml"
		# Start with base template; do not fall back to heredoc if missing
		if [ -f "$base_template" ]; then
			cp "$base_template" /etc/netplan/01-network-manager-all.yaml
		else
			func_print_fail_message "Netplan base template missing: $base_template. Skipping netplan generation."
			func_print_info_message "Create and check in netplan_base.yaml, netplan_template.yaml, netplan_wifi_template.yaml and re-run."
			exit 0
		fi
		# Append ethernet fragment if present
		if [ -n "$eth_iface" ] && [ -f "$eth_template" ]; then
			cat "$eth_template" >> /etc/netplan/01-network-manager-all.yaml
			sed -i "s/__IFACE__/$eth_iface/" /etc/netplan/01-network-manager-all.yaml || true
		fi
		# Append wifi fragment(s) if present
		if [ -n "$(echo $wifi_ifaces | xargs)" ] && [ -f "$wifi_template" ]; then
			# Add wifis block header if not already present
			if ! grep -q "^  wifis:" /etc/netplan/01-network-manager-all.yaml; then
				echo "  wifis:" >> /etc/netplan/01-network-manager-all.yaml
			fi
			for wifi in $wifi_ifaces; do
				# append a per-iface wifi fragment and replace placeholder
				cat "$wifi_template" >> /etc/netplan/01-network-manager-all.yaml
				sed -i "s/__WIFI_IFACE__/$wifi/" /etc/netplan/01-network-manager-all.yaml || true
			done
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
