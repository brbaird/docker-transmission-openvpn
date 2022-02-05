#!/bin/bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [deluge-stop] $*"
}

# If deluge-pre-stop.sh exists, run it
if [[ -x /config/deluge-pre-stop.sh ]]
then
   log "Executing /config/deluge-pre-stop.sh"
   /config/deluge-pre-stop.sh "$@"
   log "/config/deluge-pre-stop.sh returned $?"
fi

log "Sending kill signal to deluge-web"
PID=$(pgrep deluge-web)
kill "$PID"

log "Sending kill signal to deluge-daemon"
PID=$(pgrep deluged)
kill "$PID"

# Give deluged some time to shut down
DELUGE_TIMEOUT_SEC=${DELUGE_TIMEOUT_SEC:-5}
for i in $(seq "$DELUGE_TIMEOUT_SEC")
do
    sleep 1
    [[ -z "$(pgrep deluged)" ]] && break
    [[ $i == 1 ]] && echo "Waiting ${DELUGE_TIMEOUT_SEC}s for deluged to die"
done

# Check whether deluged is still running
if [[ -z "$(pgrep deluged)" ]]
then
    echo "Successfuly closed deluged"
else
    echo "Sending kill signal (SIGKILL) to deluged"
    kill -9 "$PID"
fi

# If deluge-post-stop.sh exists, run it
if [[ -x /config/deluge-post-stop.sh ]]
then
   log "Executing /config/deluge-post-stop.sh"
   /config/deluge-post-stop.sh "$@"
   log "/config/deluge-post-stop.sh returned $?"
fi

#exec /etc/ufw/disable.sh
ufw disable