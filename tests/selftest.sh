#!/bin/bash
# tests/selftest.sh — provjera da Claude Grid radi na ovom sustavu.
#
# Potpuno izoliran: lažni $HOME u privremenoj mapi, vlastiti tmux server
# (TMUX_TMPDIR), lažni "claude" (samo spava). Ne dira tvoj pravi config,
# tvoje tmux sesije ni tvoje repoe. Na kraju sve pobriše.
#
#   ./tests/selftest.sh        -> na kraju "SVE PROŠLO (N/N)" ili popis padova

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# /tmp (ne $TMPDIR): tmux socket putanja mora biti kratka (Mac limit ~104 znaka)
T="$(cd "$(mktemp -d /tmp/cgtest.XXXXXX)" && pwd -P)"
export HOME="$T/home" TMUX_TMPDIR="$T/tmux"
unset TMUX TMUX_PANE
mkdir -p "$HOME" "$TMUX_TMPDIR"
export PATH="$HOME/.local/bin:$PATH"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL="$T/gitconfig"; printf '[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"

PASS=0; FAIL=0; FAILS=""
t() { # <opis> <naredba...>
	local d="$1"; shift
	if "$@" >"$T/out" 2>&1; then PASS=$((PASS + 1)); printf '  ✓ %s\n' "$d"
	else FAIL=$((FAIL + 1)); FAILS="$FAILS\n  ✗ $d"; printf '  ✗ %s\n' "$d"; sed 's/^/      /' "$T/out" | head -8; fi
}
cleanup() { tmux kill-server >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT

echo "== instalacija (u lažni HOME) =="
t "install.sh prolazi" bash "$REPO/install.sh"
t "skripte su u ~/.local/bin i izvršne" test -x "$HOME/.local/bin/claude-grid-tmux.sh" -a -x "$HOME/.local/bin/sp-claim" -a -x "$HOME/.local/bin/claude-grid"
t "~/.tmux.conf učitava Claude Grid" grep -qx 'source-file ~/.config/claudegrid/tmux.conf' "$HOME/.tmux.conf"
t "install je idempotentan (2. put ne duplicira)" bash -c "bash '$REPO/install.sh' >/dev/null 2>&1; [ \$(grep -c claudegrid/tmux.conf '$HOME/.tmux.conf') = 1 ]"

# lažni claude: samo spava (da paneli ostanu živi)
mkdir -p "$T/fake"; printf '#!/bin/sh\nexec sleep 600\n' >"$T/fake/claude"; chmod +x "$T/fake/claude"
printf 'CLAUDE_BIN="%s"\nCLAUDE_GRID_FLAGS=""\n' "$T/fake/claude" >"$HOME/.config/claudegrid/config"

echo "== worktree pool =="
P="$T/proj"; mkdir -p "$P/app"; cd "$P/app" || exit 1
git init -q && echo hi >README && git add . && git commit -qm init
t "sp-setup napravi pool" sp-setup
t "5 stolova (app-wt1..5)" bash -c "[ \$(ls -d '$P'/app-wt* | wc -l | tr -d ' ') = 5 ]"
t "pre-commit hook blokira commit na main" bash -c "cd '$P/app' && echo x>>README && git commit -qam no; r=\$?; git checkout -q README; [ \$r != 0 ]"
t "sp-poolof prepoznaje repo" bash -c "[ \"\$(sp-poolof '$P/app')\" = app ]"

W=$(sp-claim); echo "     claim -> $W"
t "sp-claim vrati stol" test -d "$W"
t "stol je na scratch/wtN" bash -c "git -C '$W' symbolic-ref --short HEAD | grep -q '^scratch/wt'"
cd "$W" || exit 1
t "sp-name -> feat/test-tema" bash -c "[ \"\$(sp-name test-tema)\" = feat/test-tema ]"
t "lock meta ima slug (prenosivi sed)" bash -c "grep -qx slug=test-tema '$HOME'/.config/claudegrid/locks/app/wt*/meta"
t "sp-status ispisuje ZAUZET(test-tema)" bash -c "sp-status | grep -q 'ZAUZET(test-tema)'"
echo change >>README; git commit -qam "rad"
t "sp-release ODBIJE nemergeano" bash -c "cd '$W' && ! sp-release"
git -C "$P/app" merge -q --ff-only feat/test-tema
t "nakon ff merga sp-release prolazi" sp-release
t "grana feat/test-tema obrisana" bash -c "! git -C '$P/app' show-ref --verify --quiet refs/heads/feat/test-tema"
t "sp-open wt2 (bez reseta) vrati putanju" bash -c "[ \"\$(cd '$P/app' && sp-open wt2)\" = '$P/app-wt2' ]"
t "sp-wip radi (GNU/BSD stat)" bash -c "cd '$P/app' && sp-wip | grep -q STOLOVI"
t "grid --dry-run s ciljem wt2" bash -c "claude-grid-tmux.sh --dry-run 3 wt2 '$P/app' | grep -q 'CILJ wt2'"

echo "== tmux grid (izolirani server) =="
t "tmux server se diže s našim tmux.conf" tmux new-session -d -s cgt -x 200 -y 60 -c "$P/app" "sleep 600"
t "tmux.conf: prečaci n/o/j/x postoje" bash -c "k=\$(tmux list-keys -T prefix); for c in n o j x; do echo \"\$k\" | grep -qE \"prefix +\$c \" || exit 1; done"
WIN=$(tmux display-message -t cgt -p '#{window_id}')
tmux set-option -t cgt @grid_dir "$P/app"
for i in 1 2 3 4; do "$HOME/.local/bin/claude-grid-add.sh" "$WIN"; done
t "prefix+n (add) doda panele -> 5" bash -c "[ \$(tmux list-panes -t '$WIN' | wc -l | tr -d ' ') = 5 ]"
t "relayout 5 panela -> 2 reda [3,2]" bash -c "[ \$(tmux list-panes -t '$WIN' -F '#{pane_top}' | sort -u | wc -l | tr -d ' ') = 2 ]"
for i in 1 2 3 4 5; do "$HOME/.local/bin/claude-grid-add.sh" "$WIN"; done
t "10 panela -> 3 reda [4,3,3]" bash -c "[ \$(tmux list-panes -t '$WIN' -F '#{pane_top}' | sort -u | wc -l | tr -d ' ') = 3 ]"
t "10 panela -> najviše 4 u redu" bash -c "[ \$(tmux list-panes -t '$WIN' -F '#{pane_top}' | sort | uniq -c | awk '{print \$1}' | sort -n | tail -1) = 4 ]"
P1=$(tmux list-panes -t "$WIN" -F '#{pane_id}' | tail -1)
"$HOME/.local/bin/claude-grid-kill.sh" "$P1" "$WIN"
t "prefix+x (kill) -> 9 panela" bash -c "[ \$(tmux list-panes -t '$WIN' | wc -l | tr -d ' ') = 9 ]"
t "merge --list radi" bash -c "claude-grid-merge.sh --list '\$(tmux display-message -t cgt -p \"#{session_id}\")' >/dev/null"
tmux new-session -d -s cgp -x 200 -y 60 -c "$P/app" "sleep 600"
tmux set-option -t cgp @grid_dir "$P/app"; tmux set-option -t cgp @grid_pool app
PW=$(tmux display-message -t cgp -p '#{window_id}')
"$HOME/.local/bin/claude-grid-add.sh" "$PW"; sleep 1
t "pool grid: novi panel sam uđe u svoj stol (sp-claim)" bash -c "tmux list-panes -t '$PW' -F '#{pane_current_path}' | grep -q 'app-wt[0-9]'"
t "pick --gen izlista stolove" bash -c "claude-grid-pick.sh --gen '$P/app' | grep -q 'app-wt'"

echo
if [ "$FAIL" = 0 ]; then echo "SVE PROŠLO ($PASS/$PASS)"; exit 0
else printf 'PALO %d od %d:%b\n' "$FAIL" "$((PASS + FAIL))" "$FAILS"; exit 1; fi
