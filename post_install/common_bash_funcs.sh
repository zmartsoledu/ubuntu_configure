#!/bin/bash

COL_RED="\e[31m"
COL_GRN="\e[32m"
COL_YEL="\e[33m"
COL_BLU="\e[34m"
COL_MAG="\e[35m"
COL_DFL="\e[39m"

function func_print_ok_message() {
    echo -e "${COL_GRN}`date +"%D-%T"` ok  :${COL_DFL} ""$1" | tee -a install.log
}

function func_print_fail_message() {
    echo -e "${COL_RED}`date +"%D-%T"` fail:${COL_DFL} ""$1" | tee -a install.log
}

function func_print_warn_message() {
    echo -e "${COL_YEL}`date +"%D-%T"` warn:${COL_DFL} ""$1" | tee -a install.log
}

function func_print_info_message() {
    echo -e "${COL_BLU}`date +"%D-%T"` info:${COL_DFL} ""$1" | tee -a install.log
}

function func_print_dbg_message() {
    if [ ! -z "$BASH_GEN_DBG" ]; then
	echo -e "${COL_MAG}`date +"%D-%T"` warn:${COL_DFL} ""$1" | tee -a install.log
    fi
}

function func_print_ok_fail_on_ret_code() {
    local __ret_code="$1"
    local __msg="$2"

    if [ "$__ret_code" == "0" ]; then
        func_print_ok_message "$2"
    else
        func_print_fail_message "$2"
    fi
}

function func_print_ok_info_on_ret_code() {
    local __ret_code="$1"
    local __msg="$2"

    if [ "$__ret_code" == "0" ]; then
        func_print_ok_message "$2"
    else
        func_print_info_message "$2"
    fi
}

function func_install_latest_deb_from_github() {
	local __github_comp_name="$1"

	local __dl_url=$(curl -s https://api.github.com/repos/${__github_comp_name}/releases/latest | grep "browser_download_url.*deb" | cut -d : -f 2,3 | tr -d \" | xargs)
	if [ ! -z "${__dl_url}" ]; then
		echo -e "\n\nattempting to download and install: $__github_comp_name"
		wget "${__dl_url}"
		sudo dpkg -i *.deb

		sudo apt install -f -y
		func_print_ok_fail_on_ret_code "$?" "deb_install: $__github_comp_name"
		rm *.deb
	else
		func_print_fail_message "cannot extract dload url for $__github_comp_name"
	fi
}

function add_ppa() {
  local __ppa_name=""

  for __ppa_name_to_check in "$@"; do
    grep -h "^deb.*$__ppa_name_to_check" /etc/apt/sources.list.d/* > /dev/null 2>&1
    if [ "$?" != "0" ]
    then
        local __is_ppa_valid=""
        check_if_ppa_is_valid "__is_ppa_valid" "$__ppa_name_to_check"
        if [ "$__is_ppa_valid" == "0" ]; then
            echo "Adding ppa:$__ppa_name_to_check"
            sudo add-apt-repository -y ppa:$__ppa_name_to_check
            func_print_ok_message "add_ppa: $__ppa_name_to_check"
        else
            func_print_fail_message "add_ppa: $__ppa_name_to_check"
        fi
    else
        func_print_info_message "repo already exists ppa:$__ppa_name_to_check"
    fi
  done
}

function check_all_ppa_validity() {
    local __invalid_ppa_list=()

    for __ppa_to_chk in `grep -RoPish "ppa.launchpad.net/[^/]+/[^/ ]+" /etc/apt | sort -u | uniq | cut -d"/" -f2-`; do
        check_if_ppa_is_valid "__is_ppa_valid" "$__ppa_to_chk"
        if [ "$__is_ppa_valid" == "0" ]; then
            func_print_ok_message "check_ppa: $__ppa_to_chk"
        else
            func_print_fail_message "check_ppa: $__ppa_to_chk"
            __invalid_ppa_list+=("$__ppa_to_chk")
        fi
    done
    eval "$1=(${__invalid_ppa_list[*]})"
}

function check_if_ppa_is_valid() {
    local __ppa_name="$2"
    local __ppa_prefix=$(echo $__ppa_name | cut -d"/" -f1)
    local __ppa_suffix=${__ppa_name##*/}

    curl -fsSL https://launchpad.net/~"$__ppa_prefix"/+archive/ubuntu/"$__ppa_suffix" &>/dev/stdout | grep "\"`lsb_release -sc`\"" -m1 >/dev/null 2>&1
    eval "$1=\"$?\""
}

function add_to_sources_list() {
    local __repo_base_link="$1"
    local __flavour="$2"
    local __version_name=`lsb_release -sc`
    local __repo_link="deb $__repo_base_link $__version_name $__flavour"

    grep -h "^$__repo_link" /etc/apt/sources.list > /dev/null 2>&1
    if [ "$?" != "0" ]
    then
        curl -fsSL "${__repo_base_link}/dists/${__version_name}/Release" >/dev/null 2>&1
        if [ "$?" == "0" ]; then 
            echo "Adding repo:$__repo_link"
            sudo add-apt-repository -y "$__repo_link"
            func_print_ok_message "repo add: $__repo_link"
        else
            func_print_fail_message "repo add: $__repo_link"
        fi      
    else
      func_print_info_message "repo already exists: $__repo_link"
    fi
}

function apt_group_install_auto_yes() {
    local __package_list="$1"
    local __extra_apt_opts="$2"

    local __pkg_to_inst=""
    for __pkg_to_inst in $__package_list; do
        apt_install_auto_yes "$__pkg_to_inst" "$__extra_apt_opts"
    done
}

function apt_install_auto_yes() {
    local __package_name="$1"
    local __extra_apt_opts="$2"

    if [ ! -z "$__package_name" ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y "$__package_name" $extra_apt_opts
	func_print_ok_fail_on_ret_code "$?" "install_apt $__package_name"
    else
        func_print_info_message "install skipped for empty package name"
    fi
}

function snap_group_install() {
    local __snap_package_list="$1"
    local __extra_snap_opts="$2"

    local __snap_pkg_to_inst=""
    for __snap_pkg_to_inst in $__snap_package_list; do
        snap_install "$__snap_pkg_to_inst" "$__extra_snap_opts"
    done
}

function snap_install() {
    local __snap_pkg_name="$1"
    local __snap_opts="$2"

    sudo snap install "$__snap_pkg_name" $__snap_opts
    func_print_ok_fail_on_ret_code "$?" "install_snap $__snap_pkg_name $__snap_opts"
}

function apt_update() {
    sudo apt-get update
    func_print_ok_fail_on_ret_code "$?" "apt_update"
}

function apt_upgrade() {
    apt_update
    sudo apt-get upgrade -y
    func_print_ok_fail_on_ret_code "$?" "apt_upgrade"
}

function custom_reboot() {
    # comment out the line below to stop reboots, for testing
    sudo sync && sudo reboot $1
    echo ""
}

