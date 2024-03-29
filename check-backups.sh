#!/usr/bin/bash

. `dirname $0`/rf-backup.lib.sh

get-most-recent ()
{
    local LABEL
    local i

    for i in /var/lib/rf-backup/*.stats
    do
        LABEL=`basename "$i" | sed 's/[.]stats$//'`

        awk "-F|" -v "LABEL=$LABEL" '{
            if (NF < 3) next;

            if ($1 in dirs) {
               if (dirs[$1] < $3) dirs[$1] = $3;
            } else {
               dirs[$1] = $3;
            }
        }
        END {
            for (i in dirs) print LABEL "|" i "|" dirs[i];
        }' "$i"
    done
}

main ()
{
    local TMP1=`mktemp /tmp/rf-backup-XXXXXX`
    local i
    local DT=`date +%s`

    init-rf-backup

    get-most-recent > "$TMP1"

    for i in `get-cfgs`
    do
        unset cfg_SRCDIR cfg_NAME cfg_WARNAFTER cfg_MAIL

        read-cfg "$i"

        [ "$cfg_WARNAFTER" == "" ] && continue

        echo "`basename "$i"`|$cfg_SRCDIR|$cfg_WARNAFTER|$cfg_NAME|$cfg_MAIL"
    done \
    | awk "-F|" -v "DT=$DT" '{
          if (ARGIND == 1) {
              if ($2 in dirs && $3 < dirs[$2]) next;

              dirs[$2]   = $3;
              labels[$2] = $1;
          } else {
              if (!($2 in dirs)) {
                  print $1 "|" $4 "|11||" $5 "|";
                  next;
              }
              days = int ((DT - dirs[$2]) / (24 * 60 * 60))

              if (days < $3) next;

              print $1 "|" $4 "|10|" days "|" $5 "|" labels[$2];
          }
      }' "$TMP1" - \
    | while IFS="|" read CFG NAME MSG DAYS MAIL LABEL
      do
          BCK="$NAME"
          [ "$BCK" == "" ] && BCK="($CFG)"
          #echo $CFG $NAME $MSG $DAYS $MAIL
          if [[ $MAIL != "" ]]
          then
              SUBJECT=`get-locale-msg 09 "$BCK"`
              BODY=`get-locale-msg "$MSG" "$DAYS" "$LABEL"`
              echo "$BODY" \
              | sendwait=1 HOME=/root MAILRC=/dev/null /usr/bin/mailx -s "${SUBJECT}" "$MAIL"
          fi
          notify-users "RF backup" "$MSG" "${CFG}" "critical" "$DAYS" "$LABEL"
      done

    rm -f "$TMP1"
}

main 
