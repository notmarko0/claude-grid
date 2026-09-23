# INSTALL.md — upute za Claude Code agenta

> Ovaj fajl je pisan **za Claudea** koji instalira Claude Grid korisniku.
> Korisnik ti je vjerojatno samo dao link na repo. Vodi ga kroz korake, a sam
> izvrši sve što smiješ.

## Pravila

1. **Pitaj prije restarta.** `wsl --install` traži administratora i restart računala.
   Restart ugasi sve što korisnik ima otvoreno, pa ga ne pokreći sam: objasni i pričekaj „da".
2. **Instalacija ide unutar WSL-a**, ne na Windows stranu. tmux ne radi na Windowsu.
   Kloniraj repo u Linux home (`~/claude-grid`), **ne** u `/mnt/c/...`.
3. **Ne uključuj `--dangerously-skip-permissions` sam.** Pitaj korisnika (korak 6).
4. **Lozinke ne traži u chatu.** `sudo` u WSL-u traži Linux lozinku: neka je korisnik
   upiše sam u terminal (predloži mu `! <naredba>` ili da otvori Ubuntu terminal).
5. Na kraju **pokreni `./tests/selftest.sh`** i javi stvarni rezultat.

## Korak 0: gdje si?

- `uname -a` vrati Linux i `grep -i microsoft /proc/version` nešto nađe → već si
  **u WSL-u**. Preskoči na korak 2.
- Ako si na **Windows strani** (PowerShell / Git Bash): WSL naredbe zoveš kao
  `wsl -d Ubuntu -- bash -lc "<naredba>"`.
- Ako si na **Macu ili Linuxu**: preskoči WSL i idi na korak 2
  (Mac: `brew install tmux fzf git`).

## Korak 1: WSL (samo Windows)

```powershell
wsl --status
wsl -l -v
```
- Ima distribuciju **VERSION 2** (idealno Ubuntu 22.04 ili 24.04) → dalje.
- Nema WSL-a → korisnik u **PowerShellu kao administrator** pokrene
  `wsl --install -d Ubuntu`, pa **restart**. Nakon restarta Ubuntu traži Linux
  korisničko ime i lozinku. Kad to napravi, nastavi (nova sesija će možda trebati
  ponovno pročitati ovaj fajl).
- WSL 1 → `wsl --set-version Ubuntu 2`.

## Korak 2: paketi (u WSL-u)

```bash
sudo apt update && sudo apt install -y tmux fzf git python3 curl
tmux -V     # treba 3.2 ili noviji (Ubuntu 22.04 = 3.2a, 24.04 = 3.4)
```

## Korak 3: Claude Code UNUTAR WSL-a

Claude na Windowsu i Claude u WSL-u su **dvije odvojene instalacije**. Grid treba ovu drugu.
```bash
command -v claude || curl -fsSL https://claude.ai/install.sh | bash
```
Korisnik zatim jednom pokrene `claude` u Ubuntu terminalu, prijavi se i izađe s `/exit`.
Bez toga bi se svaki panel grida zasebno tražio prijavu.

## Korak 4: repo i instalacija

```bash
git clone <URL-repoa> ~/claude-grid
cd ~/claude-grid
./install.sh --check      # preduvjeti
./install.sh
./tests/selftest.sh       # mora završiti sa "SVE PROŠLO"
```
Na WSL-u install sam doda **„Claude Grid" profil u Windows Terminal** i napravi
`windows/ClaudeGrid.local.bat` (dvoklik pokretač, može se kopirati na Desktop).

Ako selftest padne: pročitaj ispis ispod ✗, popravi uzrok (najčešće paket koji
nedostaje ili stari tmux) i ponovi. Ne prijavljuj uspjeh bez „SVE PROŠLO".

## Korak 5: favoriti

Pitaj korisnika na kojim projektima radi. Upiši ih u `~/.config/claudegrid/projects`:
```
Moja app = ~/projekti/moja-app
```
Ako su mu projekti trenutno na `C:\`, predloži da ih klonira u `~/projekti`
(brže, i worktreeji rade pouzdano).

## Korak 6: dozvole (pitaj)

Objasni ukratko i pitaj:
- **Default (prazno):** Claude u svakom panelu pita prije naredbi i izmjena. Sigurnije.
- **`--dangerously-skip-permissions`:** ne pita ništa. Brže za paralelan rad, ali Claude
  smije sve. Tako radi autor grida.

Ako izabere drugo: u `~/.config/claudegrid/config` postavi
`CLAUDE_GRID_FLAGS="--dangerously-skip-permissions"`.

## Korak 7: pool (opcija)

Ako želi više Claudea na **istom git repou**: u tom repou `sp-setup`.
To napravi `<repo>-wt1..5` pokraj repoa i pre-commit hook koji brani commit na `main`.
Pokaži mu `docs/SESSION-POOL.md`.

## Korak 8: pokaži kako se koristi

- Windows Terminal → `˅` → **Claude Grid** (ili `claude-grid` u Ubuntuu)
- Prečaci: `Ctrl-b` pa `n` (novi), `x` (ugasi), `j` (spoji), `o` (stol), `b` (status traka)
- Vraćanje razgovora: u istoj mapi `claude --resume`
- Nadogradnja: `cd ~/claude-grid && git pull && ./install.sh`
