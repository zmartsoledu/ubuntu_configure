#!/bin/bash

source ./common_bash_funcs.sh

# GConf2 is obsolete in Ubuntu 24.04; skip terminal theme configuration
func_print_warn_message "Skipping gnome-terminal solarize (gconftool-2 obsolete in Ubuntu 24.04)"
func_print_info_message "Use dconf/gsettings for GNOME terminal customization if needed"

wget https://raw.github.com/seebi/dircolors-solarized/master/dircolors.256dark -O ~/.dircolors 2>/dev/null || true

func_print_info_message "script end `basename \"$0\"`"
