#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
sh "$SCRIPT_DIR/install-openclaw-api.sh" "$@"
STATUS=$?

printf '\nPress Enter to close...'
IFS= read -r _

exit "$STATUS"
