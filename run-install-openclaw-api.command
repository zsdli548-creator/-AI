#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/install-openclaw-api.sh"
if [ ! -f "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$SCRIPT_DIR/macOS-终端版-安装OpenClaw配置.sh"
fi

if [ ! -f "$SCRIPT_PATH" ]; then
    printf '\nCannot find the shell installer script.\n'
    printf 'Expected one of:\n'
    printf '  %s\n' "$SCRIPT_DIR/install-openclaw-api.sh"
    printf '  %s\n' "$SCRIPT_DIR/macOS-终端版-安装OpenClaw配置.sh"
    printf '\nPress Enter to close...'
    IFS= read -r _
    exit 1
fi

sh "$SCRIPT_PATH" "$@"
STATUS=$?

printf '\nPress Enter to close...'
IFS= read -r _

exit "$STATUS"
