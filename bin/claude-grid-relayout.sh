#!/bin/bash
# claude-grid-relayout.sh [WINDOW_ID]
# Presloži panele zadanog (ili trenutnog) prozora u ClaudeGrid raspored:
#   redovi široki NAJVIŠE 4 panela; kad ih je više, slaže se još redova prema dolje,
#   ravnomjerno (puniji redovi gore). Npr. 3->[3], 4->[4], 6->[3,3], 8->[4,4],
#   10->[4,3,3], 16->[4,4,4,4]. Čuva žive procese (samo geometrija).

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

WIN="${1:-}"
case "$WIN" in ''|*'#'*|*'{'*) WIN=$(tmux display-message -p '#{window_id}') ;; esac

# pane_id-evi poredani lijevo->desno, pa po vrhu (bez mapfile -> radi i na bash 3.2)
ids=()
while IFS= read -r _p; do ids+=("$_p"); done \
	< <(tmux list-panes -t "$WIN" -F '#{pane_left} #{pane_top} #{pane_id}' | sort -n -k1 -k2 | awk '{print $3}')
N=${#ids[@]}

# 1-4 panela -> sve u jedan red
if [ "$N" -le 4 ]; then
	tmux select-layout -t "$WIN" even-horizontal >/dev/null 2>&1
	exit 0
fi

# 5+ panela -> višeredni grid (max 4 po redu) preko layout stringa
W=$(tmux display-message -t "$WIN" -p '#{window_width}')
H=$(tmux display-message -t "$WIN" -p '#{window_height}')

# --- tmux layout checksum (layout_checksum iz tmuxa) ---
checksum() {
	local s="$1" c=0 i ch b L=${#1}
	for ((i = 0; i < L; i++)); do
		ch="${s:i:1}"; printf -v b '%d' "'$ch"
		c=$(( c / 2 + (c % 2) * 32768 ))
		c=$(( (c + b) % 65536 ))
	done
	printf '%04x' "$c"
}

# --- složi body layout stringa: R redova (max 4 stupca), vertikalno složenih ---
build_body() {
	local R=$(( (N + 3) / 4 ))               # ceil(N/4) = broj redova
	local rbase=$(( N / R )) rextra=$(( N % R ))   # panela po redu (puniji gore)
	local hbase=$(( (H - (R - 1)) / R )) hrem=$(( (H - (R - 1)) % R ))  # visine redova
	local rows="" y=0 idx=0 r c rc rh usableW cwb cwr x cw leaves leaf rowcell
	for ((r = 0; r < R; r++)); do
		rc=$rbase; [ "$r" -lt "$rextra" ] && rc=$((rbase + 1))   # stupaca u ovom redu
		rh=$hbase; [ "$r" -lt "$hrem" ] && rh=$((hbase + 1))     # visina ovog reda
		if [ "$rc" -eq 1 ]; then
			rowcell=$(printf '%dx%d,0,%d,%s' "$W" "$rh" "$y" "${ids[idx]#%}")
			idx=$((idx + 1))
		else
			cwb=$(( (W - (rc - 1)) / rc )); cwr=$(( (W - (rc - 1)) % rc ))
			leaves=""; x=0
			for ((c = 0; c < rc; c++)); do
				cw=$cwb; [ "$c" -lt "$cwr" ] && cw=$((cwb + 1))
				leaf=$(printf '%dx%d,%d,%d,%s' "$cw" "$rh" "$x" "$y" "${ids[idx]#%}")
				idx=$((idx + 1))
				[ -n "$leaves" ] && leaves="$leaves,$leaf" || leaves="$leaf"
				x=$((x + cw + 1))
			done
			rowcell=$(printf '%dx%d,0,%d{%s}' "$W" "$rh" "$y" "$leaves")
		fi
		[ -n "$rows" ] && rows="$rows,$rowcell" || rows="$rowcell"
		y=$((y + rh + 1))
	done
	printf '%dx%d,0,0[%s]' "$W" "$H" "$rows"
}

body="$(build_body)"
layout="$(checksum "$body"),$body"

# Primarno: točan grid preko layout stringa. Fallback: tiled (uvijek valjan).
tmux select-layout -t "$WIN" "$layout" >/dev/null 2>&1 \
	|| tmux select-layout -t "$WIN" tiled >/dev/null 2>&1
