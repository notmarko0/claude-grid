#!/bin/bash
# sp-common.sh — zajednička biblioteka za sp-* (session pool) helpere.
# SAMO se source-a:  . "$HOME/.local/bin/sp-common.sh"   (ne izvršava se direktno)
#
# Model: worktree pool sa siblings mapama <parent>/<prefix>N.
# Stanje "slobodan/zauzet" u atomskim mkdir lockovima, NE u imenu grane.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SP_CFG_DIR="$HOME/.config/claudegrid"
SP_POOLS_DIR="$SP_CFG_DIR/pools"
SP_LOCKS_DIR="$SP_CFG_DIR/locks"

# --- čitanje key=value ---
sp_pool_get_file() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1; }   # <file> <key>
sp_pool_get()      { sp_pool_get_file "$SP_POOLS_DIR/$1" "$2"; }         # <label> <key>

# --- repo root: dirname(git-common-dir); isti iz glavnog repoa i svih worktreejeva ---
sp_repo_root() {                                                          # [dir]
  # pwd -P: fizička (canonical) putanja — usklađeno s tim kako `git worktree list`
  # prijavljuje putanje (git razrješava symlinkove, npr. /var -> /private/var).
  local d="${1:-$PWD}" gd
  gd=$(cd "$d" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
  dirname "$gd"
}

# --- rezolucija poola ---
sp_find_pool_for_root() {                                                 # <root> -> label
  local root="$1" f
  [ -d "$SP_POOLS_DIR" ] || return 1
  for f in "$SP_POOLS_DIR"/*; do
    [ -f "$f" ] || continue
    [ "$(sp_pool_get_file "$f" repo)" = "$root" ] && { basename "$f"; return 0; }
  done
  return 1
}
sp_label_for() {                                                          # [dir] -> label
  local root; root=$(sp_repo_root "${1:-$PWD}") || return 1
  sp_find_pool_for_root "$root"
}

# --- integracijska grana i njen ref (origin ako postoji) ---
sp_integ()     { sp_pool_get "$1" integ; }                                # <label>
sp_integ_ref() {                                                          # <label> -> baza za grananje/reset i merged-check
  # Prednost LOKALNOJ integracijskoj grani (odražava lokalne merge-ove prije pusha);
  # fallback na origin/<integ> samo ako lokalna ne postoji.
  local integ root; integ=$(sp_integ "$1"); root=$(sp_pool_get "$1" repo)
  if git -C "$root" show-ref --verify --quiet "refs/heads/$integ"; then
    echo "$integ"
  elif git -C "$root" rev-parse --verify --quiet "origin/$integ" >/dev/null 2>&1; then
    echo "origin/$integ"
  else
    echo "$integ"
  fi
}

# --- worktree enumeracija (samo <parent>/<prefix>N; glavni repo isključen) ---
sp_worktrees() {                                                          # <label> -> "N\tpath" sort -n
  local root prefix parent n
  root=$(sp_pool_get "$1" repo); prefix=$(sp_pool_get "$1" prefix); parent=$(dirname "$root")
  git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r p; do
    case "$p" in
      "$parent/$prefix"[0-9]*)
        n="${p##*"$prefix"}"
        case "$n" in ''|*[!0-9]*) continue ;; esac
        printf '%s\t%s\n' "$n" "$p"
      ;;
    esac
  done | sort -n
}
sp_wt_index() { local prefix; prefix=$(sp_pool_get "$2" prefix); echo "${1##*"$prefix"}"; }  # <path> <label>

# --- lock (atomski mkdir) ---
sp_lock_dir()  { echo "$SP_LOCKS_DIR/$1/wt$2"; }                          # <label> <N>
sp_is_locked() { [ -d "$(sp_lock_dir "$1" "$2")" ]; }                     # <label> <N>
sp_lock_meta() { sp_pool_get_file "$(sp_lock_dir "$1" "$2")/meta" "$3"; } # <label> <N> <key>
sp_unlock()    { rm -rf "$(sp_lock_dir "$1" "$2")"; }                     # <label> <N>
sp_lock() {                                                               # <label> <N> <slug> -> 0 zaključano sad
  local ld; ld=$(sp_lock_dir "$1" "$2"); mkdir -p "$SP_LOCKS_DIR/$1"
  if mkdir "$ld" 2>/dev/null; then
    { echo "slug=${3:-}"; echo "pane=${TMUX_PANE:-}"; echo "pid=${PPID:-$$}"; echo "claimed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } >"$ld/meta"
    return 0
  fi
  return 1
}
sp_lock_is_stale() {                                                      # <label> <N> -> 0=stale
  local ld pane pid; ld=$(sp_lock_dir "$1" "$2"); [ -d "$ld" ] || return 1
  pane=$(sp_pool_get_file "$ld/meta" pane); pid=$(sp_pool_get_file "$ld/meta" pid)
  [ -n "$pane" ] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane" && return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 1
  return 0
}
sp_reap_stale() {                                                         # <label>
  local n path
  while IFS=$'\t' read -r n path; do
    sp_lock_is_stale "$1" "$n" && sp_unlock "$1" "$n"
  done < <(sp_worktrees "$1")
  return 0   # side-effect fn: uvijek 0 (inače set -e u pozivatelju puca na zadnjem 'not stale')
}

# --- git stanje worktreeja ---
sp_wt_clean()  { [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }        # <path>
sp_wt_branch() { git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || true; }  # <path> (detached HEAD -> prazno, rc 0; inače set -e u pozivatelju puca)
sp_wt_ahead()  { git -C "$1" rev-list --count "$2..HEAD" 2>/dev/null || echo 0; } # <path> <ref>

# --- mirror za brz pregled ---
sp_regen_mirror() {                                                       # <label>
  local out="$SP_CFG_DIR/$1-map" n path br state slug
  : >"$out"
  while IFS=$'\t' read -r n path; do
    br=$(sp_wt_branch "$path"); [ -z "$br" ] && br="-"
    if sp_is_locked "$1" "$n"; then slug=$(sp_lock_meta "$1" "$n" slug); state="ZAUZET(${slug:-?})"; else state="slobodan"; fi
    printf 'wt%s\t%s\t%s\n' "$n" "$br" "$state" >>"$out"
  done < <(sp_worktrees "$1")
  return 0
}
