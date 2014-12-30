#!/bin/bash

TLABEL="$1"

[ -z "$TLABEL"           ] && exit 0
[ -e /etc/rf-backup.conf ] || exit 0

eval $(sed -n 's/\(^[^#].*$\)/cfg_\1/p' /etc/rf-backup.conf)

IFS=,
for i in $cfg_BACKUPLABELS
do
    if [ "$i" == "$TLABEL" ]
    then
        echo OK
        exit 0
    fi
done

exit 0
