#!/bin/bash
# Run a command on (or open a shell to) the phone's Linux.
#   tools/lumia-ssh.sh [command...]
# Host: lumia822.local (mDNS, works over Wi-Fi or USB). LUMIA_HOST=192.168.42.1 forces the USB link.
# Key:  LUMIA_KEY (default ~/.ssh/id_ed25519) - its .pub must be in C:\EFIESP\linux\authorized_keys.
H=${LUMIA_HOST:-lumia822.local}
K=${LUMIA_KEY:-$HOME/.ssh/id_ed25519}
exec ssh -i "$K" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 root@"$H" "$@"
