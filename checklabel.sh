#!/bin/bash

PATH=`dirname $0`:$PATH

. rf-backup.lib.sh

CFGS=`match-label "$1"`

check-cfg-single "$1" "$CFGS" && echo OK

exit 0
