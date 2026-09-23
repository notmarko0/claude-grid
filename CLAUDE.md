# Claude Grid — za Claudea

Ako te korisnik traži da **instaliraš** Claude Grid: slijedi `INSTALL.md` korak po korak.

Ako **mijenjaš kod**:
- Skripte su u `bin/`, a instaliraju se u `~/.local/bin`. Nakon izmjene pokreni `./install.sh`.
- Moraju raditi na **bash 3.2 (Mac) i GNU/Linuxu**. Zato nema `sed -i`, `stat -f`,
  `mapfile` ni `declare -A` u glavnim skriptama.
- Jedini izvor istine za raspored je `bin/claude-grid-relayout.sh`.
- Gate: `bash -n bin/*` i `./tests/selftest.sh` moraju proći.
- Fajlovi moraju imati LF krajeve redova (`.gitattributes` to čuva). Jedina iznimka je `.bat`.
