#!/bin/bash
# claude-grid-pick.sh [WINDOW_ID]
# fzf birač stolova: odaberi worktree i otvori ga kao novi Claude panel.
# Veže se na: prefix + o  (vidi ~/.tmux.conf), u display-popup.
#
# Zašto postoji: prefix+n uzme PRVI SLOBODAN stol, što je dobro za novi feature,
# ali beskorisno kad se želiš vratiti na određenu granu. Ovo je taj drugi slučaj.
#
# Pomoćni način:
#   claude-grid-pick.sh --gen [DIR]   # ispiši kandidate (cilj<TAB>opis)

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
TAB=$'\t'

pool_root() { # -> putanja glavnog repoa poola (iz @grid_dir ili cwd)
	local d="$1"
	[ -d "$d" ] || d="$PWD"
	(cd "$d" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && dirname "$(pwd -P)")
}

gen() {
	local root; root=$(pool_root "${1:-$PWD}")
	[ -n "$root" ] || return 1
	local integ lbl
	lbl=$("$HOME/.local/bin/sp-poolof" "$root" 2>/dev/null) && integ=$(sed -n 's/^integ=//p' "$HOME/.config/claudegrid/pools/$lbl" | head -n1)
	integ="${integ:-main}"
	git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r p; do
		case "$(basename "$p")" in *-wt[0-9]*) ;; *) continue ;; esac
		local br dirty ah be when wt
		wt=$(basename "$p"); wt="wt${wt##*-wt}"
		br=$(git -C "$p" symbolic-ref --short -q HEAD 2>/dev/null || echo "(detached)")
		dirty=$(git -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
		[ "$dirty" = 0 ] && dirty="       " || dirty="DIRTY  "
		ah=$(git -C "$p" rev-list --count "$integ..HEAD" 2>/dev/null || echo 0)
		be=$(git -C "$p" rev-list --count "HEAD..$integ" 2>/dev/null || echo 0)
		when=$(git -C "$p" log -1 --format=%cr 2>/dev/null)
		printf '%s\t%-6s %-30s %s +%-4s -%-4s %s\n' "$p" "$wt" "$br" "$dirty" "$ah" "$be" "$when"
	done
}

case "${1:-}" in
	--gen) shift; gen "${1:-$PWD}"; exit 0 ;;
esac

WIN="${1:-}"
case "$WIN" in ''|*'#'*|*'{'*) WIN=$(tmux display-message -p '#{window_id}' 2>/dev/null) ;; esac

SES=$(tmux display-message -t "$WIN" -p '#{session_id}' 2>/dev/null)
DIR=$(tmux show-options -qv -t "$SES" @grid_dir 2>/dev/null)
[ -d "$DIR" ] || DIR=$(tmux display-message -t "$WIN" -p '#{pane_current_path}' 2>/dev/null)
[ -d "$DIR" ] || DIR="$PWD"

CHOICE=$(gen "$DIR" | fzf --with-nth=2.. --delimiter="$TAB" \
	--prompt="stol > " --height=100% --reverse \
	--header="odaberi worktree za novi Claude panel (Esc = odustani)" |
	cut -f1)

[ -n "$CHOICE" ] || exit 0
"$HOME/.local/bin/claude-grid-add.sh" "$WIN" "$CHOICE"
