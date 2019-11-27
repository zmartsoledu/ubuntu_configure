#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

grep "echoCancel" /etc/pulse/default.pa >/dev/null 2>&1
if [ "$?" != "0" ]; then
	echo "microphone noise cancellation option: being added"
cat <<EOT >> /etc/pulse/default.pa
### Enable Echo/Noise-Cancelation
load-module module-echo-cancel aec_method=webrtc aec_args="analog_gain_control=0 digital_gain_control=1" source_name=echoCancel_source sink_name=echoCancel_sink
set-default-source echoCancel_source
set-default-sink echoCancel_sink
EOT

	pulseaudio -k
	pulseaudio --start
else
	echo "microphone noise cancellation option: already added, skipping"
fi

func_print_info_message "script end `basename "$0"`"
