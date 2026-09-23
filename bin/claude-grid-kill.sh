#!/bin/bash
# claude-grid-kill.sh [PANE_ID] [WINDOW_ID]
# Ugasi zadani (ili trenutni) panel pa presloži prozor u ClaudeGrid raspored.
# Veže se na: prefix + x  (vidi ~/.tmux.conf)

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

PANE="$1"; WIN="$2"
case "$PANE" in ''|*'#'*|*'{'*) PANE=$(tmux display-message -p '#{pane_id}') ;; esac
case "$WIN" in ''|*'#'*|*'{'*) WIN=$(tmux display-message -p '#{window_id}') ;; esac

# --- session-pool: ako je panel u pooled worktreeju, oslobodi "stol" prije gašenja ---
# sp-release sam odbija ako je rad nemergean/dirty -> tada NE gubimo ništa, wt ostaje zauzet.
PANE_DIR=$(tmux display-message -p -t "$PANE" '#{pane_current_path}' 2>/dev/null || echo "")
if [ -n "$PANE_DIR" ] && "$HOME/.local/bin/sp-poolof" "$PANE_DIR" >/dev/null 2>&1; then
	( cd "$PANE_DIR" && "$HOME/.local/bin/sp-release" >/dev/null 2>&1 ) || \
		tmux display-message "wt ostaje zauzet (nemergeano/dirty) — ručno: sp-release --force"
fi

tmux kill-pane -t "$PANE" 2>/dev/null

# ako prozor još postoji (nije ugašen zadnji panel), presloži ga
if tmux list-panes -t "$WIN" >/dev/null 2>&1; then
	"$HOME/.local/bin/claude-grid-relayout.sh" "$WIN"
fi
