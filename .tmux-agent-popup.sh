#!/usr/bin/env bash
set -u

status_script="$HOME/.tmux-agent-status.sh"
refresh_seconds="${TMUX_AGENT_POPUP_REFRESH:-1}"
[[ "$refresh_seconds" =~ ^[0-9]+$ ]] || refresh_seconds=1

cleanup() {
  stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

pretty_title() {
  local title="$(trim "$1")"
  title="${title#✳ }"
  title="${title#⠂ }"
  title="${title#⠐ }"
  [[ -n "$title" ]] || return 1
  printf '%s' "$title"
}

render_once() {
  printf '\033[H\033[2J'
  printf 'Agent Status Dashboard  (q to close, r to refresh)\n\n'

  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    local sbadge= wcount=0
    sbadge="$($status_script --tree-item session "$session" 2>/dev/null || true)"
    [[ -n "$sbadge" ]] || continue

    printf '%s %s\n' "$session" "$sbadge"

    while IFS=$'\t' read -r window_index window_name; do
      [[ -n "$window_index" ]] || continue
      local wbadge pane_lines=0
      wbadge="$($status_script --tree-item window "$session" "$window_index" 2>/dev/null || true)"
      [[ -n "$wbadge" ]] || continue
      wcount=$((wcount + 1))
      printf '  [%s] %s %s\n' "$window_index" "$window_name" "$wbadge"

      while IFS=$'\t' read -r pane_index pane_id pane_title pane_cmd; do
        [[ -n "$pane_id" ]] || continue
        local pbadge label
        pbadge="$($status_script --tree-item pane "$pane_id" 2>/dev/null || true)"
        [[ -n "$pbadge" ]] || continue
        label="$(pretty_title "$pane_title" 2>/dev/null || true)"
        [[ -n "$label" ]] || label="$pane_cmd"
        [[ -n "$label" ]] || label="$pane_id"
        pane_lines=$((pane_lines + 1))
        printf '      - %s %s\n' "$label" "$pbadge"
      done < <(tmux list-panes -t "$session:$window_index" -F $'#{pane_index}\t#{pane_id}\t#{pane_title}\t#{pane_current_command}' 2>/dev/null)
    done < <(tmux list-windows -t "$session" -F $'#{window_index}\t#{window_name}' 2>/dev/null)

    if (( wcount == 0 )); then
      printf '  (no active agent windows)\n'
    fi
    printf '\n'
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

  printf 'Mode: %s | DONE TTL: %s s\n' "$(tmux show-options -gqv @agent_status_mode 2>/dev/null || echo normal)" "$(tmux show-options -gqv @agent_status_done_ttl 2>/dev/null || echo 180)"
}

stty -echo -icanon time 0 min 0 2>/dev/null || true
while true; do
  render_once
  for _ in $(seq 1 "$refresh_seconds" 2>/dev/null || echo 1); do
    IFS= read -rsn1 key || true
    case "$key" in
      q|Q) exit 0 ;;
      r|R) break ;;
      *) sleep 1 ;;
    esac
  done
done
