#!/bin/bash
# claude-grid-add.sh [WINDOW_ID] [CILJ]
# Otvori NOVU Claude sesiju kao panel u zadanom (ili trenutnom) prozoru,
# pa presloži prozor u ClaudeGrid raspored (redovi po najviše 4).
# Veže se na: prefix + n  (vidi ~/.tmux.conf)
#
# CILJ (opcionalno) = određeni stol: wtN, ime grane ili putanja worktreeja.
# Bez cilja: panel uzme prvi slobodan stol (sp-claim), kao dosad.
# S ciljem:  panel ide na TAJ stol (sp-open — zaključa, NE resetira granu).
# Birač na prefix + o (claude-grid-pick.sh) poziva ovu skriptu s ciljem.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

WIN="${1:-}"
case "$WIN" in ''|*'#'*|*'{'*) WIN=$(tmux display-message -p '#{window_id}') ;; esac
TARGET="${2:-}"

# Postavke (opcionalno): ~/.config/claudegrid/config — CLAUDE_BIN, CLAUDE_GRID_FLAGS
[ -f "$HOME/.config/claudegrid/config" ] && . "$HOME/.config/claudegrid/config"
CLAUDE="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
FLAGS="${CLAUDE_GRID_FLAGS-}"   # npr. --dangerously-skip-permissions (vidi README)
SHELL_BIN="${SHELL:-/bin/bash}"
RUN="\"$CLAUDE\" $FLAGS; exec \"$SHELL_BIN\" -l"

# --- radni direktorij novog panela: "korijen grida" (@grid_dir) -> path
#     trenutnog panela -> $HOME. Tako novi panel padne u isti projekt kao grid. ---
SES=$(tmux display-message -t "$WIN" -p '#{session_id}')
DIR=$(tmux show-options -qv -t "$SES" @grid_dir 2>/dev/null)
[ -z "$DIR" ] && DIR=$(tmux display-message -t "$WIN" -p '#{pane_current_path}')
[ -d "$DIR" ] || DIR="$HOME"

# --- session-pool: ako je grid enrolled (@grid_pool), novi panel claima svoj worktree ---
POOL=$(tmux show-options -qv -t "$SES" @grid_pool 2>/dev/null)
if [ -n "$TARGET" ]; then
	# Izričit cilj radi i kad @grid_pool nije postavljen (npr. grid pokrenut
	# prije ove promjene) — sp-open sam razrješava pool iz ciljne mape.
	RUN="cd \"\$('$HOME/.local/bin/sp-open' $(printf '%q' "$TARGET"))\" 2>/dev/null || cd \"$DIR\"; \"$CLAUDE\" $FLAGS; exec \"$SHELL_BIN\" -l"
elif [ -n "$POOL" ]; then
	RUN="cd \"\$('$HOME/.local/bin/sp-claim')\" 2>/dev/null || cd \"$DIR\"; \"$CLAUDE\" $FLAGS; exec \"$SHELL_BIN\" -l"
fi

tmux split-window -h -t "$WIN" -c "$DIR" "$RUN" >/dev/null 2>&1
"$HOME/.local/bin/claude-grid-relayout.sh" "$WIN"
