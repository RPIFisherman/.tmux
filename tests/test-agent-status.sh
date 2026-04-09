#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
status_script="$repo_root/.tmux-agent-status.sh"
popup_script="$repo_root/.tmux-agent-popup.sh"
wrapper_script="$repo_root/agent-wrapper.sh"
install_script="$repo_root/install.sh"

bash -n "$status_script"
bash -n "$popup_script"
bash -n "$wrapper_script"
bash -n "$install_script"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
XDG_CONFIG_HOME="$TMPDIR" "$status_script" --tree-item session claude >/dev/null 2>&1 || true

for f in claude.conf opencode.conf codex.conf gemini.conf openclaw.conf; do
  test -f "$TMPDIR/tmux-agent-status/agents/$f"
done

echo 'tmux agent tests: OK'
