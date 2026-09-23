#!/bin/bash
# install.sh — instalira Claude Grid za trenutnog korisnika (bez sudo).
#
#   ./install.sh              instaliraj / nadogradi (sigurno za ponavljanje)
#   ./install.sh --check      samo provjeri preduvjete, ništa ne mijenjaj
#   ./install.sh --uninstall  makni skripte i source-liniju (config ostaje)
#
# Što radi:
#   1) kopira bin/* u ~/.local/bin (postojeći drugačiji fajl -> backup .bak)
#   2) ~/.config/claudegrid/: tmux.conf (uvijek svjež), projects + config (samo ako ne postoje)
#   3) u ~/.tmux.conf doda:  source-file ~/.config/claudegrid/tmux.conf  (jednom)
#   4) pobrine se da je ~/.local/bin u PATH-u (~/.bashrc / ~/.zshrc)
#   5) na WSL-u: doda "Claude Grid" profil u Windows Terminal (fragment)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
CFG="$HOME/.config/claudegrid"
SRC_LINE='source-file ~/.config/claudegrid/tmux.conf'
MODE="${1:-install}"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# ---------------------------------------------------------------- preduvjeti
check() {
	local missing=0 v
	echo "Preduvjeti:"
	for c in bash git tmux fzf python3; do
		if command -v "$c" >/dev/null 2>&1; then ok "$c"; else bad "$c — nedostaje"; missing=1; fi
	done
	if command -v tmux >/dev/null 2>&1; then
		v=$(tmux -V | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1\2/')
		[ "${v:-0}" -ge 32 ] 2>/dev/null && ok "tmux $(tmux -V | cut -d' ' -f2) (treba 3.2+)" \
			|| { bad "tmux je prestar ($(tmux -V)); treba 3.2+"; missing=1; }
	fi
	if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then ok "claude (Claude Code)"
	else warn "claude nije nađen — instaliraj Claude Code U OVOM sustavu (vidi README)"; fi
	case "$HERE" in /mnt/[a-z]/*) warn "repo je na Windows disku ($HERE) — radi, ali je sporo; bolje ~/..." ;; esac
	if [ "$missing" = 1 ]; then
		echo
		echo "Instaliraj što fali. Ubuntu/WSL:  sudo apt update && sudo apt install -y tmux fzf git python3"
		echo "                     Mac:         brew install tmux fzf git python"
	fi
	return "$missing"
}

# ---------------------------------------------------------------- Windows Terminal profil
wt_fragment() {
	is_wsl || return 0
	command -v cmd.exe >/dev/null 2>&1 || { warn "cmd.exe nije dostupan iz WSL-a — preskačem Windows Terminal profil"; return 0; }
	local lad dir distro
	lad=$(cd /mnt/c 2>/dev/null && cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')
	[ -n "$lad" ] && [ "$lad" != "%LOCALAPPDATA%" ] || { warn "ne mogu naći %LOCALAPPDATA% — preskačem profil"; return 0; }
	dir="$(wslpath -u "$lad")/Microsoft/Windows Terminal/Fragments/ClaudeGrid"
	distro="${WSL_DISTRO_NAME:-Ubuntu}"
	if [ "$1" = remove ]; then rm -rf "$dir" && ok "maknut Windows Terminal profil"; return 0; fi
	mkdir -p "$dir" || { warn "ne mogu pisati u $dir"; return 0; }
	cat >"$dir/claudegrid.json" <<EOF
{
  "profiles": [
    {
      "name": "Claude Grid",
      "commandline": "wsl.exe -d $distro --cd ~ -- bash -lc \"$BIN/claude-grid\"",
      "icon": "🧩",
      "hidden": false
    }
  ]
}
EOF
	ok "Windows Terminal: profil \"Claude Grid\" (strelica ˅ pokraj + u Windows Terminalu)"
	sed "s/^set DISTRO=.*/set DISTRO=$distro/" "$HERE/windows/ClaudeGrid.bat" | sed 's/$/\r/' >"$HERE/windows/ClaudeGrid.local.bat"
	ok "dvoklik pokretač: $(wslpath -w "$HERE/windows/ClaudeGrid.local.bat" 2>/dev/null) (kopiraj na Desktop po želji)"
}

# ---------------------------------------------------------------- PATH
ensure_path() {
	case ":$PATH:" in *":$BIN:"*) ok "~/.local/bin je u PATH-u"; return ;; esac
	local rc line='export PATH="$HOME/.local/bin:$PATH"'
	for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
		[ -f "$rc" ] || continue
		grep -qF '.local/bin' "$rc" || { printf '\n# Claude Grid\n%s\n' "$line" >>"$rc"; ok "PATH dodan u $rc"; }
	done
	warn "otvori novi terminal (ili: source ~/.bashrc) da PATH proradi"
}

# ---------------------------------------------------------------- uninstall
if [ "$MODE" = "--uninstall" ]; then
	echo "Uklanjam Claude Grid…"
	for f in "$HERE"/bin/*; do rm -f "$BIN/$(basename "$f")"; done; ok "skripte maknute iz $BIN"
	if [ -f "$HOME/.tmux.conf" ]; then
		grep -vxF "$SRC_LINE" "$HOME/.tmux.conf" >"$HOME/.tmux.conf.tmp" && mv "$HOME/.tmux.conf.tmp" "$HOME/.tmux.conf"
		ok "source-linija maknuta iz ~/.tmux.conf"
	fi
	wt_fragment remove
	echo "Config ($CFG) je ostavljen; obriši ga ručno ako želiš."
	exit 0
fi

if [ "$MODE" = "--check" ]; then check; exit $?; fi

# ---------------------------------------------------------------- install
echo "Claude Grid → $BIN"
check || { echo; echo "Instalacija nastavlja, ali grid neće raditi dok ne instaliraš što fali."; }
echo
echo "Instalacija:"
mkdir -p "$BIN" "$CFG/pools" "$CFG/locks"

n=0
for f in "$HERE"/bin/*; do
	dst="$BIN/$(basename "$f")"
	if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then
		grep -q 'claude-grid\|sp-common' "$dst" 2>/dev/null || cp "$dst" "$dst.bak"
	fi
	cp "$f" "$dst" && chmod +x "$dst" && n=$((n + 1))
done
ok "$n skripti u $BIN"

cp "$HERE/config/tmux.conf" "$CFG/tmux.conf" && ok "tmux postavke → $CFG/tmux.conf"
[ -f "$CFG/projects" ] || { cp "$HERE/config/projects.example" "$CFG/projects"; ok "favoriti → $CFG/projects (uredi po želji)"; }
[ -f "$CFG/config" ]   || { cp "$HERE/config/config.example" "$CFG/config"; ok "postavke → $CFG/config"; }

touch "$HOME/.tmux.conf"
if grep -qxF "$SRC_LINE" "$HOME/.tmux.conf"; then ok "~/.tmux.conf već učitava Claude Grid"
else printf '\n# Claude Grid\n%s\n' "$SRC_LINE" >>"$HOME/.tmux.conf"; ok "~/.tmux.conf → dodan source-file"; fi
# ako tmux server već radi, primijeni odmah
tmux info >/dev/null 2>&1 && tmux source-file "$CFG/tmux.conf" 2>/dev/null && ok "primijenjeno na živi tmux server"

ensure_path
wt_fragment add

echo
echo "Gotovo. Pokreni:  claude-grid        (pita broj panela i projekt)"
echo "        ili:      claude-grid-tmux.sh 4 ~/projekti/nesto"
echo "Test:             ./tests/selftest.sh"
