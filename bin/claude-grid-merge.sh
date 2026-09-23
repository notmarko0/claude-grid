#!/bin/bash
# claude-grid-merge.sh [TARGET_SESSION_ID] [TARGET_WINDOW_ID]
#
# Spaja (join) žive Claude panele iz DRUGIH tmux sesija/prozora u trenutni
# (ciljani) prozor, BEZ gašenja/restartanja (kontekst ostaje). Bira se fzf-om
# uz pregled uživo (zadnji ekran svake sesije) i raspored se posloži u grid.
#
# Poziva se:
#   1) Direktno u panelu:        claude-grid-merge.sh
#   2) Iz tmux hotkeya (prefix+j): display-popup -E "claude-grid-merge.sh"
#
# Pomoćni načini:
#   claude-grid-merge.sh --gen <SESSION_ID>   # ispiši kandidate (pid<TAB>label), za fzf reload
#   claude-grid-merge.sh --list               # ljudski čitljiv popis (test)

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
TAB=$'\t'

# --- enumeracija kandidata: svi paneli koji NISU u ciljanoj sesiji ---
# Izlaz: pane_id <TAB> "[session]  <cwd-folder>  ·  <command>"
gen_candidates() {
	local tgt="$1"
	tmux list-panes -a -F "#{pane_id}${TAB}#{session_id}${TAB}#{session_name}${TAB}#{pane_current_path}${TAB}#{pane_current_command}" \
		| awk -F"$TAB" -v tgt="$tgt" 'BEGIN{OFS="\t"} $2!=tgt {
			n=split($4,a,"/"); cwd=a[n]; if(cwd=="")cwd=$4;
			print $1, "["$3"]  " cwd "  \xc2\xb7  " $5
		}'
}

# --- skriveni način za fzf reload ---
if [ "$1" = "--gen" ]; then
	gen_candidates "$2"
	exit 0
fi

LIST_ONLY=0
if [ "$1" = "--list" ]; then LIST_ONLY=1; shift; fi

# --- ciljani prozor (gdje spajamo) ---
TARGET_SES="$1"
TARGET_WIN="$2"
case "$TARGET_SES" in *'#'*|*'{'*) TARGET_SES="" ;; esac
case "$TARGET_WIN" in *'#'*|*'{'*) TARGET_WIN="" ;; esac
[ -z "$TARGET_SES" ] && TARGET_SES=$(tmux display-message -p '#{session_id}')
[ -z "$TARGET_WIN" ] && TARGET_WIN=$(tmux display-message -t "$TARGET_SES" -p '#{window_id}')
export TARGET_SES TARGET_WIN

# --- ima li uopće kandidata? ---
if [ -z "$(gen_candidates "$TARGET_SES")" ]; then
	echo "Nema Claude sesija u drugim prozorima za spojiti."
	[ "$LIST_ONLY" -eq 1 ] && exit 0
	echo "(Enter za izlaz)"; read -r _; exit 0
fi

# --- test/ne-interaktivni popis ---
if [ "$LIST_ONLY" -eq 1 ]; then
	echo "=== Claude sesije iz DRUGIH prozora ==="
	gen_candidates "$TARGET_SES" | awk -F"$TAB" '{printf "  %s\n", $2}'
	exit 0
fi

# --- fzf picker s pregledom uživo ---
if ! command -v fzf >/dev/null 2>&1; then
	echo "fzf nije pronađen u PATH-u. Instaliraj ga (Ubuntu/WSL: sudo apt install fzf · Mac: brew install fzf) ili koristi stari način."
	echo "(Enter za izlaz)"; read -r _; exit 1
fi

SELF="$HOME/.local/bin/claude-grid-merge.sh"
sel=$(gen_candidates "$TARGET_SES" | fzf \
	--multi --ansi \
	--delimiter="$TAB" --with-nth=2.. \
	--prompt='spoji> ' \
	--header=$'TAB = označi više • Enter = spoji • Ctrl-X = ugasi taj panel • Esc = odustani' \
	--preview="tmux capture-pane -pe -t {1}" \
	--preview-window='right,60%,wrap' \
	--bind="ctrl-x:execute-silent(tmux kill-pane -t {1})+reload($SELF --gen $TARGET_SES)")

[ -z "$sel" ] && { echo "Odustao."; exit 0; }

# --- spoji odabrane panele u ciljani prozor ---
cnt=0
while IFS="$TAB" read -r pid label; do
	[ -z "$pid" ] && continue
	if tmux join-pane -h -d -s "$pid" -t "$TARGET_WIN" 2>/dev/null; then
		echo "Spojeno: $label"
		cnt=$((cnt + 1))
	else
		echo "Neuspjelo (možda već premješteno): $label"
	fi
done <<< "$sel"

# --- presloži ciljani prozor u ClaudeGrid raspored ---
"$HOME/.local/bin/claude-grid-relayout.sh" "$TARGET_WIN"

TOTAL=$(tmux list-panes -t "$TARGET_WIN" | wc -l | tr -d ' ')
echo "Gotovo. Spojeno $cnt; prozor sada ima $TOTAL panela."
sleep 0.4
