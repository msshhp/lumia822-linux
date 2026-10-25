#!/bin/bash
# usage: pc.sh "<command>" [waitms]  -> runs on phone, prints cleaned output after the echoed command
H=$(cd "$(dirname "$0")" && pwd)   # needs LUMIA_WP_IP set (see pcmd.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $H/pcmd.ps1)" -Cmd "$1" -Wait ${2:-4000} | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' | tr -d '\r' | awk 'BEGIN{p=0} /^Copyright/{p=1;next} p' | grep -v '^C:\windows\system32>[^ ]*$' | sed -n '3,$p'
