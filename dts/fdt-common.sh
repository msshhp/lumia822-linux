# Shared helpers for the DTB build scripts (sourced). The DTB is built by editing an existing binary
# DTB step by step with tools/dotnet/fdttool (build it once: cd tools/dotnet/fdttool && dotnet build -c Release).
# Works in Git Bash on Windows and on Linux. Override the tool with FDTTOOL="<command>".
export MSYS_NO_PATHCONV=1
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
W() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
F=${FDTTOOL:-"dotnet $(W "$REPO/tools/dotnet/fdttool/bin/Release/net8.0/fdttool.dll")"}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
i=0
start_from() { cur="$(W "$1")"; }
step() { i=$((i+1)); nxt="$(W "$T/s$i.dtb")"; $F "$1" "$cur" "$nxt" "${@:2}" || { echo "FAILED at $*"; exit 1; }; cur="$nxt"; }
node() { step addnode "$1" "$2"; }
prop() { step set "$@"; }
finish() { cp "$T/s$i.dtb" "$1"; ls -l "$1"; }
