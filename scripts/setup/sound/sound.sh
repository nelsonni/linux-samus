#!/bin/bash

# 1. Copy firmware
if [ -d "/lib/firmware" ]; then
  sudo cp -r ../../../firmware/* /lib/firmware
elif [ -d "/usr/lib/firmware" ]; then
  sudo cp -r ../../../firmware/* /usr/lib/firmware
else
  echo "Could not find firmware directory, skipping firmware install"
fi

# 2. Set card order
sudo cp modprobe.d/alsa-bdwrt5677.conf /etc/modprobe.d

# 3. Set verb
echo "Setting sound card UCM verb"
ALSA_CONFIG_UCM=ucm/ alsaucm -c bdw-rt5677 set _verb HiFi
if [ ! $? -eq 0 ]; then
  echo "!!Failed to set UCM verb, make sure 'alsaucm' is installed"
  exit 1
fi

# 4. Set microphone device
egrep -q '^[ 	]*load-module module-alsa-source device=hw:1,1' /etc/pulse/default.pa
if [ $? -eq 0 ]; then
	sudo sed -i '/^[ 	]*load-module module-alsa-source device=hw:1,1/d' /etc/pulse/default.pa
fi
egrep -q '^[ 	]*load-module module-alsa-source device=hw:1,2' /etc/pulse/default.pa
if [ $? -eq 0 ]; then
	sudo sed -i '/^[ 	]*load-module module-alsa-source device=hw:1,2/d' /etc/pulse/default.pa
fi
egrep -q '^[ 	]*load-module module-alsa-source device=hw:0,1' /etc/pulse/default.pa
egrep -q '^[ 	]*load-module module-alsa-source device=hw:0,2' /etc/pulse/default.pa
alreadyset=$?
if [ ! $alreadyset -eq 0 ]; then
  echo "Updating PulseAudio config with microphone hardware info"
  sudo cp /etc/pulse/default.pa /etc/pulse/default.pa.orig
  sudo sed -i '/load-module module-udev-detect/ i load-module module-alsa-source device=hw:0,1' /etc/pulse/default.pa
  sudo sed -i '/load-module module-udev-detect/ i load-module module-alsa-source device=hw:0,2' /etc/pulse/default.pa
  if [ ! $? -eq 0 ]; then
    echo "!!Failed to patch /etc/pulse/default.pa, proceeding anyway."
  else
    pulseaudio -k
    pulseaudio -D
    if [ ! $? -eq 0 ]; then
      echo "!!Failed to restart pulseaudio, the original config is available at /etc/pulse/default.pa.orig"
      exit 1
    fi
    echo "PulseAudio config successfully updated"
  fi
fi

# 5. Restore speakers.state for speakers
echo "Restoring asla config"
sudo alsactl restore --file alsa/speakers.state
sudo alsactl store

# 6. Setup ACPI hooks for switching between speakers and headphones
if [[ -f /etc/acpi/handler.sh ]]; then
  egrep -q '^[  ]*jack/headphone\)$' /etc/acpi/handler.sh
  alreadyset=$?
  if [ ! $alreadyset -eq 0 ]; then
    echo "Setting up ACPI hooks"
    sudo cp /etc/acpi/handler.sh /etc/acpi/handler.sh.orig
    sudo mkdir -p /opt/samus
    sudo cp ./alsa/speakers.state /opt/samus
    sudo cp ./alsa/headphones.state /opt/samus
    line=$(sed -n '/^# Default acpi script that takes an entry for all actions/=' /etc/acpi/handler.sh);
    line=$(echo $line | cut -d " " -f 1)
    sudo sed -i "${line} a \}" /etc/acpi/handler.sh
    sudo sed -i "${line} a \    done" /etc/acpi/handler.sh
    sudo sed -i "${line} a \        su \"\${user}\" -c - \"PULSE_RUNTIME_PATH=\\\\\"\${pulsepath}\\\\\" pacmd set-sink-port \${sink} \${port}\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \        pulsepath=\"/run/user/\${uid}/pulse/\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \        uid=\`id -u \"\${user}\"\`" /etc/acpi/handler.sh
    sudo sed -i "${line} a \    do" /etc/acpi/handler.sh
    sudo sed -i "${line} a \    for user in \`ps axc -o user,command | grep pulseaudio | cut -f1 -d\' \' | sort | uniq\`" /etc/acpi/handler.sh
    sudo sed -i "${line} a \ " /etc/acpi/handler.sh
    sudo sed -i "${line} a \    fi" /etc/acpi/handler.sh
    sudo sed -i "${line} a \        port=\"analog-output-headphones\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \    if [ \"x\$1\" == \"xplug\" ] ; then" /etc/acpi/handler.sh
    sudo sed -i "${line} a \ " /etc/acpi/handler.sh
    sudo sed -i "${line} a \    port=\"analog-output-speaker\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \    sink=\"alsa_output.platform-bdw-rt5677.analog-stereo\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \function _SwitchPulsePort () {" /etc/acpi/handler.sh
    sudo sed -i "${line} a \ " /etc/acpi/handler.sh
    line=$(sed -n '/^case \"\$1\" in/=' /etc/acpi/handler.sh);
    line=$(echo $line | cut -d " " -f 1)
    sudo sed -i "${line} a \        ;;" /etc/acpi/handler.sh
    sudo sed -i "${line} a \        esac" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               ;;" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               logger \"ACPI action undefined: \$3\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \           *)" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               ;;" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               _SwitchPulsePort \"\$3\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               logger \"headphone unplugged\""  /etc/acpi/handler.sh
    sudo sed -i "${line} a \           unplug)" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               ;;" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               _SwitchPulsePort \"\$3\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \               logger \"headphone plugged\"" /etc/acpi/handler.sh
    sudo sed -i "${line} a \           plug)" /etc/acpi/handler.sh
    sudo sed -i "${line} a \        case \"\$3\" in" /etc/acpi/handler.sh
    sudo sed -i "${line} a \    jack/headphone)" /etc/acpi/handler.sh
  fi
else
  echo "/etc/acpi/handler.sh not found. Not setting up ACPI hooks. Headphones may not work correctly!"
  echo "Install the acpid daemon on re-run this script."
fi

# 7. Profit
echo "Sound setup completed successfully."
