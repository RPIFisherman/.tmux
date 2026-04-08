#!/usr/bin/env bash
set -u

[[ $# -ge 2 ]] || {
  printf 'Usage: %s <agent-name> <real-command> [args...]\n' "${0##*/}" >&2
  exit 2
}

agent_name="$1"
shift
real_cmd="$1"
shift

status_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-agent-status"
pane_id="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"

if [[ -z "$pane_id" ]]; then
  exec "$real_cmd" "$@"
fi

mkdir -p "$status_dir"
safe_id="${pane_id//%/_}"
status_file="$status_dir/$safe_id"

write_status() {
  printf '%s\t%s\t%s\n' "$agent_name" "$1" "$(date +%s)" > "$status_file"
}

cleanup() {
  rm -f "$status_file"
}
trap cleanup EXIT INT TERM

write_status WORK
"$real_cmd" "$@"
exit_code=$?

if (( exit_code == 0 )); then
  write_status DONE
else
  write_status ERR
fi

sleep 2
cleanup
exit "$exit_code"
