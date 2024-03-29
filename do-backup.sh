#!/usr/bin/bash

. `dirname $0`/rf-backup.lib.sh

BCKIMG=/usr/share/icons/gnome/32x32/devices/drive-harddisk-usb.png

cond-mount ()
{
    local RLBL="$1"
    local RMNT="$2"
    local BCFG=`basename "$3"`
    local RDEV=`readlink -f /dev/disk/by-label/$RLBL`

    local DEV MPT REST

    write-log "INFO (${BCFG}): Mounting $RDEV on $RMNT"

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

    # mount "$RDEV" "$RMNT" -o acl,user_xattr 2>/dev/null

    if action-and-log "${BCFG}" \
           mount "\"${RDEV}\"" "\"${RMNT}\"" -o user_xattr
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
    local LABEL="$6"
    local BCFG=`basename "$4"`

    write-log "INFO (${BCFG}): Making backup $NEXTID"

    LASTID=`get_last_id "$DSTPATH" $NEXTID`
    case "$LASTID" in
        ERROR:*)
            write-log "ERROR (${BCFG}): Bad last backup ${LASTID#*:}"
            return 1;
        ;;
    esac

    notify-users "RF backup" 03 "${BCFG}" "" "${NAME}" "${LABEL}"

    if [ "$LASTID" = "" ]
    then
        mkdir -p "$DSTPATH/${NEXTID}"
    else
        write-log "INFO (${BCFG}): Making copy of previous backup $LASTID"
       if ! action-and-log "${BCFG}" \
                cp -apl "\"$DSTPATH/${LASTID}\"" "\"$DSTPATH/${NEXTID}\""
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
    action-and-log "${BCFG}" \
        rsync -axAHRS --exclude-from="\"${TMPEXCL}\"" \
              --delete --ignore-errors --delete-excluded --force \
              "\"$SRCPATH\"" "\"$DSTPATH/${NEXTID}\""

    RET=$?
    [ "$RET" == "24" ] && RET=0

    rm "${TMPEXCL}"

    if [ "$RET" != "0" ]
    then
        write-log "ERROR (${BCFG}): rsync failed"
        return 1
    fi

    write-log "INFO (${BCFG}): Contents updated"

    return 0
}

do-work ()
{
    local PLABEL="$1"
    local PCFG="$2"
    local CFGS="$3"

    local MNTBCKDIR
    local NEXTID
    local BCFG
    local DF1
    local DU1
    local DF2
    local DU2
    local AVGSIZ

    [ -z "${cfg_NAME}" ] && cfg_NAME="${PCFG}"

    MNTBCKDIR="${MNTDIR}/`basename "${CFGS}"`"

    mkdir -p "${MNTBCKDIR}"

    if ! cond-mount "${PLABEL}" "${MNTBCKDIR}" "${CFGS}"
    then
        notify-users "RF backup" 04 "${PCFG}" "" "${cfg_NAME}"
        return 1
    fi

    AVGSIZ=`get-backup-size "${cfg_SRCDIR}" "${PLABEL}"`

    write-log "DEBUG (AVGSIZ): $AVGSIZ"

    DF1=`get-df "${MNTBCKDIR}"`
    DF1="${DF1#* }"
    DU1="${DF1%% *}"
    DF1="${DF1#* }"

    write-log "DEBUG (DF/DU): [$DF1][$DU1]"

    if [ "$(($AVGSIZ * 2))" -gt "$DF1" ]
    then
        notify-users "RF backup" 08 "${PCFG}" "critical" "${cfg_NAME}"
        return 1
    fi

    NEXTID=`echo 1 | awk '{ print strftime ("%Y%m%d.%H%M%S")}'`

    if ! make_backup "$NEXTID" "${cfg_SRCDIR}" "${MNTBCKDIR}/${cfg_DSTDIR}" "${CFGS}" "${cfg_NAME}" "${PLABEL}"
    then
        notify-users "RF backup" 05 "${PCFG}" "critical" "${cfg_NAME}"
        return 1
    fi

    DF2=`get-df "${MNTBCKDIR}"`
    DF2="${DF2#* }"
    DU2="${DF2%% *}"
    DF2="${DF2#* }"
    write-log "DEBUG (DF/DU): [$DF2][$DU2][$(($DU2-$DU1))]"
    add-backup-size "${cfg_SRCDIR}" "${PLABEL}" "$(($DU2-$DU1))" "$DF2"

    write-log "INFO (${PCFG}): Unmounting ${MNTBCKDIR}"

    if action-and-log "${BCFG}" \
        umount "\"${MNTBCKDIR}\""
    then
        notify-users "RF backup" 06 "${PCFG}" "critical" "${cfg_NAME}" "${PLABEL}"
    else
        write-log "ERROR (${PCFG}): Error unmounting ${MNTBCKDIR}"
        notify-users "RF backup" 07 "${PCFG}" "critical" "${cfg_NAME}"
    fi

    return 0
}

main ()
{
    local PLABEL="$1:"
    local PCFG="${PLABEL#*:}"
    local CFGS
    local TLOG=`mktemp /tmp/rf-backup-XXXXXX`
    local TNOTI=`mktemp /tmp/rf-backup-XXXXXX`

    PLABEL="${PLABEL%%:*}"
    PCFG="${PCFG%%:*}"

    [ "${PLABEL}" == "" ] && return 0
    [ "${PCFG}"   == "" ] && return 0

    CFGS="${CFGDIR}/${PCFG}"

    init-rf-backup

    read-cfg "${CFGS}" || return 0

    set-logoutput "${TLOG}" "${TNOTI}"

    do-work "${PLABEL}" "${PCFG}" "${CFGS}"

    if [ "${cfg_MAIL}" != "" ]
    then
        sendwait=1 HOME=/root MAILRC=/dev/null /usr/bin/mailx -s "`cat "${TNOTI}"`" rolf@rolffokkens.nl < "${TLOG}"
    fi

    rm -f "${TLOG}" "${TNOTI}"
}


main "$1"
