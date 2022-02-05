#!/bin/bash

RUN_AS=root

if [ -n "$PUID" ] && [ ! "$(id -u root)" -eq "$PUID" ]; then
    RUN_AS=abc
    if [ ! "$(id -u ${RUN_AS})" -eq "$PUID" ]; then
        usermod -o -u "$PUID" ${RUN_AS}
    fi
    if [ -n "$PGID" ] && [ ! "$(id -g ${RUN_AS})" -eq "$PGID" ]; then
        groupmod -o -g "$PGID" ${RUN_AS}
    fi

    if [[ "true" = "$LOG_TO_STDOUT" ]]; then
        chown ${RUN_AS}:${RUN_AS} /dev/stdout
    fi

    # Make sure directories exist before chown and chmod
    mkdir -p /config \
        "${DELUGE_DOWNLOAD_DIR}" \
        "${DELUGE_INCOMPLETE_DIR}" \
        "${DELUGE_WATCH_DIR}" \
        "${DELUGE_TORRENT_DIR}"

    echo "Enforcing ownership on deluge config directories"
    chown -R ${RUN_AS}:${RUN_AS} \
        /config

    echo "Applying permissions to deluge config directories"
    chmod -R go=rX,u=rwX \
        /config

    if [ "$GLOBAL_APPLY_PERMISSIONS" = true ]; then
        echo "Setting owner for deluge paths to ${PUID}:${PGID}"
        chown -R ${RUN_AS}:${RUN_AS} \
            "${DELUGE_DOWNLOAD_DIR}" \
            "${DELUGE_INCOMPLETE_DIR}" \
            "${DELUGE_WATCH_DIR}" \
            "${DELUGE_TORRENT_DIR}"

        echo "Setting permissions for download and incomplete directories"
        DIR_PERMS=$(printf '%o\n' $((0777 & ~UMASK)))
        FILE_PERMS=$(printf '%o\n' $((0666 & ~UMASK)))
        echo "Mask: ${UMASK}"
        echo "Directories: ${DIR_PERMS}"
        echo "Files: ${FILE_PERMS}"

        find "${DELUGE_DOWNLOAD_DIR}" "${DELUGE_INCOMPLETE_DIR}" -type d \
            -exec chmod $(printf '%o\n' $((0777 & ~UMASK))) {} +
        find "${DELUGE_DOWNLOAD_DIR}" "${DELUGE_INCOMPLETE_DIR}" -type f \
            -exec chmod $(printf '%o\n' $((0666 & ~UMASK))) {} +

        echo "Setting permission for watch and torrent directories (775) and its files (664)"
        chmod -R o=rX,ug=rwX \
            "${DELUGE_WATCH_DIR}" "${DELUGE_TORRENT_DIR}"
    fi
fi

echo "
-------------------------------------
Deluge will run as
-------------------------------------
User name:   ${RUN_AS}
User uid:    $(id -u ${RUN_AS})
User gid:    $(id -g ${RUN_AS})
-------------------------------------
"

export PUID
export PGID
export RUN_AS
