#!/usr/bin/env bash
set -u

scope="all"
session_filter=""
target_window_filter=""
target_pane_filter=""
max_items=6
mode="${TMUX_AGENT_STATUS_MODE:-normal}"
done_ttl=""
tree_item_kind=""
tree_item_session=""
tree_item_window=""
tree_item_pane=""
write_state=1

sep='__OCSEP_9b2f6f__'
fmt="#{session_name}${sep}#{window_index}${sep}#{pane_index}${sep}#{pane_id}${sep}#{pane_pid}${sep}#{@agent_label}${sep}#{pane_title}${sep}#{pane_current_command}"
state_file="${TMUX_AGENT_STATUS_STATE_FILE:-$HOME/.cache/tmux-agent-status/state.tsv}"
status_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-agent-status"
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-agent-status/agents"
now="$(date +%s)"

shell_re='^(bash|zsh|fish|sh|dash|ksh|tmux|screen|nvim|vim)$'
nb_space=$'\u00a0'

declare -a AGENT_NAMES=()
declare -a AGENT_ABBREVS=()
declare -a AGENT_PROCESS_NAMES=()
declare -a AGENT_IDENTITY_HINTS=()
declare -a AGENT_WAIT_PATTERNS=()
declare -a AGENT_DONE_PATTERNS=()
declare -a AGENT_ERR_PATTERNS=()
declare -a AGENT_BINARY_STATUS=()
declare -A AGENT_INDEX=()
declare -A capture_cache=()
process_snapshot_loaded=0
process_snapshot=""

while (($#)); do
  case "$1" in
    --all)
      scope="all"
      shift
      ;;
    --alerts-only)
      mode="normal"
      shift
      ;;
    --mode)
      mode="${2:-normal}"
      shift 2
      ;;
    --mode=*)
      mode="${1#*=}"
      shift
      ;;
    --done-ttl)
      done_ttl="${2:-}"
      shift 2
      ;;
    --done-ttl=*)
      done_ttl="${1#*=}"
      shift
      ;;
    --tree-item)
      tree_item_kind="${2:-}"
      case "$tree_item_kind" in
        session)
          tree_item_session="${3:-}"
          shift 3
          ;;
        window)
          tree_item_session="${3:-}"
          tree_item_window="${4:-}"
          shift 4
          ;;
        pane)
          tree_item_pane="${3:-}"
          shift 3
          ;;
        *)
          shift
          ;;
      esac
      ;;
    *)
      scope="session"
      session_filter="$1"
      shift
      ;;
  esac
done

mode="${mode,,}"
case "$mode" in
  brief|normal|verbose) ;;
  *) mode="normal" ;;
esac

if [[ -n "$tree_item_kind" ]]; then
  write_state=0
  case "$tree_item_kind" in
    session)
      scope="session"
      session_filter="$tree_item_session"
      ;;
    window)
      scope="session"
      session_filter="$tree_item_session"
      target_window_filter="$tree_item_window"
      ;;
    pane)
      target_pane_filter="$tree_item_pane"
      ;;
  esac
fi

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

short_label() {
  local s
  s="$(trim "$1")"
  for prefix in "✳ " "⠂ " "⠐ " "● " "· " "• " "◦ "; do
    s="${s#"$prefix"}"
  done
  [[ -n "$s" ]] || return 1
  if (( ${#s} > 26 )); then
    printf '%s…' "${s:0:25}"
  else
    printf '%s' "$s"
  fi
}

normalize_user_label() {
  local s
  s="$(trim "$1")"
  [[ -n "$s" ]] || return 1
  printf '%s' "$s"
}

is_path_like() {
  local s="$1"
  [[ "$s" =~ ^[:~/] || "$s" =~ ^\.[./] || "$s" =~ ^[A-Za-z]:[\\/] ]]
}

is_generic_name() {
  local s="${1,,}"
  case "$s" in
    ""|bash|zsh|fish|sh|dash|ksh|tmux|screen|nvim|vim|claude|claude\ code|opencode|codex|gemini|openclaw|pc4000|'[tmux]') return 0 ;;
    *) return 1 ;;
  esac
}

meaningful_title() {
  local raw="$1"
  local title
  title="$(short_label "$raw" 2>/dev/null || true)"
  [[ -n "$title" ]] || return 1
  is_path_like "$title" && return 1

  if is_generic_name "$title"; then
    local raw_lc="${raw,,}"
    local title_lc="${title,,}"
    if [[ "$raw_lc" != *'✳ '* && "$title_lc" != "claude code" ]]; then
      return 1
    fi
  fi

  printf '%s' "$title"
}

get_tmux_option() {
  tmux show-options -gqv "$1" 2>/dev/null || true
}

write_default_conf() {
  local file="$1"
  local content="$2"
  [[ -f "$file" ]] && return 0
  printf '%s\n' "$content" > "$file"
}

ensure_default_configs() {
  mkdir -p "$conf_dir"
  if compgen -G "$conf_dir/*.conf" >/dev/null 2>&1; then
    return 0
  fi

  write_default_conf "$conf_dir/claude.conf" 'name=claude
abbrev=CC
process_names=claude
identity_hints=claude code,claude,[claude]
wait_patterns=do you want to proceed|bash command|esc to cancel|tab to amend|ctrl\+e to explain|press enter|press any key|yes, and don.?t ask again|accept edits on
 done_patterns=^[[:space:]]*❯[[:space:]]*$
err_patterns=\berror:\b|\bfailed\b|exception|traceback|timed out'

  write_default_conf "$conf_dir/opencode.conf" 'name=opencode
abbrev=OC
process_names=opencode
identity_hints=opencode
wait_patterns=select an option|press enter|press any key|do you want to proceed
 done_patterns=next action:|would you like me|priority order for hacking|what to do:|accept edits on|completed successfully|finished in
err_patterns=\berror:\b|\bfailed\b|exception|traceback|timed out'

  write_default_conf "$conf_dir/codex.conf" 'name=codex
abbrev=CX
process_names=codex
identity_hints=codex
wait_patterns=do you want to proceed|bash command|press enter|press any key
 done_patterns=^[[:space:]]*❯[[:space:]]*$|completed successfully
err_patterns=\berror:\b|\bfailed\b|exception|traceback|timed out'

  write_default_conf "$conf_dir/gemini.conf" 'name=gemini
abbrev=GM
process_names=gemini
identity_hints=gemini
wait_patterns=do you want to proceed|press enter|press any key
 done_patterns=^[[:space:]]*❯[[:space:]]*$|completed successfully
err_patterns=\berror:\b|\bfailed\b|exception|traceback|timed out'

  write_default_conf "$conf_dir/openclaw.conf" 'name=openclaw
abbrev=AI
process_names=openclaw
identity_hints=openclaw
wait_patterns=
 done_patterns=
err_patterns=
binary_status=true'
}

load_agents() {
  AGENT_NAMES=()
  AGENT_ABBREVS=()
  AGENT_PROCESS_NAMES=()
  AGENT_IDENTITY_HINTS=()
  AGENT_WAIT_PATTERNS=()
  AGENT_DONE_PATTERNS=()
  AGENT_ERR_PATTERNS=()
  AGENT_BINARY_STATUS=()
  AGENT_INDEX=()

  local i=0 conf_file line key value
  for conf_file in "$conf_dir"/*.conf; do
    [[ -f "$conf_file" ]] || continue

    local name="" abbrev="" procs="" hints="" wait_pat="" done_pat="" err_pat="" binary="false"
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(trim "$line")"
      [[ -n "$line" && "$line" != \#* ]] || continue
      [[ "$line" == *=* ]] || continue
      key="$(trim "${line%%=*}")"
      value="$(trim "${line#*=}")"
      case "$key" in
        name) name="$value" ;;
        abbrev) abbrev="$value" ;;
        process_names) procs="$value" ;;
        identity_hints) hints="$value" ;;
        wait_patterns) wait_pat="$value" ;;
        done_patterns) done_pat="$value" ;;
        err_patterns) err_pat="$value" ;;
        binary_status) binary="$value" ;;
      esac
    done < "$conf_file"

    [[ -n "$name" ]] || continue
    AGENT_NAMES+=("$name")
    AGENT_ABBREVS+=("${abbrev:-??}")
    AGENT_PROCESS_NAMES+=("$procs")
    AGENT_IDENTITY_HINTS+=("$hints")
    AGENT_WAIT_PATTERNS+=("$wait_pat")
    AGENT_DONE_PATTERNS+=("$done_pat")
    AGENT_ERR_PATTERNS+=("$err_pat")
    AGENT_BINARY_STATUS+=("${binary:-false}")
    AGENT_INDEX["$name"]="$i"
    ((i++))
  done
}

kind_abbrev() {
  local idx="${AGENT_INDEX[$1]-}"
  if [[ -n "$idx" ]]; then
    printf '%s' "${AGENT_ABBREVS[$idx]}"
  else
    printf '??'
  fi
}

is_coding_kind() {
  local kind="$1"
  local idx="${AGENT_INDEX[$kind]-}"
  [[ -n "$idx" ]] || return 1
  [[ "$kind" != "openclaw" ]]
}

action_color() {
  case "$1" in
    WAIT) printf 'colour226' ;;
    ERR) printf 'colour196' ;;
    DONE) printf 'colour45' ;;
    WORK) printf 'colour46' ;;
    *) printf 'colour244' ;;
  esac
}

status_rank() {
  case "$1" in
    ERR) printf '4' ;;
    WAIT) printf '3' ;;
    WORK) printf '2' ;;
    DONE) printf '1' ;;
    *) printf '0' ;;
  esac
}

detect_agent_by_hints() {
  local text="${1,,}"
  local i hint
  for ((i = 0; i < ${#AGENT_NAMES[@]}; i++)); do
    IFS=',' read -r -a hints <<< "${AGENT_IDENTITY_HINTS[$i]}"
    for hint in "${hints[@]}"; do
      hint="$(trim "${hint,,}")"
      [[ -n "$hint" ]] || continue
      if [[ "$text" == *"$hint"* ]]; then
        printf '%s' "${AGENT_NAMES[$i]}"
        return 0
      fi
    done
  done
  return 1
}

ensure_process_snapshot() {
  if (( process_snapshot_loaded )); then
    return 0
  fi
  process_snapshot="$(ps -eo pid=,ppid=,comm= 2>/dev/null || true)"
  process_snapshot_loaded=1
}

descendant_commands_for() {
  local root="$1"
  [[ "$root" =~ ^[0-9]+$ ]] || return 1
  ensure_process_snapshot
  [[ -n "$process_snapshot" ]] || return 1

  awk -v root="$root" '
    {
      pid=$1
      ppid=$2
      $1=""
      $2=""
      sub(/^[[:space:]]+/, "")
      comm=$0
      P[pid]=ppid
      C[pid]=comm
    }
    END {
      if (!(root in C)) exit
      want[root]=1
      changed=1
      while (changed) {
        changed=0
        for (pid in P) {
          if ((P[pid] in want) && !(pid in want)) {
            want[pid]=1
            changed=1
          }
        }
      }
      for (pid in want) if (pid in C) print C[pid]
    }
  ' <<< "$process_snapshot"
}

detect_agent_by_process() {
  local pane_pid="$1"
  local descendants lc_descendants i proc
  descendants="$(descendant_commands_for "$pane_pid" 2>/dev/null || true)"
  [[ -n "$descendants" ]] || return 1
  lc_descendants="${descendants,,}"

  for ((i = 0; i < ${#AGENT_NAMES[@]}; i++)); do
    IFS=',' read -r -a procs <<< "${AGENT_PROCESS_NAMES[$i]}"
    for proc in "${procs[@]}"; do
      proc="$(trim "${proc,,}")"
      [[ -n "$proc" ]] || continue
      if grep -qiw -- "$proc" <<< "$lc_descendants"; then
        printf '%s' "${AGENT_NAMES[$i]}"
        return 0
      fi
    done
  done
  return 1
}

read_file_status() {
  local pane_id="$1"
  local safe_id status_file agent status ts
  safe_id="${pane_id//%/_}"
  status_file="$status_dir/$safe_id"
  [[ -f "$status_file" ]] || return 1

  IFS=$'\t' read -r agent status ts < "$status_file" 2>/dev/null || return 1
  [[ -n "$agent" && -n "$status" ]] || return 1
  case "$status" in
    WAIT|ERR|DONE|WORK|IDLE) ;;
    *) return 1 ;;
  esac

  printf '%s\t%s' "$agent" "$status"
}

get_capture() {
  local pane_id="$1"
  if [[ -n "${capture_cache[$pane_id]+set}" ]]; then
    printf '%s' "${capture_cache[$pane_id]}"
    return 0
  fi

  local cap
  cap="$(tmux capture-pane -p -J -t "$pane_id" -S -60 2>/dev/null | tail -n 30)"
  capture_cache["$pane_id"]="$cap"
  printf '%s' "$cap"
}

status_for() {
  local kind="$1"
  local current_cmd="$2"
  local text="$3"
  local idx="${AGENT_INDEX[$kind]-}"

  [[ -n "$idx" ]] || {
    if [[ ! "${current_cmd,,}" =~ $shell_re ]]; then
      printf 'WORK'
    else
      printf 'IDLE'
    fi
    return 0
  }

  if [[ "${AGENT_BINARY_STATUS[$idx],,}" == "true" ]]; then
    if [[ ! "${current_cmd,,}" =~ $shell_re ]]; then
      printf 'WORK'
    else
      printf 'IDLE'
    fi
    return 0
  fi

  local bottom lc_bottom wait_pat done_pat err_pat
  bottom="$(printf '%s\n' "$text" | tail -n 18)"
  bottom="${bottom//${nb_space}/ }"
  lc_bottom="${bottom,,}"
  wait_pat="${AGENT_WAIT_PATTERNS[$idx]}"
  done_pat="${AGENT_DONE_PATTERNS[$idx]}"
  err_pat="${AGENT_ERR_PATTERNS[$idx]}"

  if [[ -n "$wait_pat" ]] && grep -Eiq "$wait_pat" <<< "$lc_bottom"; then
    printf 'WAIT'
  elif [[ -n "$err_pat" ]] && grep -Eiq "$err_pat" <<< "$lc_bottom"; then
    printf 'ERR'
  elif [[ -n "$done_pat" ]] && grep -Eq "$done_pat" <<< "$bottom"; then
    printf 'DONE'
  elif [[ ! "${current_cmd,,}" =~ $shell_re ]]; then
    printf 'WORK'
  else
    printf 'IDLE'
  fi
}

brief_name_for() {
  local session="$1"
  local user_label="$2"
  local pane_title="$3"
  local nice_title=""

  if [[ -n "$user_label" ]]; then
    short_label "$user_label"
    return 0
  fi

  nice_title="$(meaningful_title "$pane_title" 2>/dev/null || true)"
  if [[ -n "$nice_title" ]]; then
    printf '%s' "$nice_title"
    return 0
  fi

  printf '%s' "$session"
}

format_item() {
  local session="$1"
  local label="$2"
  local status="$3"
  local kind="$4"
  local window_index="$5"
  local pane_index="$6"
  local display kind_short color

  kind_short="$(kind_abbrev "$kind")"
  color="$(action_color "$status")"

  case "$mode" in
    brief)
      display="${label}/${kind_short}:${status}"
      ;;
    verbose)
      display="${session}[${window_index}.${pane_index}]/${kind_short}/${label}:${status}"
      ;;
    *)
      display="${session}/${label}:${status}"
      ;;
  esac

  if [[ "$status" == "IDLE" ]]; then
    printf '#[fg=%s]%s#[default]' "$color" "$display"
  else
    printf '#[fg=%s,bold]%s#[default]' "$color" "$display"
  fi
}

format_tree_token() {
  local kind="$1"
  local status="$2"
  local count="${3:-1}"
  local token

  token="$(kind_abbrev "$kind"):${status}"
  if (( count > 1 )); then
    token+="+$((count - 1))"
  fi
  printf '[%s]' "$token"
}

join_items() {
  local -n arr_ref=$1
  local count=${#arr_ref[@]}
  local limit=$count
  if (( limit > max_items )); then
    limit=$max_items
  fi

  (( count > 0 )) || return 1

  printf '%s' "${arr_ref[0]}"
  local i
  for ((i = 1; i < limit; i++)); do
    printf ' %s' "${arr_ref[i]}"
  done
  if (( count > limit )); then
    printf ' #[fg=colour244]+%d#[default]' "$((count - limit))"
  fi
}

parse_line() {
  local line="$1"
  pane_session="${line%%${sep}*}"
  line="${line#*${sep}}"
  window_index="${line%%${sep}*}"
  line="${line#*${sep}}"
  pane_index="${line%%${sep}*}"
  line="${line#*${sep}}"
  pane_id="${line%%${sep}*}"
  line="${line#*${sep}}"
  pane_pid="${line%%${sep}*}"
  line="${line#*${sep}}"
  agent_label="${line%%${sep}*}"
  line="${line#*${sep}}"
  pane_title="${line%%${sep}*}"
  current_cmd="${line#*${sep}}"
}

declare -A prev_status=()
declare -A prev_changed=()
declare -A state_status=()
declare -A state_changed=()
declare -A state_seen=()
state_keys=()

load_state() {
  [[ -f "$state_file" ]] || return 0
  while IFS=$'\t' read -r pane old_status changed_at; do
    [[ -n "$pane" ]] || continue
    prev_status["$pane"]="$old_status"
    prev_changed["$pane"]="$changed_at"
  done < "$state_file"
}

mark_state() {
  local pane="$1"
  local status="$2"
  local changed_at="$3"
  if [[ -z "${state_seen[$pane]-}" ]]; then
    state_seen["$pane"]=1
    state_keys+=("$pane")
  fi
  state_status["$pane"]="$status"
  state_changed["$pane"]="$changed_at"
}

save_state() {
  local dir tmp pane
  dir="$(dirname "$state_file")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.tmux-agent-status.XXXXXX")"
  for pane in "${state_keys[@]}"; do
    printf '%s\t%s\t%s\n' "$pane" "${state_status[$pane]}" "${state_changed[$pane]}"
  done > "$tmp"
  mv "$tmp" "$state_file"
}

status_changed_at() {
  local pane="$1"
  local status="$2"
  if [[ "${prev_status[$pane]-}" == "$status" && -n "${prev_changed[$pane]-}" ]]; then
    printf '%s' "${prev_changed[$pane]}"
  else
    printf '%s' "$now"
  fi
}

status_is_visible() {
  local status="$1"
  local changed_at="$2"
  [[ -n "$status" && "$status" != "IDLE" ]] || return 1
  if [[ "$status" == "DONE" ]] && (( done_ttl > 0 )) && (( now - changed_at > done_ttl )); then
    return 1
  fi
  return 0
}

should_show_main() {
  local status="$1"
  local kind="$2"
  case "$mode" in
    brief)
      is_coding_kind "$kind" && [[ -n "$status" ]]
      ;;
    normal)
      [[ "$status" == "WAIT" || "$status" == "ERR" || "$status" == "DONE" ]]
      ;;
    verbose)
      [[ "$status" == "WAIT" || "$status" == "ERR" || "$status" == "DONE" || "$status" == "WORK" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

declare -A session_seen=()
declare -A session_rank=()
declare -A session_status=()
declare -A session_kind=()
declare -A session_name=()
declare -A session_count=()
declare -A session_fallback=()
session_keys=()

declare -A window_seen=()
declare -A window_rank=()
declare -A window_status=()
declare -A window_kind=()
declare -A window_name=()
declare -A window_count=()
declare -A window_fallback=()
window_keys=()

declare -A pane_tree_status=()
declare -A pane_tree_kind=()

update_summary() {
  local prefix="$1"
  local key="$2"
  local status="$3"
  local kind="$4"
  local name="$5"
  local fallback_name="$6"
  local rank prev

  is_coding_kind "$kind" || return 0
  rank="$(status_rank "$status")"
  (( rank > 0 )) || return 0

  local -n seen_map="${prefix}_seen"
  local -n keys_ref="${prefix}_keys"
  local -n rank_map="${prefix}_rank"
  local -n status_map="${prefix}_status"
  local -n kind_map="${prefix}_kind"
  local -n name_map="${prefix}_name"
  local -n count_map="${prefix}_count"
  local -n fallback_map="${prefix}_fallback"

  if [[ -z "${seen_map[$key]-}" ]]; then
    seen_map["$key"]=1
    keys_ref+=("$key")
    count_map["$key"]=0
  fi
  count_map["$key"]=$(( ${count_map[$key]:-0} + 1 ))
  fallback_map["$key"]="$fallback_name"

  prev="${rank_map[$key]-0}"
  if (( rank > prev )); then
    rank_map["$key"]="$rank"
    status_map["$key"]="$status"
    kind_map["$key"]="$kind"
    name_map["$key"]="$name"
  elif (( rank == prev )); then
    if [[ "${name_map[$key]-$key}" == "$key" && "$name" != "$key" ]]; then
      name_map["$key"]="$name"
      kind_map["$key"]="$kind"
      status_map["$key"]="$status"
    fi
  fi
}

ensure_default_configs
load_agents

if [[ -z "${done_ttl:-}" ]]; then
  done_ttl="$(get_tmux_option @agent_status_done_ttl)"
fi
[[ "$done_ttl" =~ ^[0-9]+$ ]] || done_ttl=180

wait_items=()
err_items=()
done_items=()
work_items=()

load_state

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  [[ "$line" == *"$sep"* ]] || continue
  parse_line "$line"

  [[ -n "$pane_session" ]] || continue
  if [[ "$scope" == "session" && "$pane_session" != "$session_filter" ]]; then
    continue
  fi
  if [[ -n "$target_window_filter" && "$window_index" != "$target_window_filter" ]]; then
    continue
  fi
  if [[ -n "$target_pane_filter" && "$pane_id" != "$target_pane_filter" ]]; then
    continue
  fi

  user_label=''
  local_label=''
  brief_label=''
  kind=''
  raw_status=''
  capture=''

  if user_label="$(normalize_user_label "$agent_label" 2>/dev/null)"; then
    local_label="$(short_label "$user_label" 2>/dev/null || printf '%s' "$user_label")"
    kind="$(detect_agent_by_hints "$user_label" 2>/dev/null || true)"
  fi

  file_result="$(read_file_status "$pane_id" 2>/dev/null || true)"
  if [[ -n "$file_result" ]]; then
    IFS=$'\t' read -r file_kind raw_status <<< "$file_result"
    kind="$file_kind"
  fi

  if [[ -z "$kind" && -n "$pane_pid" ]]; then
    kind="$(detect_agent_by_process "$pane_pid" 2>/dev/null || true)"
  fi
  if [[ -z "$kind" ]]; then
    kind="$(detect_agent_by_hints "$current_cmd $pane_title $pane_session" 2>/dev/null || true)"
  fi
  if [[ -z "$kind" ]]; then
    capture="$(get_capture "$pane_id")"
    kind="$(detect_agent_by_hints "$capture" 2>/dev/null || true)"
  fi

  [[ -n "$kind" ]] || continue

  if [[ -z "$local_label" ]]; then
    local_label="$(meaningful_title "$pane_title" 2>/dev/null || true)"
  fi
  if [[ -z "$local_label" ]]; then
    local_label="${kind}@${window_index}.${pane_index}"
  fi

  brief_label="$(brief_name_for "$pane_session" "$user_label" "$pane_title" 2>/dev/null || printf '%s' "$pane_session")"

  if [[ -z "$raw_status" ]]; then
    if [[ -z "$capture" ]]; then
      capture="$(get_capture "$pane_id")"
    fi
    raw_status="$(status_for "$kind" "$current_cmd" "$capture")"
  fi

  changed_at="$(status_changed_at "$pane_id" "$raw_status")"
  mark_state "$pane_id" "$raw_status" "$changed_at"

  visible_status=""
  if status_is_visible "$raw_status" "$changed_at"; then
    visible_status="$raw_status"
  fi

  if [[ -n "$visible_status" ]]; then
    update_summary session "$pane_session" "$visible_status" "$kind" "$brief_label" "$pane_session"
    update_summary window "${pane_session}:${window_index}" "$visible_status" "$kind" "$brief_label" "$pane_session:$window_index"
    if is_coding_kind "$kind"; then
      pane_tree_status["$pane_id"]="$visible_status"
      pane_tree_kind["$pane_id"]="$kind"
    fi
  fi

  should_show_main "$visible_status" "$kind" || continue

  if [[ "$mode" == "brief" ]]; then
    continue
  fi

  item="$(format_item "$pane_session" "$local_label" "$visible_status" "$kind" "$window_index" "$pane_index")"
  case "$visible_status" in
    WAIT) wait_items+=("$item") ;;
    ERR) err_items+=("$item") ;;
    DONE) done_items+=("$item") ;;
    WORK) work_items+=("$item") ;;
  esac
done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)

(( write_state )) && save_state

render_tree_item() {
  local status kind count key
  case "$tree_item_kind" in
    session)
      key="$tree_item_session"
      status="${session_status[$key]-}"
      kind="${session_kind[$key]-}"
      count="${session_count[$key]-0}"
      ;;
    window)
      key="${tree_item_session}:${tree_item_window}"
      status="${window_status[$key]-}"
      kind="${window_kind[$key]-}"
      count="${window_count[$key]-0}"
      ;;
    pane)
      status="${pane_tree_status[$tree_item_pane]-}"
      kind="${pane_tree_kind[$tree_item_pane]-}"
      count=1
      ;;
    *)
      return 0
      ;;
  esac

  [[ -n "$status" && -n "$kind" ]] || return 0
  format_tree_token "$kind" "$status" "$count"
}

if [[ -n "$tree_item_kind" ]]; then
  render_tree_item
  exit 0
fi

filtered=()
if [[ "$mode" == "brief" ]]; then
  declare -A used_names=()
  for session in "${session_keys[@]}"; do
    name="${session_name[$session]-$session}"
    used_names["$name"]=$(( ${used_names[$name]:-0} + 1 ))
  done

  for session in "${session_keys[@]}"; do
    status="${session_status[$session]-}"
    kind="${session_kind[$session]-}"
    name="${session_name[$session]-$session}"
    fallback="${session_fallback[$session]-$session}"
    [[ -n "$status" && -n "$kind" ]] || continue
    if (( ${used_names[$name]:-0} > 1 )); then
      name="$fallback"
    fi
    filtered+=("$(format_item "$session" "$name" "$status" "$kind" "" "")")
  done
else
  groups=("wait_items" "err_items" "done_items")
  if [[ "$mode" == "verbose" ]]; then
    groups+=("work_items")
  fi
  for group in "${groups[@]}"; do
    declare -n ref="$group"
    for item in "${ref[@]}"; do
      [[ -n "$item" ]] && filtered+=("$item")
    done
  done
fi

if ((${#filtered[@]} == 0)); then
  printf '#[fg=colour244]agents:clear#[default]'
  exit 0
fi

join_items filtered
