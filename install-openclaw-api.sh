#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/openclaw-api-setup.env"

if [ ! -f "$CONFIG_FILE" ]; then
    printf 'Setup config not found: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

set -a
. "$CONFIG_FILE"
set +a

OPENCLAW_BASE_URL="${OPENCLAW_BASE_URL:-https://aizhiwen.top}"
OPENCLAW_MODEL="${OPENCLAW_MODEL:-gpt-5.4}"
OPENCLAW_REASONING_EFFORT="${OPENCLAW_REASONING_EFFORT:-xhigh}"
OPENCLAW_PROVIDER_API="${OPENCLAW_PROVIDER_API:-openai-responses}"
OPENCLAW_INSTALL_CHANNEL="${OPENCLAW_INSTALL_CHANNEL:-latest}"

if [ "${OPENCLAW_REASONING_EFFORT}" = "xhigh" ] && [ "${OPENCLAW_PROVIDER_API}" != "openai-responses" ]; then
    printf 'Warning: OPENCLAW_PROVIDER_API=%s. GPT-5.4 xhigh usually expects openai-responses.\n' "$OPENCLAW_PROVIDER_API" >&2
fi

HOME_DIR="${SETUP_HOME:-${OPENCLAW_HOME:-$HOME}}"
OPENCLAW_DIR="${HOME_DIR}/.openclaw"
ENV_FILE="${OPENCLAW_DIR}/.env"
DEFAULT_CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
API_KEY="${1:-${OPENAI_API_KEY:-}}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
SKIP_GATEWAY_SERVICE="${SKIP_GATEWAY_SERVICE:-0}"

cleanup_tty() {
    stty echo 2>/dev/null || true
}

backup_if_exists() {
    target_path="$1"
    if [ -f "$target_path" ]; then
        backup_path="${target_path}.bak-${TIMESTAMP}"
        cp "$target_path" "$backup_path"
        printf 'Backed up: %s\n' "$backup_path"
    fi
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

env_escape() {
    value="$1"
    case "$value" in
        *[!A-Za-z0-9_./:-]*)
            escaped=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
            printf '"%s"' "$escaped"
            ;;
        *)
            printf '%s' "$value"
            ;;
    esac
}

update_env_file() {
    target_path="$1"
    key="$2"
    value="$3"
    temp_path="${target_path}.tmp.$$"
    escaped_value=$(env_escape "$value")

    if [ -f "$target_path" ]; then
        awk -v key="$key" '
            $0 ~ "^[[:space:]]*" key "=" { next }
            { print }
        ' "$target_path" > "$temp_path"
    else
        : > "$temp_path"
    fi

    printf '%s=%s\n' "$key" "$escaped_value" >> "$temp_path"
    mv "$temp_path" "$target_path"
}

resolve_openclaw_cmd() {
    if command -v openclaw >/dev/null 2>&1; then
        command -v openclaw
        return 0
    fi

    if [ -x "${HOME_DIR}/.openclaw/bin/openclaw" ]; then
        printf '%s\n' "${HOME_DIR}/.openclaw/bin/openclaw"
        return 0
    fi

    if command -v npm >/dev/null 2>&1; then
        npm_prefix="$(npm config get prefix 2>/dev/null || true)"
        if [ -n "$npm_prefix" ] && [ -x "${npm_prefix}/bin/openclaw" ]; then
            printf '%s\n' "${npm_prefix}/bin/openclaw"
            return 0
        fi
    fi

    return 1
}

ensure_openclaw_installed() {
    if openclaw_cmd="$(resolve_openclaw_cmd)"; then
        printf '%s\n' "$openclaw_cmd"
        return 0
    fi

    if [ "$SKIP_INSTALL" = "1" ]; then
        printf 'OpenClaw is not installed and SKIP_INSTALL=1 was provided.\n' >&2
        exit 1
    fi

    printf 'OpenClaw not found. Installing with the official local-prefix installer...\n'
    if [ "$OPENCLAW_INSTALL_CHANNEL" = "latest" ]; then
        curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- --no-onboard
    else
        curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | \
            bash -s -- --no-onboard --version "$OPENCLAW_INSTALL_CHANNEL"
    fi

    if openclaw_cmd="$(resolve_openclaw_cmd)"; then
        printf '%s\n' "$openclaw_cmd"
        return 0
    fi

    printf 'OpenClaw installation completed, but the openclaw command was not found.\n' >&2
    exit 1
}

if [ -z "$API_KEY" ]; then
    trap cleanup_tty EXIT HUP INT TERM
    printf 'Please enter your OPENAI_API_KEY: '
    stty -echo
    IFS= read -r API_KEY
    cleanup_tty
    trap - EXIT HUP INT TERM
    printf '\n'
fi

if [ -z "$API_KEY" ]; then
    printf 'OPENAI_API_KEY cannot be empty.\n' >&2
    exit 1
fi

umask 077
mkdir -p "$OPENCLAW_DIR"

backup_if_exists "$ENV_FILE"
update_env_file "$ENV_FILE" "OPENAI_API_KEY" "$API_KEY"

OPENCLAW_CMD="$(ensure_openclaw_installed)"

CONFIG_FILE_PATH="$("$OPENCLAW_CMD" config file 2>/dev/null | tr -d '\r' || true)"
if [ -z "$CONFIG_FILE_PATH" ]; then
    CONFIG_FILE_PATH="$DEFAULT_CONFIG_FILE"
fi

backup_if_exists "$CONFIG_FILE_PATH"

BATCH_FILE="$(mktemp "${TMPDIR:-/tmp}/openclaw-config.XXXXXX.json")"
API_KEY_PLACEHOLDER='${OPENAI_API_KEY}'
trap 'rm -f "$BATCH_FILE"' EXIT HUP INT TERM

BASE_URL_ESCAPED="$(json_escape "$OPENCLAW_BASE_URL")"
MODEL_ESCAPED="$(json_escape "openai/${OPENCLAW_MODEL}")"
REASONING_ESCAPED="$(json_escape "$OPENCLAW_REASONING_EFFORT")"
PROVIDER_API_ESCAPED="$(json_escape "$OPENCLAW_PROVIDER_API")"
PLACEHOLDER_ESCAPED="$(json_escape "$API_KEY_PLACEHOLDER")"

cat > "$BATCH_FILE" <<EOF
[
  {"path":"gateway.mode","value":"local"},
  {"path":"agents.defaults.model.primary","value":"${MODEL_ESCAPED}"},
  {"path":"agents.defaults.thinkingDefault","value":"${REASONING_ESCAPED}"},
  {"path":"models.mode","value":"merge"},
  {"path":"models.providers.openai.baseUrl","value":"${BASE_URL_ESCAPED}"},
  {"path":"models.providers.openai.api","value":"${PROVIDER_API_ESCAPED}"},
  {"path":"models.providers.openai.apiKey","value":"${PLACEHOLDER_ESCAPED}"}
]
EOF

"$OPENCLAW_CMD" config set --batch-file "$BATCH_FILE" --dry-run >/dev/null
"$OPENCLAW_CMD" config set --batch-file "$BATCH_FILE" >/dev/null
"$OPENCLAW_CMD" config validate >/dev/null

DOCTOR_WARNING=""
if ! "$OPENCLAW_CMD" doctor --non-interactive; then
    DOCTOR_WARNING="openclaw doctor reported a warning"
fi

GATEWAY_WARNING=""
if [ "$SKIP_GATEWAY_SERVICE" != "1" ]; then
    if ! "$OPENCLAW_CMD" gateway install --json >/dev/null; then
        GATEWAY_WARNING="gateway install did not complete cleanly"
    fi
    if ! "$OPENCLAW_CMD" gateway start --json >/dev/null; then
        if [ -n "$GATEWAY_WARNING" ]; then
            GATEWAY_WARNING="${GATEWAY_WARNING}; gateway start did not complete cleanly"
        else
            GATEWAY_WARNING="gateway start did not complete cleanly"
        fi
    fi
    if ! "$OPENCLAW_CMD" gateway status --require-rpc >/dev/null; then
        if [ -n "$GATEWAY_WARNING" ]; then
            GATEWAY_WARNING="${GATEWAY_WARNING}; gateway status probe failed"
        else
            GATEWAY_WARNING="gateway status probe failed"
        fi
    fi
fi

printf '\nOpenClaw setup completed.\n'
printf 'Config file:          %s\n' "$CONFIG_FILE_PATH"
printf 'Global env file:      %s\n' "$ENV_FILE"
printf 'Default model:        %s\n' "openai/${OPENCLAW_MODEL}"
printf 'Reasoning level:      %s\n' "$OPENCLAW_REASONING_EFFORT"
printf 'OpenAI base URL:      %s\n' "$OPENCLAW_BASE_URL"

if [ -n "$DOCTOR_WARNING" ]; then
    printf 'Warning: %s\n' "$DOCTOR_WARNING" >&2
fi

if [ "$SKIP_GATEWAY_SERVICE" = "1" ]; then
    printf 'Gateway service:      skipped by request\n'
    printf 'Manual start:         %s gateway run\n' "$OPENCLAW_CMD"
elif [ -n "$GATEWAY_WARNING" ]; then
    printf 'Warning: %s\n' "$GATEWAY_WARNING" >&2
    printf 'Manual start:         %s gateway run\n' "$OPENCLAW_CMD"
else
    printf 'Gateway service:      installed and started\n'
fi
