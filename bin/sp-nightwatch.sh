#!/bin/bash
# sp-nightwatch.sh — nudge stalled Claude Grid panels back to work.
#
# A panel that hits
# the usage limit stops dead and stays stopped; the limit lifting does not restart
# it. This watches each pane and re-sends a short "continue" once the pane is
# genuinely stuck, so the work resumes on its own when the window rolls over.
#
# Deliberately timid. It types into live sessions, so a false positive costs real
# work. FOUR conditions must ALL hold before it sends anything:
#   1. the pane text matches a usage-limit signature,
#   2. the pane content hash is unchanged since the previous check (it is idle, not
#      thinking — a working pane repaints its spinner every second),
#   3. the composer is EMPTY (see below),
#   4. at least NUDGE_COOLDOWN has passed since this pane was last nudged.
# While the limit is still active the nudge is simply ignored by the CLI, so retrying
# every cycle is harmless and self-correcting: the first attempt after the reset lands.
#
# WHY CONDITION 3 EXISTS (added 2026-08-27)
# Once this script had to be killed by hand: every task had finished, but
# unsent text was sitting in the panels' composers. A nudge would have been appended
# to that text and submitted together with it, sending something nobody wrote. The
# composer check makes that impossible, and it fails CLOSED — a composer it cannot
# read confidently counts as non-empty, so the pane is skipped and the reason logged.
#
# SESSION DISCOVERY
# claude-grid-tmux.sh names its session "claudegrid-$$", so the name changes every
# run. This finds the session that holds the most pool-worktree panes (any path
# ending in -wtN). Pass a session name to override.
#
# It never spawns panes, never touches git, and only ever sends one plain sentence.
# Kill it with:  pkill -f sp-nightwatch.sh

set -uo pipefail

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/claudegrid/nightwatch.log"
STATE="$(mktemp -d)"
INTERVAL=300          # 5 min between checks
NUDGE_COOLDOWN=900    # 15 min minimum between nudges to the same pane
MAX_RUNTIME=39600     # 11 h, then exit so it cannot outlive the night
NUDGE='nastavi gdje si stao. ako si stao na limitu, samo nastavi zadatak iz briefa. ne pocinji ispocetka i ne ponavljaj vec napravljene commitove.'

# A working pane repaints constantly; an idle one does not. Match the CLI's own
# limit wording plus the generic API phrasing.
command -v sha1sum >/dev/null 2>&1 && HASHCMD=sha1sum || HASHCMD=shasum
LIMIT_RE='session limit|usage limit|rate limit|resets [0-9]|limit .*reached|out of (tokens|credits)'

# Is this path a pool worktree (…-wtN)?
is_wt() { case "$(basename "$1")" in *-wt[0-9]*) return 0 ;; *) return 1 ;; esac; }

# Find the tmux session holding the most pool-worktree panes. Argument overrides.
discover_session() {
  if [ -n "${1:-}" ]; then printf '%s' "$1"; return; fi
  tmux list-panes -a -F '#{session_name} #{pane_current_path}' 2>/dev/null \
    | awk '$2 ~ /-wt[0-9]+$/ { print $1 }' \
    | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'
}

# Read the composer. Prints nothing and returns 0 when it is empty (safe to type);
# prints what it found and returns 1 otherwise.
#
# The prompt marker is "❯" (U+276F), NOT ASCII ">". Verified against a live grid on
# 2026-08-27: matching ">" finds no prompt line on any pane, the function fails
# closed on all of them, and the watchdog then never nudges anything. Both are
# accepted here so a future CLI restyling cannot silently disarm the whole script.
composer_is_empty() {
  local pane="$1" line
  line=$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -12 \
         | grep -E '^[[:space:]]*[│|]?[[:space:]]*(❯|>)' | tail -1)
  # No prompt line visible at all: the CLI may not be at a prompt. Fail closed.
  [ -n "$line" ] || { printf 'nema-prompta'; return 1; }
  # The padding after the prompt is U+00A0, not a plain space, and the box drawing is
  # multibyte too. `tr -d` is byte-oriented and mangles both, so this is done in
  # Python where "is this character whitespace" is a real question with a real answer.
  printf '%s' "$line" | python3 -c '
import sys
s = sys.stdin.read()
i = s.find("❯")                     # the real prompt marker
if i < 0: i = s.find(">")                # tolerate a plain ASCII restyling
rest = s[i + 1:] if i >= 0 else s
BOX = set("│|╭╮╰╯─█▌")
rest = "".join(c for c in rest if not c.isspace() and c not in BOX)
if rest:
    sys.stdout.write(rest[:40])
    sys.exit(1)
sys.exit(0)
'
}

started=$(date +%s)
mkdir -p "$(dirname "$LOG")"
SESSION=$(discover_session "${1:-}")
if [ -z "$SESSION" ]; then
  echo "[$(date '+%F %T')] nema tmux sesije s worktree panelima (*-wtN), izlazim" >>"$LOG"
  exit 1
fi
echo "[$(date '+%F %T')] nightwatch start, session=$SESSION interval=${INTERVAL}s" >>"$LOG"

while true; do
  now=$(date +%s)
  [ $((now - started)) -ge "$MAX_RUNTIME" ] && { echo "[$(date '+%F %T')] max runtime, izlazim" >>"$LOG"; exit 0; }

  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[$(date '+%F %T')] grid sesija '$SESSION' nestala, izlazim" >>"$LOG"
    exit 1
  fi

  while IFS=' ' read -r pane cwd; do
    is_wt "$cwd" || continue              # never type into anything outside a worktree
    name=$(basename "$cwd")

    text=$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -40)
    [ -n "$text" ] || continue

    hash=$(printf '%s' "$text" | $HASHCMD | cut -d' ' -f1)
    prev=$(cat "$STATE/$name.hash" 2>/dev/null || echo '')
    printf '%s' "$hash" >"$STATE/$name.hash"

    grep -qiE "$LIMIT_RE" <<<"$text" || continue            # (1) limit visible
    [ "$hash" = "$prev" ] || {                              # (2) genuinely idle
      echo "[$(date '+%F %T')] $name: limit vidljiv ali se panel jos mijenja, cekam" >>"$LOG"
      continue
    }

    if ! leftover=$(composer_is_empty "$pane"); then        # (3) composer empty
      echo "[$(date '+%F %T')] $name: PRESKACEM, composer nije prazan ($leftover)" >>"$LOG"
      continue
    fi

    lastfile="$STATE/$name.nudged"
    last=$(cat "$lastfile" 2>/dev/null || echo 0)
    [ $((now - last)) -ge "$NUDGE_COOLDOWN" ] || continue    # (4) cooldown

    tmux send-keys -t "$pane" -l "$NUDGE" 2>/dev/null && sleep 1 && tmux send-keys -t "$pane" Enter 2>/dev/null
    printf '%s' "$now" >"$lastfile"
    echo "[$(date '+%F %T')] $name: gurnut dalje" >>"$LOG"
  done < <(tmux list-panes -a -F "#{pane_id} #{pane_current_path}" 2>/dev/null)

  sleep "$INTERVAL"
done
