#!/bin/bash

PLABEL="$1"
PNEXTAFTER="$2"

[ -z "${PLABEL}"             ] && exit 0
[ $((${PNEXTAFTER}+0)) -gt 0 ] || exit 0

. `dirname $0`/rf-backup.lib.sh

echo $((`date +%s` + ${PNEXTAFTER})) > "${RUNDIR}/${PLABEL}.nxt"

exit 0
