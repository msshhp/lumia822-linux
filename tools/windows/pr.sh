#!/bin/bash
# pr.sh "<command>" [waitms]: run on phone with output redirected to a file, then print only that file
H=$(cd "$(dirname "$0")" && pwd)   # needs LUMIA_WP_IP set (see pcmd.ps1)
P="powershell -NoProfile -ExecutionPolicy Bypass -File $(cygpath -w $H/pcmd.ps1)"
$P -Cmd "($1) > C:\Data\o.txt 2>&1" -Wait ${2:-4000} > /dev/null
$P -Cmd "type C:\Data\o.txt & echo @@END@@" -Wait 3000 | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' | tr -d '\r' | awk '/@@END@@$/{exit} f{print} /echo @@END@@/{f=1}' | sed 's/.*echo @@END@@//' 
