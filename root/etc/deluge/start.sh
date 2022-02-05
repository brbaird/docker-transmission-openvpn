#!/bin/bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [deluge-start] $*"
}

# Source our persisted env variables from container startup
. /etc/deluge/environment-variables.sh

# This script will be called with tun/tap device name as parameter 1, and local IP as parameter 4
# See https://openvpn.net/index.php/open-source/documentation/manuals/65-openvpn-20x-manpage.html (--up cmd)
echo "Up script executed with $*"
if [[ "$4" = "" ]]; then
  echo "ERROR, unable to obtain tunnel address"
  echo "killing $PPID"
  kill -9 $PPID
  exit 1
fi

# If deluge-pre-start.sh exists, run it
if [[ -x /scripts/deluge-pre-start.sh ]]; then
  echo "Executing /scripts/deluge-pre-start.sh"
  /scripts/deluge-pre-start.sh "$@"
  echo "/scripts/deluge-pre-start.sh returned $?"
fi

echo "Updating DELUGE_BIND_ADDRESS_IPV4 to the ip of $1 : $4"
export DELUGE_BIND_ADDRESS_IPV4=$4
# Also update the persisted settings in case it is already set. First remove any old value, then add new.
sed -i '/DELUGE_BIND_ADDRESS_IPV4/d' /etc/deluge/environment-variables.sh
echo "export DELUGE_BIND_ADDRESS_IPV4=$4" >>/etc/deluge/environment-variables.sh

#echo "Updating Transmission settings.json with values from env variables"
# Ensure TRANSMISSION_HOME is created
#mkdir -p ${TRANSMISSION_HOME}
#python3 /etc/deluge/updateSettings.py /etc/deluge/default-settings.json ${TRANSMISSION_HOME}/settings.json || exit 1
#
#echo "sed'ing True to true"
#sed -i 's/True/true/g' ${TRANSMISSION_HOME}/settings.json

if [ -e /config/core.conf ]; then
  log "Updating Deluge conf file"
  #Interface
  sed -i -e "s/\"listen_interface\": \".*\"/\"listen_interface\": \"$DELUGE_BIND_ADDRESS_IPV4\"/" /config/core.conf
  #Deamon port
  sed -i -e "s/\"daemon_port\": \".*\"/\"daemon_port\": \"$DELUGE_DEAMON_PORT\"/" /config/core.conf
  #location
  sed -i -e "s/\"download_location\": \".*\"/\"download_location\": \"${DELUGE_INCOMPLETE_DIR//\//\\/}\"/" /config/core.conf
  sed -i -e "s/\"autoadd_location\": \".*\"/\"autoadd_location\": \"${DELUGE_WATCH_DIR//\//\\/}\"/" /config/core.conf
  sed -i -e "s/\"move_completed_path\": \".*\"/\"move_completed_path\": \"${DELUGE_DOWNLOAD_DIR//\//\\/}\"/" /config/core.conf
  sed -i -e "s/\"torrentfiles_location\": \".*\"/\"torrentfiles_location\": \"${DELUGE_TORRENT_DIR//\//\\/}\"/" /config/core.conf
fi

if [ -e /config/web.conf ]; then
  log "Updating Deluge web conf file"
  #Deamon port
  sed -i -e "s/\"default_daemon\": \".*\"/\"default_daemon\": \"127.0.0.1:$DELUGE_DEAMON_PORT\"/" /config/web.conf
  #Web port
  sed -i -e "s/\"port\": \".*\"/\"port\": \"$DELUGE_WEB_PORT\"/" /config/web.conf
fi

if [[ ! -e "/dev/random" ]]; then
  # Avoid "Fatal: no entropy gathering module detected" error
  echo "INFO: /dev/random not found - symlink to /dev/urandom"
  ln -s /dev/urandom /dev/random
fi

. /etc/deluge/userSetup.sh

if [[ "true" = "$DROP_DEFAULT_ROUTE" ]]; then
    echo "DROPPING DEFAULT ROUTE"
    # Remove the original default route to avoid leaks.
    /sbin/ip route del default via "${route_net_gateway}" || exit 1
fi

if [[ "true" = "$LOG_TO_STDOUT" ]]; then
  LOGFILE=/dev/stdout
else
  LOGFILE=/config/deluged.log
fi

log "STARTING DELUGE"
exec su --preserve-environment ${RUN_AS} -s /bin/bash -c "/usr/bin/deluged -d -c /config -L info -l $LOGFILE" &

# wait for deluge daemon process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
  sleep 0.1
done

log "STARTING DELUGE WEBUI"
exec su --preserve-environment ${RUN_AS} -s /bin/bash -c "/usr/bin/deluge-web -c /config -L info -l $LOGFILE" &

# Configure port forwarding if applicable
if [[ -x /etc/openvpn/${OPENVPN_PROVIDER,,}/update-port.sh && (-z $DISABLE_PORT_UPDATER || "false" = "$DISABLE_PORT_UPDATER") ]]; then
  echo "Provider ${OPENVPN_PROVIDER^^} has a script for automatic port forwarding. Will run it now."
  echo "If you want to disable this, set environment variable DISABLE_PORT_UPDATER=true"
  exec /etc/openvpn/${OPENVPN_PROVIDER,,}/update-port.sh &
fi

# If deluge-post-start.sh exists, run it
if [[ -x /scripts/deluge-post-start.sh ]]; then
  echo "Executing /scripts/deluge-post-start.sh"
  /scripts/deluge-post-start.sh "$@"
  echo "/scripts/deluge-post-start.sh returned $?"
fi

echo "Deluge startup script complete."
