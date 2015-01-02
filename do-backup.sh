#!/bin/bash

. `dirname $0`/rf-backup.lib.sh

BCKLABEL="$1"
BCKIMG=/usr/share/icons/gnome/32x32/devices/drive-harddisk-usb.png

cond-mount ()
{
    local RLBL="$1"
    local RMNT="$2"
    local BCFG=`basename "$3"`
    local RDEV=`readlink -f /dev/disk/by-label/$RLBL`

    local DEV MPT REST

    while read DEV MPT REST
    do
        [ "$DEV" != "$RDEV" ] && [ "$MPT" != "$RMNT" ] && continue
        if [ "$DEV" = "$RDEV" ] && [ "$MPT" = "$RMNT" ]
        then
            write-log "INFO (${BCFG}): $RDEV already mounted on $RMNT"
            return 0
        fi
        if [ "$DEV" = "$RDEV" ]
        then
            write-log "ERROR (${BCFG}): $RDEV already mounted on $MPT"
        else
            write-log "ERROR (${BCFG}): $DEV already mounted on $RMNT"
        fi
        return 1
    done < /proc/mounts

    write-log "INFO (${BCFG}): Mounting $RDEV on $RMNT"

    # mount "$RDEV" "$RMNT" -o acl,user_xattr 2>/dev/null
    mount "$RDEV" "$RMNT" -o user_xattr 2>/dev/null

    if [ "$?" = "0" ]
    then
        return 0
    fi

    write-log "ERROR (${BCFG}): Unable to mount device $RDEV with label $RLBL on $RMNT"
    return 1
}

get_last_id ()
{
    for i in "$1/"[0-9][0-9][0-9][0-9]*
    do
        echo $i
    done \
    | sed 's|\(^.*/\)\([^/]*$\)|\2|' \
    | awk "-F." "-vNXT=$2" '
           BEGIN {
               split (NXT, a, "[.]");
           }
           /^[0-9.]*$/ {
               if (NF>2 || l ~ "^ERROR:.*$") next;
               if ($1>a[1] || ($1==a[1] && $2>=a[2])) {
                   l="ERROR:" $0;
                   next;
               }
               if ($1>l1) {
                   l1=$1 + 0;
                   l2=$2 + 0;
                   l=$0
               } else if ($1==l1 && $2 > l2) {
                   l2=$2 + 0;
                   l=$0
               }
           }
           END {
               print l;
           }'
}

make_backup ()
{
    local NEXTID="$1"
    local SRCPATH="$2"
    local DSTPATH="$3"
    local CFG="$4"
    local NAME="$5"
    local BCFG=`basename "$4"`

    write-log "INFO (${BCFG}): Making backup $NEXTID"

    LASTID=`get_last_id "$DSTPATH" $NEXTID`
    case "$LASTID" in
        ERROR:*)
            write-log "ERROR (${BCFG}): Bad last backup ${LASTID#*:}"
            return 1;
        ;;
    esac

    notify-users "RF backup" "`get-locale-msg 03 "${NAME}" "${BCKLABEL}"`" "${BCFG}"

    if [ "$LASTID" = "" ]
    then
        mkdir -p "$DSTPATH/${NEXTID}"
    else
        write-log "INFO (${BCFG}): Making copy of previous backup $LASTID"
       if ! cp -apl "$DSTPATH/${LASTID}" "$DSTPATH/${NEXTID}"
       then
           write-log "ERROR (${BCFG}): cp failed"
           return 1
       fi
    fi

    TMPEXCL=`mktemp /tmp/rf-backup-XXXXXX`

    if [ -e "${CFG}.exclude" ]
    then
        write-log "INFO (${BCFG}): Using excludes in ${CFG}.exclude"
        cat < "${CFG}.exclude" > "${TMPEXCL}"
    fi

    write-log "INFO (${BCFG}): Updating contents"
    # removed --xattrs 
    rsync -axAHRS --exclude-from="${TMPEXCL}" \
          --delete --ignore-errors --delete-excluded --force \
          "$SRCPATH" "$DSTPATH/${NEXTID}"

    RET=$?

    rm "${TMPEXCL}"

    if [ "$RET" != "0" ]
    then
        write-log "ERROR (${BCFG}): rsync failed"
        return 1
    fi

    write-log "INFO (${BCFG}): Contents updated"

    return 0
}

main ()
{
    local PLABEL="$1"
    local MNTBCKDIR
    local NEXTID
    local CFGS=`match-label "$BCKLABEL"`
    local BCFG

    init-rf-backup

    check-cfg-single "${PLABEL}" "${CFGS}" || exit 0

    BCFG=`basename "${CFGS}"`

    read-cfg "${CFGS}"

    [ -z "${cfg_NAME}" ] && cfg_NAME="${BCFG}"

    MNTBCKDIR="${MNTDIR}/`basename "${CFGS}"`"

    mkdir -p "${MNTBCKDIR}"

    if ! cond-mount "${BCKLABEL}" "${MNTBCKDIR}" "${CFGS}"
    then
        notify-users "RF backup" "`get-locale-msg 04 "${cfg_NAME}"`" "${BCFG}" critical
        exit 0
    fi

    NEXTID=`echo 1 | awk '{ print strftime ("%Y%m%d.%H%M%S")}'`

    if ! make_backup "$NEXTID" "${cfg_SRCDIR}" "${MNTBCKDIR}/${cfg_DSTDIR}" "${CFGS}" "${cfg_NAME}"
    then
        notify-users "RF backup" "`get-locale-msg 05 "${cfg_NAME}"`" "${BCFG}" critical
        exit 0
    fi

    if umount "${MNTBCKDIR}"
    then
        notify-users "RF backup" "`get-locale-msg 06 "${cfg_NAME}" "${BCKLABEL}"`" "${BCFG}" critical
    else
        write-log "ERROR (${BCFG}): Error unmounting ${MNTBCKDIR}"
        notify-users "RF backup" "`get-locale-msg 07 "${cfg_NAME}"`" "${BCFG}" critical
    fi

    exit 0
}

main "$1"
