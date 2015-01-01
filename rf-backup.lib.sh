CFGDIR=/etc/rf-backup.d/
MNTDIR=/mnt/backup
EXCLUDEFILE=/tmp/rsync-backup-exclude-$$.lis
LOGFILE=/var/log/rf-backup.log

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
    eval $(sed -n 's/\(^[^#].*$\)/cfg_\1/p' "$1.conf")
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

write-log ()
{
    echo "$1" | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; }' >> ${LOGFILE}
}
