#!/bin/bash

PLABEL="$1"

. `dirname $0`/rf-backup.lib.sh

[ -e "${RUNDIR}/${PLABEL}.nxt" ] && NEXTAFTER=$((`cat "${RUNDIR}/${PLABEL}.nxt"`+0))
[ $((${NEXTAFTER}+0)) -lt `date +%s` ] || exit 0

CFGS=`match-label "${PLABEL}"`

check-cfg-single "${PLABEL}" "$CFGS" || exit 0

read-cfg "$CFGS"

[ $((${cfg_NEXTAFTER}+0)) -gt 0 ] || cfg_NEXTAFTER=0

echo `basename "$CFGS"` "$cfg_NEXTAFTER"

exit 0
