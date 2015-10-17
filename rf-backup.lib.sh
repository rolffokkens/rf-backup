CFGDIR=/etc/rf-backup.d/
MNTDIR=/mnt/rf-backup
RUNDIR=/var/run/rf-backup
LIBDIR=/var/lib/rf-backup
LOGFILE=/var/log/rf-backup.log
LOGOUTPUT=""
NOTIOUTPUT=""

read-locale ()
{
    local LNG
    local LOCDIR="${RFBCKDIR}/locale"

    LNG="${LANG}."
    LNG="${LNG%%.*}"

    [ -e "${LOCDIR}/${LNG}.messages" ] || LNG="${LNG%%_*}"
    [ -e "${LOCDIR}/${LNG}.messages" ] || LNG=en

    unset rf_locale

    declare -gA rf_locale

    eval $(sed -n 's/"/\\\"/g;s/\(^[^#][^#= ]\+\)\([=]\)\([^ ].*$\)/rf_locale["\1"]="\3"/p' "${LOCDIR}/${LNG}.messages")
}

init-rf-backup ()
{
    declare -g RFBCKDIR=`dirname "$0"`

    declare -g LANG
    [ -z "$LANG" ] && [ -e /etc/locale.conf ] && . /etc/locale.conf

    read-locale
}

get-locale-msg ()
{
    local MSGTXT="${rf_locale[$1]}"

    shift

    printf "$MSGTXT" "$@"
}

get-cfgs ()
{
    local i
    local SEP=""

    for i in ${CFGDIR}/*.conf
    do
        [ -e "$i" ] || continue
        echo -n "$SEP${i%[.]conf}"
        SEP=" "
    done | sed 's|/\+|/|g'
}

read-cfg ()
{
    declare -g cfg_NAME="" cfg_BACKUPLABELS="" cfg_DSTDIR="" cfg_SRCDIR="" cfg_NEXTAFTER=""

    [ -e "$1.conf" ] || return 1

    eval $(sed -n 's/"/\\\"/g;s/\(^[^#][^#= ]\+\)\([=]\)\([^ ].*$\)/cfg_\1="\3"/p' "$1.conf")

    return 0
}

expand-cfgs ()
{
    local SEP

    if [ $# == 1 ]
    then
        SEP=" "
    else
        SEP="$2"
    fi

    echo $1 | sed "s| |.conf${SEP}|g;s|$|.conf|"
}

split-labels ()
{
    local LBL
    local LBLS

    LBLS="${1},"

    while [ "${LBLS}" != "" ]
    do

        LBL=${LBLS%%,*}
        LBLS=${LBLS#*,}

        echo "$LBL"
    done 

    return 0
}

match-label ()
{
    local i
    local CFG
    local SEP=""

    for CFG in `get-cfgs`
    do
        read-cfg "${CFG}"

        for i in `split-labels "${cfg_BACKUPLABELS}"`
        do
            [ "$i" == "$1" ] || continue
            echo -n "${SEP}${CFG}"
            SEP=" "
        done
    done | sort -u
}

check-cfg-single ()
{
    case "$2" in
    *\ *)
        write-log "ERROR: mutiple configs apply for $1: `expand-cfgs "$2" ", "`"
        return 1
        ;;
    "")
        return 1
        ;;
    *)
        write-log "INFO: config $2.conf applies for $1"
        return 0
    esac
}

set-logoutput ()
{
    LOGOUTPUT="$1"
    NOTIOUTPUT="$2"
}

cond-logoutput ()
{
    if [ "${LOGOUTPUT}" == "" ]
    then
        cat
    else
        tee -a "${LOGOUTPUT}"
    fi
}

write-log ()
{
    echo "$1" | cond-logoutput | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; }' >> "${LOGFILE}"
}

notify-users ()
{
    local TITLE="$1"
    local MSG="$2"
    local BCFG="$3"
    local URG="$4"
    local USER

    [ "$URG" == "" ] && URG=normal

    write-log "USER (${BCFG}): ${TITLE}: ${MSG}"

    for pid in `pgrep dbus-daemon`
    do
        USER="`stat -c"%U" "/proc/${pid}"`"
        unset prc_DISPLAY prc_DBUS_SESSION_BUS_ADDRESS
        eval $(grep -z -e DISPLAY= -e DBUS_SESSION_BUS_ADDRESS= /proc/$pid/environ | sed 's/\o00/\n/' | sed 's|^|prc_|')
        [ "$prc_DISPLAY"                  == "" ] && continue
        [ "$prc_DBUS_SESSION_BUS_ADDRESS" == "" ] && continue
        echo "${USER}|${prc_DBUS_SESSION_BUS_ADDRESS}"
    done \
    | sort -u \
    | while IFS="|" read USER prc_DBUS_SESSION_BUS_ADDRESS
      do
          su - "$USER" -c "DBUS_SESSION_BUS_ADDRESS=$prc_DBUS_SESSION_BUS_ADDRESS /bin/notify-send -i \"${BCKIMG}\" \"${TITLE}\" \"${MSG}\" -u ${URG}"
      done

    wall "${TITLE}: ${MSG}" > /dev/null 2>&1

    [ "$NOTIOUTPUT" == "" ] || echo "${TITLE}: ${MSG}" > "$NOTIOUTPUT"
}

action-and-log ()
{
    local BCFG="$1"
    local RETVAL
    local TMP=`mktemp /tmp/do-backup-XXXXXX`

    shift

    eval "$@" > "${TMP}" 2>&1

    RETVAL=$?

    if [ "${RETVAL}" != "0" ]
    then
        write-log "CMD (${BCFG}): `echo "$@"`"
        cat "${TMP}" \
        | while read LINE
          do
              write-log "LOG (${BCFG}): ${LINE}"
          done
    fi

    rm "${TMP}"

    return ${RETVAL}
}

get-df ()
{
    df -k | awk -v "MNT=$1" '{ if ($0 "//" ~ " " MNT "[/]*$") print $1, $3, $4}'
}

get-backup-size ()
{
    local DIR="$1"
    local LABEL="$2"
    local STATS="${LIBDIR}/${LABEL}.stats"

    if [ ! -s "$STATS" ]
    then
        echo 0
        return 0
    fi

    awk "-F|" -v "DIR=$DIR" -v "SIZE=$SIZE" '
    BEGIN {
        size = 0;
        l    = 0;
    }
    {
        if ($1 != DIR) next;
        size += $2;
        l++;
    }
    END {
        print int (size/l);
    }' "$STATS"
}

add-backup-size ()
{
    local DIR="$1"
    local LABEL="$2"
    local SIZE="$3"
    local FREE="$4"
    local STATS="${LIBDIR}/${LABEL}.stats"
    local TMP1=`mktemp "${LIBDIR}/${LABEL}-XXXXXX.stats"`
    local DT=`date +%s`

    [ "$SIZE" -lt "0" ] && return 0

    [ -e "$STATS" ] || touch "$STATS"

    awk "-F|" -v "DIR=$DIR" -v "SIZE=$SIZE" -v "DT=$DT" -v "FREE=$FREE" '
    BEGIN {
        l     = 0;
    }
    {
        if (NF < 3) next;
        if ($1 != DIR) {
            print $0;
            next;
        }
        lines[l++] = $0;
    }
    END {
        lines[l++]=DIR "|" SIZE "|" DT "|" FREE;
        i = l-5;
        if (i < 0) i = 0;
        while (i < l) print lines[i++];
    }' "$STATS" > "$TMP1"

    mv -f "$TMP1" "$STATS"
}
