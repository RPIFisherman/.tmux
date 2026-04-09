#!/bin/bash
# Oh my tmux!
# 💛🩷💙🖤❤️🤍
# https://github.com/RPIFisherman/.tmux
# (‑●‑●)> dual licensed under the WTFPL v2 license and the MIT license,
#         without any warranty.
#         Copyright 2012— Gregory Pakosz (@gpakosz).
#
# ------------------------------------------------------------------------------
# 🚨 PLEASE REVIEW THE CONTENT OF THIS FILE BEFORE BLINDING PIPING TO CURL
# ------------------------------------------------------------------------------
{
if [ ${EUID:-$(id -u)} -eq 0 ]; then
  printf '❌ Do not execute this script as root!\n' >&2 && exit 1
fi

if [ -z "$BASH_VERSION" ]; then
  printf '❌ This installation script requires bash\n' >&2 && exit 1
fi

if ! tmux -V >/dev/null 2>&1; then
  printf '❌ tmux is not installed\n' >&2 && exit 1
fi

is_true() {
  case "$1" in
    true|yes|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if ! is_true "$PERMISSIVE" && [ -n "$TMUX" ]; then
  printf '❌ tmux is currently running, please terminate the server\n' >&2 && exit 1
fi

install() {
  printf '🎢 Installing Oh my tmux! Buckle up!\n' >&2
  printf '\n' >&2
  now=$(date +'%Y%d%m%S')

  for dir in "${XDG_CONFIG_HOME:-$HOME/.config}/tmux" "$HOME/.tmux"; do
    if [ -d "$dir" ]; then
      printf '⚠️  %s directory exists, making a backup → %s\n' "${dir/#"$HOME"/'~'}" "${dir/#"$HOME"/'~'}.$now" >&2
      if ! is_true "$DRY_RUN"; then
        mv "$dir" "$dir.$now"
      fi
    fi
  done

  for conf in "$HOME/.tmux.conf" \
              "$HOME/.tmux.conf.local" \
              "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" \
              "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf.local"; do
    if [ -f "$conf" ]; then
      if [ -L "$conf" ]; then
        printf '⚠️  %s symlink exists, removing → 🗑️\n' "${conf/#"$HOME"/'~'}" >&2
        if ! is_true "$DRY_RUN"; then
          rm -f "$conf"
        fi
      else
        printf '⚠️  %s file exists, making a backup -> %s\n' "${conf/#"$HOME"/'~'}" "${conf/#"$HOME"/'~'}.$now" >&2
        if ! is_true "$DRY_RUN"; then
          mv "$conf" "$conf.$now"
        fi
      fi
    fi
  done

  if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}" ]; then
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
    TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  else
    TMUX_CONF="$HOME/.tmux.conf"
  fi
  TMUX_CONF_LOCAL="$TMUX_CONF.local"
  mkdir -p "$HOME/.local/bin"

  OH_MY_TMUX_CLONE_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/oh-my-tmux"
  if [ -d "$OH_MY_TMUX_CLONE_PATH" ]; then
    printf '⚠️  %s exists, making a backup\n' "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}" >&2
    printf '%s → %s\n' "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}" "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}.$now" >&2
    if ! is_true "$DRY_RUN"; then
      mv "$OH_MY_TMUX_CLONE_PATH" "$OH_MY_TMUX_CLONE_PATH.$now"
    fi
  fi

  printf '\n'
  printf '✅ Using %s\n' "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}" >&2
  printf '✅ Using %s\n' "${TMUX_CONF/#"$HOME"/'~'}" >&2
  printf '✅ Using %s\n' "${TMUX_CONF_LOCAL/#"$HOME"/'~'}" >&2

  printf '\n'
  OH_MY_TMUX_REPOSITORY=${OH_MY_TMUX_REPOSITORY:-https://github.com/RPIFisherman/.tmux.git}
  printf '⬇️  Cloning Oh my tmux! repository...\n' >&2
  if ! is_true "$DRY_RUN"; then
    mkdir -p "$(dirname "$OH_MY_TMUX_CLONE_PATH")"
    if ! git clone -q --single-branch "$OH_MY_TMUX_REPOSITORY" "$OH_MY_TMUX_CLONE_PATH"; then
      printf '❌ Failed\n' >&2 && exit 1
    fi
  fi

  printf '\n'
  if is_true "$DRY_RUN" || ln -s -f "$OH_MY_TMUX_CLONE_PATH/.tmux.conf" "$TMUX_CONF"; then
    printf '✅ Symlinked %s → %s\n' "${TMUX_CONF/#"$HOME"/'~'}" "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}/.tmux.conf" >&2
  fi
  if is_true "$DRY_RUN" || cp "$OH_MY_TMUX_CLONE_PATH/.tmux.conf.local" "$TMUX_CONF_LOCAL"; then
    printf '✅ Copied %s → %s\n' "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}/.tmux.conf.local" "${TMUX_CONF_LOCAL/#"$HOME"/'~'}" >&2
  fi
  if is_true "$DRY_RUN" || ln -s -f "$OH_MY_TMUX_CLONE_PATH/.tmux-agent-status.sh" "$HOME/.tmux-agent-status.sh"; then
    printf '✅ Symlinked %s → %s\n' "~/.tmux-agent-status.sh" "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}/.tmux-agent-status.sh" >&2
  fi
  if is_true "$DRY_RUN" || ln -s -f "$OH_MY_TMUX_CLONE_PATH/.tmux-agent-popup.sh" "$HOME/.tmux-agent-popup.sh"; then
    printf '✅ Symlinked %s → %s\n' "~/.tmux-agent-popup.sh" "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}/.tmux-agent-popup.sh" >&2
  fi
  if is_true "$DRY_RUN" || ln -s -f "$OH_MY_TMUX_CLONE_PATH/agent-wrapper.sh" "$HOME/.local/bin/agent-wrapper.sh"; then
    printf '✅ Symlinked %s → %s\n' "~/.local/bin/agent-wrapper.sh" "${OH_MY_TMUX_CLONE_PATH/#"$HOME"/'~'}/agent-wrapper.sh" >&2
  fi

  tmux() {
    ${TMUX_PROGRAM:-tmux} ${TMUX_SOCKET:+-S "$TMUX_SOCKET"} "$@"
  }
  if ! is_true "$DRY_RUN" && [ -n "$TMUX" ]; then
    tmux set-environment -g TMUX_CONF "$TMUX_CONF"
    tmux set-environment -g TMUX_CONF_LOCAL "$TMUX_CONF_LOCAL"
    tmux source "$TMUX_CONF"
  fi

  if [ -n "$TMUX" ]; then
    printf '\n' >&2
    printf '⚠️  Installed Oh my tmux! while tmux was running...\n' >&2
    printf '→ Existing sessions have outdated environment variables\n' >&2
    printf '  • TMUX_CONF\n' >&2
    printf '  • TMUX_CONF_LOCAL\n' >&2
    printf '  • TMUX_PROGRAM\n' >&2
    printf '  • TMUX_SOCKET\n' >&2
    printf '→ Some other things may not work 🤷\n' >&2
  fi

  printf '\n' >&2
  printf '🎉 Oh my tmux! successfully installed 🎉\n' >&2

  # ── Agent Status Dashboard (optional) ──────────────────────────────
  install_agent_dashboard
}

install_agent_dashboard() {
  AGENT_DASHBOARD_REPO=${AGENT_DASHBOARD_REPO:-https://github.com/RPIFisherman/agents-status.git}
  AGENT_DASHBOARD_DIR="$HOME/projects/agents-status"

  printf '\n' >&2
  printf '🤖 Agent Status Dashboard\n' >&2
  printf '   A web dashboard for monitoring AI coding agents in tmux\n' >&2
  printf '   (Claude Code, Codex, Gemini CLI, OpenCode, OpenClaw)\n' >&2
  printf '\n' >&2

  while :; do
    printf '   Install Agent Status Dashboard? [Yes/No] > ' >&2
    read -r answer < /dev/tty 2>/dev/null || answer="no"
    case $(printf '%s\n' "$answer" | tr '[:upper:]' '[:lower:]') in
      y|yes) break ;;
      n|no)
        printf '   ⏭️  Skipped Agent Status Dashboard\n' >&2
        return 0
        ;;
    esac
  done

  printf '\n' >&2

  # Check Python + FastAPI
  if ! python3 --version >/dev/null 2>&1; then
    printf '   ❌ Python 3 not found, skipping dashboard install\n' >&2
    return 1
  fi
  if ! python3 -c "import fastapi, uvicorn" 2>/dev/null; then
    printf '   📦 Installing FastAPI + Uvicorn...\n' >&2
    if ! is_true "$DRY_RUN"; then
      pip install --quiet fastapi uvicorn 2>&1 | tail -1
    fi
  fi

  # Clone or update
  if [ -d "$AGENT_DASHBOARD_DIR/.git" ]; then
    printf '   ⬇️  Updating existing agents-status repo...\n' >&2
    if ! is_true "$DRY_RUN"; then
      git -C "$AGENT_DASHBOARD_DIR" pull --quiet origin master 2>/dev/null || true
    fi
  else
    printf '   ⬇️  Cloning agents-status repository...\n' >&2
    if ! is_true "$DRY_RUN"; then
      mkdir -p "$(dirname "$AGENT_DASHBOARD_DIR")"
      if ! git clone -q --single-branch "$AGENT_DASHBOARD_REPO" "$AGENT_DASHBOARD_DIR"; then
        printf '   ❌ Failed to clone agents-status\n' >&2
        return 1
      fi
    fi
  fi

  # Install agent configs
  AGENT_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-agent-status/agents"
  if ! is_true "$DRY_RUN"; then
    mkdir -p "$AGENT_CONF_DIR"
    for conf in "$AGENT_DASHBOARD_DIR"/configs/*.conf; do
      [ -f "$conf" ] || continue
      target="$AGENT_CONF_DIR/$(basename "$conf")"
      if [ ! -f "$target" ]; then
        cp "$conf" "$target"
        printf '   ✅ Installed %s\n' "$(basename "$conf")" >&2
      else
        printf '   ⏭️  %s already exists, skipping\n' "$(basename "$conf")" >&2
      fi
    done
  fi

  # Install Claude Code hooks (if Claude is available)
  if command -v claude >/dev/null 2>&1; then
    CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
    if ! is_true "$DRY_RUN"; then
      mkdir -p "$CLAUDE_HOOKS_DIR"
      cp "$AGENT_DASHBOARD_DIR/hooks/tmux-agent-state.sh" "$CLAUDE_HOOKS_DIR/"
      chmod +x "$CLAUDE_HOOKS_DIR/tmux-agent-state.sh"
      printf '   ✅ Installed Claude Code hook → %s\n' "~/.claude/hooks/tmux-agent-state.sh" >&2
    fi

    # Merge hooks into settings.json if not already present
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$CLAUDE_SETTINGS" ]; then
      if ! grep -q "tmux-agent-state" "$CLAUDE_SETTINGS" 2>/dev/null; then
        if command -v jq >/dev/null 2>&1; then
          if ! is_true "$DRY_RUN"; then
            jq -s '.[0] * .[1]' "$CLAUDE_SETTINGS" "$AGENT_DASHBOARD_DIR/configs/settings.fragment.json" \
              > "$CLAUDE_SETTINGS.new" 2>/dev/null \
              && mv "$CLAUDE_SETTINGS.new" "$CLAUDE_SETTINGS"
            printf '   ✅ Merged hooks into %s\n' "~/.claude/settings.json" >&2
          fi
        else
          printf '   ⚠️  jq not found — please manually merge hooks from configs/settings.fragment.json\n' >&2
        fi
      else
        printf '   ⏭️  Claude hooks already configured\n' >&2
      fi
    fi
  fi

  printf '\n' >&2
  printf '   🎉 Agent Status Dashboard installed!\n' >&2
  printf '   Start: cd %s && python3 server.py\n' "${AGENT_DASHBOARD_DIR/#"$HOME"/'~'}" >&2
  printf '   Open:  http://localhost:7890\n' >&2
  printf '\n' >&2
  printf '   Tip: Run in a dedicated tmux window for persistence:\n' >&2
  printf '     tmux new-window -n dashboard -c %s "exec python3 server.py"\n' "${AGENT_DASHBOARD_DIR/#"$HOME"/'~'}" >&2
}

if [ -p /dev/stdin ]; then
  printf '✋ STOP\n' >&2
  printf '   🤨 It looks like you are piping commands from the internet to your shell!\n' >&2
  printf "   🙏 Please take the time to review what's going to be executed...\n" >&2

  (
    printf '\n'

    self() {
      printf '# Oh my tmux!\n'
      printf '# 💛🩷💙🖤❤️🤍\n'
      printf '# https://github.com/RPIFisherman/.tmux\n'
      printf '\n'

      declare -f install
    }

    while :; do
      printf '   Do you want to review the content? [Yes/No/Cancel] > ' >&2
      read -r answer >&2
      case $(printf '%s\n' "$answer" | tr '[:upper:]' '[:lower:]') in
        y|yes)
          case "$(command -v bat)${VISUAL:-${EDITOR}}" in
            *bat*)
              self | LESS='' bat --paging always --file-name install.sh
              ;;
            *vim*) # vim, nvim, neovim ... compatible
              self | ${VISUAL:-${EDITOR}} -c ':set syntax=tmux' -R -
              ;;
            *)
              tput smcup
              clear
              self | LESS='-R' ${PAGER:-less}
              tput rmcup
              ;;
          esac
          break
          ;;
        n|no)
          break
          ;;
        c|cancel)
          printf '\n'
          printf '⛔️ Installation aborted...\n' >&2 && exit 1
          ;;
      esac
    done
  ) < /dev/tty || exit 1
  printf '\n'
fi

install
}
