#!/bin/bash
# claude-grid-tmux.sh [N] [DIR] [CILJ...]
# Otvara tmux sesiju s N panela (redovi po najviše 4, slažu se prema dolje),
# svi u radnom direktoriju DIR, svaki pokreće:
#   claude $CLAUDE_GRID_FLAGS
# Kad claude izađe, panel ostaje na login shellu (možeš ga ponovno pokrenuti).
#
# CILJ = određeni stol iz poola: wtN, ime grane ili putanja worktreeja.
# Takav panel se veže na TAJ stol (sp-open: zaključa, NE resetira granu) umjesto
# da uzme prvi slobodan (sp-claim). Ostali paneli claimaju kao i prije.
#   claude-grid-tmux.sh wt2                    # 1 panel, na wt2
#   claude-grid-tmux.sh feat/back-button       # 1 panel, na stolu te grane
#   claude-grid-tmux.sh wt2 wt7                # 2 panela, na wt2 i wt7
#   claude-grid-tmux.sh 4 wt2                  # 4 panela: wt2 + 3 auto-claim
#   claude-grid-tmux.sh --dry-run wt2 wt7      # samo ispiši plan, ne otvaraj
# Bez argumenata: kao prije (4 panela, svi auto-claim).

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# --- razdvoji argumente: broj / DIR / ciljevi -------------------------------
# Kompatibilnost: bare integer = N, mapa koja NIJE stol poola = DIR (staro
# ponašanje), sve ostalo = cilj (stol). Tako `claude-grid-tmux.sh 4 ~/projekti/nesto`
# radi kao i dosad.
is_pool_table() { # <dir> -> 0 ako je linked worktree enrolled repoa
	local d="$1" gd cd_
	"$HOME/.local/bin/sp-poolof" "$d" >/dev/null 2>&1 || return 1
	gd=$(cd "$d" && git rev-parse --absolute-git-dir 2>/dev/null) || return 1
	cd_=$(cd "$d" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd -P) || return 1
	[ "$gd" != "$cd_" ]
}

N=""; N_GIVEN=0; DIR_ARG=""; DRY=0; TARGETS=()
for a in "$@"; do
	case "$a" in
		--dry-run) DRY=1; continue ;;
		--) continue ;;
	esac
	if [ -z "${a//[0-9]/}" ] && [ -n "$a" ]; then N="$a"; N_GIVEN=1; continue; fi
	# Mapa: linked worktree enrolled repoa = stol (cilj); sve ostalo = DIR.
	# Kriterij za "linked worktree": git-dir != git-common-dir. Glavni repo ima
	# ta dva jednaka, pa `claude-grid-tmux.sh 4 ~/projekti/mojrepo` i dalje
	# znači "4 panela u tom repou", kao dosad.
	if [ -d "${a/#\~/$HOME}" ]; then
		d="${a/#\~/$HOME}"
		if is_pool_table "$d"; then TARGETS+=("$a"); else DIR_ARG="$a"; fi
		continue
	fi
	TARGETS+=("$a")           # wtN ili ime grane
done

# Ciljevi bez izričitog broja: točno toliko panela koliko je ciljeva — inače bi
# default (4) otvorio panele koji bespotrebno claimaju slobodne stolove.
if [ "$N_GIVEN" = 0 ] && [ "${#TARGETS[@]}" -gt 0 ]; then N="${#TARGETS[@]}"; fi
case "$N" in ''|*[!0-9]*) N=4 ;; esac
[ "${#TARGETS[@]}" -gt "$N" ] && N="${#TARGETS[@]}"
[ "$N" -lt 1 ] && N=1
[ "$N" -gt 16 ] && N=16

# --- radni direktorij: DIR arg -> "zadnji korišteni" (last) -> $HOME ---
LASTF="$HOME/.config/claudegrid/last"
DIR="${DIR_ARG:-}"
[ -z "$DIR" ] && [ -f "$LASTF" ] && DIR="$(cat "$LASTF")"
[ -z "$DIR" ] && DIR="$HOME"
# ~ ekspanzija i validacija (padni na $HOME ako mapa ne postoji)
case "$DIR" in "~"|"~/"*) DIR="$HOME${DIR#\~}" ;; esac
[ -d "$DIR" ] || DIR="$HOME"

# Postavke (opcionalno): ~/.config/claudegrid/config — CLAUDE_BIN, CLAUDE_GRID_FLAGS
[ -f "$HOME/.config/claudegrid/config" ] && . "$HOME/.config/claudegrid/config"
CLAUDE="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
FLAGS="${CLAUDE_GRID_FLAGS-}"   # npr. --dangerously-skip-permissions (vidi README)
SHELL_BIN="${SHELL:-/bin/bash}"

# --- session-pool (worktree-po-panelu): SAMO na enrolled repou (postoji pool marker) ---
# Svaki panel u startu cd-a u svoj slobodan worktree preko sp-claim; fallback na DIR ako zakaže.
# Ne-enrolled projekti -> POOL prazan -> obični paneli u DIR.
POOL="$("$HOME/.local/bin/sp-poolof" "$DIR" 2>/dev/null || true)"
# Ako DIR nije enrolled a zadan je cilj-putanja, izvedi pool iz njega.
if [ -z "$POOL" ] && [ "${#TARGETS[@]}" -gt 0 ] && [ -d "${TARGETS[0]/#\~/$HOME}" ]; then
	DIR="${TARGETS[0]/#\~/$HOME}"
	POOL="$("$HOME/.local/bin/sp-poolof" "$DIR" 2>/dev/null || true)"
fi
if [ -n "$POOL" ]; then
	RUN="cd \"\$('$HOME/.local/bin/sp-claim')\" 2>/dev/null || cd \"$DIR\"; \"$CLAUDE\" $FLAGS; exec \"$SHELL_BIN\" -l"
else
	RUN="\"$CLAUDE\" $FLAGS; exec \"$SHELL_BIN\" -l"
fi

# Naredba za panel vezan na ODREĐENI stol: sp-open (zaključa, ne resetira granu).
# Ako sp-open padne (nepostojeći stol), panel padne na DIR umjesto da nestane.
run_for_target() {
	printf 'cd "$(%s %s)" 2>/dev/null || cd %s; %s %s; exec %s -l' \
		"$(printf '%q' "$HOME/.local/bin/sp-open")" "$(printf '%q' "$1")" \
		"$(printf '%q' "$DIR")" "$(printf '%q' "$CLAUDE")" "$FLAGS" "$(printf '%q' "$SHELL_BIN")"
}

# Naredba po panelu: prvi paneli idu na zadane ciljeve, ostatak auto-claim.
pane_cmd() {
	local i="$1"
	if [ "$i" -lt "${#TARGETS[@]}" ]; then run_for_target "${TARGETS[$i]}"; else printf '%s' "$RUN"; fi
}

if [ "$DRY" = 1 ]; then
	echo "panela: $N"
	echo "DIR:    $DIR"
	echo "pool:   ${POOL:-(ne-enrolled)}"
	for ((c = 0; c < N; c++)); do
		if [ "$c" -lt "${#TARGETS[@]}" ]; then
			if p=$("$HOME/.local/bin/sp-open" --peek "${TARGETS[$c]}" 2>/dev/null); then
				echo "  panel $((c + 1)): CILJ ${TARGETS[$c]} -> $p"
			else
				echo "  panel $((c + 1)): CILJ ${TARGETS[$c]} -> NE POSTOJI (panel bi pao na $DIR)"
			fi
		else
			echo "  panel $((c + 1)): auto-claim (sp-claim)"
		fi
	done
	exit 0
fi

SESSION="claudegrid-$$"

# --- raspored: redovi široki najviše 4 panela, slažu se prema dolje ---
# Napravi N panela (tijekom gradnje drži ih u 'tiled' da uvijek ima mjesta),
# pa prepusti rasporedjivanje jedinom izvoru istine: claude-grid-relayout.sh.
tmux new-session -d -s "$SESSION" -c "$DIR" "$(pane_cmd 0)"
for ((c = 1; c < N; c++)); do
	tmux split-window -t "$SESSION" -c "$DIR" "$(pane_cmd "$c")" >/dev/null
	tmux select-layout -t "$SESSION" tiled >/dev/null
done
WIN=$(tmux display-message -t "$SESSION" -p '#{window_id}')
"$HOME/.local/bin/claude-grid-relayout.sh" "$WIN"

# Zapamti "korijen grida" da prefix+n (claude-grid-add.sh) otvara novi panel ovdje.
tmux set-option -t "$SESSION" @grid_dir "$DIR" >/dev/null 2>&1
# Zapamti pool (ako enrolled) -> prefix+n claima novi worktree umjesto dijeljenog @grid_dir.
[ -n "$POOL" ] && tmux set-option -t "$SESSION" @grid_pool "$POOL" >/dev/null 2>&1

tmux set-option -t "$SESSION" mouse on >/dev/null 2>&1
# Border stilovi + naslovna traka aktivnog panela se nasljeđuju iz ~/.tmux.conf
# (aktivni panel = ▶ SESSION N ◀ traka na vrhu).

# Hotkeyevi prefix+j (spoji sesije, fzf) i prefix+n (nova sesija) sada su trajno
# u ~/.tmux.conf -> rade neovisno o tome je li grid pokrenut ovom skriptom.

# --- glatkije scrollanje: koliko redaka po jednom pomaku kotacica ---
# Manji broj = sitniji korak = manje "preskakanja". Probaj 1, 2, 3...
SCROLL_LINES=1
# Ako aplikacija u panelu sama hvata mis (npr. claude TUI) -> proslijedi joj scroll.
# Inace udi u copy-mode i scrollaj SCROLL_LINES redaka.
tmux bind-key -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" \
	"send-keys -M" \
	"if-shell -F -t = '#{pane_in_mode}' 'send-keys -X -N ${SCROLL_LINES} scroll-up' 'copy-mode -e; send-keys -X -N ${SCROLL_LINES} scroll-up'" >/dev/null 2>&1
tmux bind-key -n WheelDownPane if-shell -F -t = "#{mouse_any_flag}" \
	"send-keys -M" \
	"if-shell -F -t = '#{pane_in_mode}' 'send-keys -X -N ${SCROLL_LINES} scroll-down' 'send-keys -M'" >/dev/null 2>&1

exec tmux attach-session -t "$SESSION"
