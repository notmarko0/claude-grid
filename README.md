# Claude Grid

Više **Claude Code** sesija odjednom, složenih u mrežu (grid) u jednom prozoru terminala.
Radi na **Windowsu (kroz WSL)**, Linuxu i Macu.

```
┌─ ▶ SESSION 1 ◀ ─┬──── 2 ────┬──── 3 ────┬──── 4 ────┐
│ claude          │ claude    │ claude    │ claude    │
│                 │           │           │           │
├────── 5 ────────┼──── 6 ────┴─────┬─────┴── 7 ──────┤
│ claude          │ claude          │ claude          │
└─────────────────┴─────────────────┴─────────────────┘
```

- **1–16 panela**, u svakom radi `claude`. Redovi imaju najviše 4 panela, višak ide u novi red.
- **Prečaci** (prvo `Ctrl-b`, pusti, pa tipka):
  - `n`: novi Claude panel
  - `x`: ugasi panel (pita y/n) i presloži ostale
  - `j`: dovuci žive Claude sesije iz drugih prozora u ovaj (s pregledom uživo)
  - `o`: novi panel na određenom stolu (vidi pool ispod)
  - `b`: pokaži ili sakrij statusnu traku
- **Miš radi:** klik bira panel, kotačić scrolla, povlačenjem ruba mijenjaš veličinu.
- **Aktivni panel** ima jarku traku `▶ SESSION N ◀` na vrhu.
- Zatvoriš prozor i grid se sam počisti. Razgovori se **ne gube**: u istoj mapi upišeš `claude --resume`.

### Worktree pool (za paralelan rad na istom git repou)

Kad 4 Claudea rade u istom repou, gaze si granu i fajlove. Pool to rješava:
svaki panel dobije svoj **stol**, to jest vlastiti `git worktree` na vlastitoj grani.
Grid ga dodijeli sam.

```bash
cd ~/projekti/moj-repo && sp-setup     # jednom po repou: napravi moj-repo-wt1..5 + zaštitu maina
claude-grid                            # odaberi taj repo -> svaki panel sam ode u svoj stol
```

U panelu Claude (ili ti) zatim:
`sp-name <tema>` → radi → commit → `git merge main` → u glavnom repou `git merge --ff-only feat/<tema>` → `sp-release`.
Detalji i zamke su u [docs/SESSION-POOL.md](docs/SESSION-POOL.md).

---

## Instalacija na Windowsu

> **Najlakše:** otvori Claude Code i reci mu
> *„Instaliraj mi Claude Grid s <link na ovaj repo>, prati INSTALL.md"*.
> On zna sve korake ispod.

Ručno:

1. **WSL** (Linux unutar Windowsa). U PowerShellu **kao administrator**:
   `wsl --install -d Ubuntu`, pa **restart** računala. Nakon restarta se Ubuntu otvori
   i traži korisničko ime i lozinku (to je Linux račun, ne Windows).
2. **U Ubuntuu** (Start → „Ubuntu"):
   ```bash
   sudo apt update && sudo apt install -y tmux fzf git python3 curl
   curl -fsSL https://claude.ai/install.sh | bash      # Claude Code, službeni instalacijski
   claude                                              # prijavi se jednom, pa izađi (/exit)
   ```
   Claude Code mora biti instaliran **unutar Ubuntua**. Onaj na Windowsu ga ne vidi.
3. **Claude Grid:**
   ```bash
   git clone <link na ovaj repo> ~/claude-grid
   cd ~/claude-grid && ./install.sh && ./tests/selftest.sh
   ```
4. **Pokretanje:** u Windows Terminalu klikni strelicu `˅` pokraj `+` → **Claude Grid**.
   Ili u Ubuntuu upiši `claude-grid`.
   Za prečac na Desktopu: `windows\ClaudeGrid.local.bat` (napravi ga install).

**Važno:** projekte drži **unutar Ubuntua** (`~/projekti/...`), ne na `C:\` (`/mnt/c/...`).
Na `C:\` git radi puno sporije, a worktreeji znaju zapinjati.
Mapu Ubuntua vidiš iz Windows Explorera na `\\wsl$\Ubuntu\home\<ime>`.

## Mac / Linux

```bash
brew install tmux fzf git        # ili: sudo apt install tmux fzf git python3
git clone <link> ~/claude-grid && cd ~/claude-grid && ./install.sh
```

## Postavke

| Fajl | Što |
|---|---|
| `~/.config/claudegrid/projects` | favoriti u biraču (`Labela = ~/putanja`) |
| `~/.config/claudegrid/config` | `CLAUDE_GRID_FLAGS`, `CLAUDE_BIN` |
| `~/.config/claudegrid/tmux.conf` | izgled i prečaci (install ga prepisuje; svoje izmjene stavi u `~/.tmux.conf`) |

**Dozvole:** po defaultu Claude u svakom panelu pita prije naredbi i izmjena fajlova.
Ako želiš da ne pita (tako radi autor), u `config` stavi
`CLAUDE_GRID_FLAGS="--dangerously-skip-permissions"`. Tada Claude **smije sve bez
pitanja**, pa to koristi samo na projektima gdje ti to odgovara.

## Naredbe

| Naredba | Što radi |
|---|---|
| `claude-grid` | pita broj panela i projekt pa otvori grid |
| `claude-grid-tmux.sh 4 ~/projekt` | isto, bez pitanja |
| `claude-grid-tmux.sh feat/x` | 1 panel na stolu koji drži granu `feat/x` (ne resetira je) |
| `sp-setup` | uključi pool u trenutnom repou |
| `sp-status` / `sp-wip` | tko drži koji stol / što je nedovršeno i gdje |
| `sp-name <tema>` | `scratch/wtN` → `feat/<tema>` |
| `sp-release [--force]` | vrati stol (odbije ako rad nije mergean) |
| `sp-open <wtN\|grana>` | zaključaj određeni stol bez reseta |
| `sp-adopt <grana>` | ubaci postojeću granu u slobodan stol |
| `sp-nightwatch.sh` | (opcija) preko noći gurne panele koji su stali na limitu |

Nadogradnja: `cd ~/claude-grid && git pull && ./install.sh` ·
Uklanjanje: `./install.sh --uninstall`
