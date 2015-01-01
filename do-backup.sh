#!/bin/bash

PATH=`dirname $0`:$PATH

. rf-backup.lib.sh

BCKIMG=/usr/share/icons/gnome/32x32/devices/drive-harddisk-usb.png
BCKLABEL="$1"

notify-users ()
{
    local TITLE=$1
    local MSG=$2
    local URG=$3

    [ "$URG" == "" ] && URG=normal

    logger -t "rf-backup" "${TITLE}: ${MSG}"

    who \
    | awk '{ if ($2 ~ "^[:]") print $1, $2; }' \
    | while read USER DISP
      do
          su - "$USER" -c "DISPLAY=$DISP /bin/notify-send -i \"${BCKIMG}\" \"${TITLE}\" \"${MSG}\" -u ${URG}"
      done

    /bin/wall "$MSG" > /dev/null 2>&1
}

find-backupdisk ()
{
    RETVAL=""

    LBLS="${cfg_BACKUPLABELS},"

    while [ "${LBLS}" != "" ]
    do

        LBL=${LBLS%%,*}
        LBLS=${LBLS#*,}

        [ -e "/dev/disk/by-label/$LBL" ] || continue
        if [ "$RETVAL" != "" ]
        then
            notify-users "RF backup" "Meer dan 1 backup disk gevonden, kan niet door gaan." critical
            return 1
        fi
        RETVAL="$LBL"
    done
    if [ "$RETVAL" == "" ]
    then
        notify-users "RF backup" "Geen backup disk gevonden, kan niet door gaan." critical
        return 1
    fi
    echo "$RETVAL"
    return 0
}

cond-mount ()
{
    local RLBL="$1"
    local RMNT="$2"
    local RDEV=`readlink -f /dev/disk/by-label/$RLBL`

    local DEV MPT REST

    while read DEV MPT REST
    do
        [ "$DEV" != "$RDEV" ] && [ "$MPT" != "$RMNT" ] && continue
        if [ "$DEV" = "$RDEV" ] && [ "$MPT" = "$RMNT" ]
        then
            write-log "INFO: $RDEV already mounted on $RMNT"
            return 0
        fi
        if [ "$DEV" = "$RDEV" ]
        then
            write-log "ERROR: $RDEV already mounted on $MPT"
        else
            write-log "ERROR: $DEV already mounted on $RMNT"
        fi
        return 1
    done < /proc/mounts

    write-log "INFO: Mounting $RDEV on $RMNT"

    # mount "$RDEV" "$RMNT" -o acl,user_xattr 2>/dev/null
    mount "$RDEV" "$RMNT" -o user_xattr 2>/dev/null

    if [ "$?" = "0" ]
    then
        return 0
    fi

    write-log "ERROR: Unable to mount device $RDEV with label $RLBL on $RMNT" >&2
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

    write-log "INFO: Making backup $NEXTID"

    LASTID=`get_last_id "$DSTPATH" $NEXTID`
    case "$LASTID" in
        ERROR:*)
            write-log "ERROR: Bad last backup ${LASTID#*:}"
            return 1;
        ;;
    esac

    notify-users "RF backup" "De backup is begonnen op disk ${BCKLABEL}..."

    if [ "$LASTID" = "" ]
    then
        mkdir -p "$DSTPATH/${NEXTID}"
    else
        write-log "INFO: Making copy of previous backup $LASTID"
        cp -apl "$DSTPATH/${LASTID}" "$DSTPATH/${NEXTID}"
    fi
    write-log "INFO: Updating contents" >&2

#    create_exclude_file > "$EXCLUDEFILE"
    > "$EXCLUDEFILE"
    # removed --xattrs 
    rsync -axAHRS --exclude-from="$EXCLUDEFILE" \
          --delete --ignore-errors --delete-excluded --force \
          "$SRCPATH" "$DSTPATH/${NEXTID}"
    rm ""$EXCLUDEFILE""

    return 0
}

CFGS=`match-label "$BCKLABEL"`

check-cfg-single "$1" "$CFGS" || exit 0

read-cfg "$CFGS"

MNTBCKDIR="${MNTDIR}/`basename "$CFGS"`"

mkdir -p "${MNTBCKDIR}"

if ! cond-mount "${BCKLABEL}" "${MNTBCKDIR}"
then
    notify-users "RF backup" "Er is een fout opgetreden bij het starten van de backup" critical
    exit 0
fi

NEXTID=`echo 1 | awk '{ print strftime ("%Y%m%d.%H%M%S")}'`

if ! make_backup "$NEXTID" "${cfg_SRCDIR}" "${MNTBCKDIR}/${cfg_DSTDIR}"
then
    notify-users "RF backup" "Er is een fout opgetreden bij het maken van de backup" critical
    exit 0
fi

if umount "${MNTBCKDIR}"
then
    notify-users "RF backup" "De backup is afgerond op disk ${BCKLABEL}..." critical
else
    write-log "ERROR: Error unmounting ${MNTBCKDIR}"
    notify-users "RF backup" "Er is een fout opgetreden bij het afsluiten van de backup" critical
fi

exit 0
