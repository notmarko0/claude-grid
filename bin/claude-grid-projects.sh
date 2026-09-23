#!/bin/bash
# claude-grid-projects.sh — čitač liste favorita za ClaudeGrid.app
# Config: ~/.config/claudegrid/projects  (redovi "Labela = /putanja"; # i prazni se ignoriraju)
#
# Podnaredbe:
#   --labels            ispiši labele (po jedna u retku); ako config fali -> "home"
#   --path  "Labela"    ispiši putanju za zadanu labelu (~ ekspanzija)
#   --label "putanja"   ispiši labelu koja odgovara zadanoj putanji (reverse lookup)

CFG="$HOME/.config/claudegrid/projects"

# Ispiši "labela<TAB>putanja" za svaki valjani redak. Trimma razmake oko labele/putanje.
_rows() {
	[ -f "$CFG" ] || return 0
	# makni komentare i prazne, razdvoji na prvom '='
	sed -e 's/#.*$//' "$CFG" 2>/dev/null | while IFS= read -r line; do
		case "$line" in *=*) : ;; *) continue ;; esac
		label="${line%%=*}"; path="${line#*=}"
		# trim vodeći/prateći razmak
		label="$(printf '%s' "$label" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		path="$(printf '%s' "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		[ -z "$label" ] && continue
		case "$path" in "~"|"~/"*) path="$HOME${path#\~}" ;; esac
		printf '%s\t%s\n' "$label" "$path"
	done
}

case "${1:-}" in
	--labels)
		out="$(_rows | cut -f1)"
		[ -z "$out" ] && out="home"
		printf '%s\n' "$out"
		;;
	--path)
		want="$2"
		_rows | awk -F'\t' -v w="$want" '$1==w {print $2; exit}'
		;;
	--label)
		want="$2"
		_rows | awk -F'\t' -v w="$want" '$2==w {print $1; exit}'
		;;
	*)
		echo "korištenje: $0 --labels | --path 'Labela' | --label '/putanja'" >&2
		exit 1
		;;
esac
