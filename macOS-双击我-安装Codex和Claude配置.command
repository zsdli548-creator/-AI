#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
sh "$SCRIPT_DIR/macOS-Linux-终端版-安装Codex和Claude配置.sh" "$@"
STATUS=$?

printf '\nPress Enter to close...'
IFS= read -r _

exit "$STATUS"
