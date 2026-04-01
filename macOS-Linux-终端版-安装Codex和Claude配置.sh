#!/bin/sh

set -eu

CODEX_BASE_URL="https://aizhiwen.top"
CODEX_MODEL="gpt-5.4"
CODEX_REVIEW_MODEL="gpt-5.4"
CODEX_REASONING_EFFORT="xhigh"

CLAUDE_BASE_URL="https://aizhiwen.top"
CLAUDE_DISABLE_TRAFFIC="1"
CLAUDE_ATTRIBUTION_HEADER="0"

HOME_OVERRIDE="${CODEX_SETUP_HOME:-${SETUP_HOME:-}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
API_KEY="${1:-}"
CLAUDE_AUTH_TOKEN="${2:-}"

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

ensure_managed_source_block() {
    profile_path="$1"
    helper_path="$2"
    start_marker="# >>> Claude Code env >>>"
    end_marker="# <<< Claude Code env <<<"
    source_line="[ -f \"$helper_path\" ] && . \"$helper_path\""
    temp_path="${profile_path}.tmp.$$"

    backup_if_exists "$profile_path"

    if [ -f "$profile_path" ]; then
        awk -v start="$start_marker" -v end="$end_marker" '
            $0 == start { skip = 1; next }
            skip && $0 == end { skip = 0; next }
            skip { next }
            { print }
        ' "$profile_path" > "$temp_path"
    else
        : > "$temp_path"
    fi

    {
        if [ -s "$temp_path" ]; then
            cat "$temp_path"
            printf '\n'
        fi
        printf '%s\n' "$start_marker"
        printf '%s\n' "$source_line"
        printf '%s\n' "$end_marker"
    } > "$profile_path"

    rm -f "$temp_path"
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

if [ -z "$CLAUDE_AUTH_TOKEN" ]; then
    trap cleanup_tty EXIT HUP INT TERM
    printf 'Please enter your ANTHROPIC_AUTH_TOKEN: '
    stty -echo
    IFS= read -r CLAUDE_AUTH_TOKEN
    cleanup_tty
    trap - EXIT HUP INT TERM
    printf '\n'
fi

if [ -z "$API_KEY" ]; then
    printf 'OPENAI_API_KEY cannot be empty.\n' >&2
    exit 1
fi

if [ -z "$CLAUDE_AUTH_TOKEN" ]; then
    printf 'ANTHROPIC_AUTH_TOKEN cannot be empty.\n' >&2
    exit 1
fi

HOME_DIR="${HOME}"
if [ -n "$HOME_OVERRIDE" ]; then
    HOME_DIR="$HOME_OVERRIDE"
fi

CODEX_DIR="${HOME_DIR}/.codex"
CLAUDE_DIR="${HOME_DIR}/.claude"
CODEX_CONFIG_PATH="${CODEX_DIR}/config.toml"
CODEX_AUTH_PATH="${CODEX_DIR}/auth.json"
CLAUDE_SETTINGS_PATH="${CLAUDE_DIR}/settings.json"
CLAUDE_ENV_PATH="${CLAUDE_DIR}/claude-code-env.sh"

umask 077
mkdir -p "$CODEX_DIR" "$CLAUDE_DIR"

backup_if_exists "$CODEX_CONFIG_PATH"
backup_if_exists "$CODEX_AUTH_PATH"
backup_if_exists "$CLAUDE_SETTINGS_PATH"
backup_if_exists "$CLAUDE_ENV_PATH"

cat > "$CODEX_CONFIG_PATH" <<EOF
model_provider = "OpenAI"
model = "$CODEX_MODEL"
review_model = "$CODEX_REVIEW_MODEL"
model_reasoning_effort = "$CODEX_REASONING_EFFORT"
disable_response_storage = true
network_access = "enabled"
windows_wsl_setup_acknowledged = true
model_context_window = 1000000
model_auto_compact_token_limit = 900000

[model_providers.OpenAI]
name = "OpenAI"
base_url = "$CODEX_BASE_URL"
wire_api = "responses"
requires_openai_auth = true
EOF

API_KEY_ESCAPED="$(json_escape "$API_KEY")"
printf '{\n  "OPENAI_API_KEY": "%s"\n}\n' "$API_KEY_ESCAPED" > "$CODEX_AUTH_PATH"

cat > "$CLAUDE_SETTINGS_PATH" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$CLAUDE_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$CLAUDE_AUTH_TOKEN",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "$CLAUDE_DISABLE_TRAFFIC",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "$CLAUDE_ATTRIBUTION_HEADER"
  }
}
EOF

cat > "$CLAUDE_ENV_PATH" <<EOF
export ANTHROPIC_BASE_URL="$CLAUDE_BASE_URL"
export ANTHROPIC_AUTH_TOKEN="$CLAUDE_AUTH_TOKEN"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$CLAUDE_DISABLE_TRAFFIC"
export CLAUDE_CODE_ATTRIBUTION_HEADER="$CLAUDE_ATTRIBUTION_HEADER"
EOF

chmod 600 "$CODEX_CONFIG_PATH" "$CODEX_AUTH_PATH" "$CLAUDE_SETTINGS_PATH" "$CLAUDE_ENV_PATH" 2>/dev/null || true

for profile_name in ".bashrc" ".bash_profile" ".zshrc" ".zprofile" ".profile"
do
    ensure_managed_source_block "${HOME_DIR}/${profile_name}" "$CLAUDE_ENV_PATH"
done

printf '\nCodex and Claude Code configuration installed successfully.\n'
printf 'Codex config:        %s\n' "$CODEX_CONFIG_PATH"
printf 'Codex auth:          %s\n' "$CODEX_AUTH_PATH"
printf 'Claude settings:     %s\n' "$CLAUDE_SETTINGS_PATH"
printf 'Claude env helper:   %s\n' "$CLAUDE_ENV_PATH"
