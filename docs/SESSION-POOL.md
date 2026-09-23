# Worktree pool: paralelne Claude sesije bez sudara

**Problem:** 4 Claudea u istom repou dijele jednu radnu mapu i jedan `HEAD`.
Commitovi završe na krivoj grani, a izmjene se miješaju.

**Rješenje:** svaki panel dobije svoj **stol**, to jest `git worktree` (zasebnu
radnu mapu) na zasebnoj grani. Git sam ne dopušta istu granu u dva worktreeja.

```
~/projekti/app        ← glavni repo: drži čist main, U NJEMU SE NE RADI
~/projekti/app-wt1    ← stol 1 (grana scratch/wt1 → feat/<tema>)
~/projekti/app-wt2    ← stol 2
…                     ← kad su svi zauzeti, sp-claim sam napravi sljedeći
```

## Postavljanje (jednom po repou)

```bash
cd ~/projekti/app && sp-setup
```
To napravi pool marker (`~/.config/claudegrid/pools/app`), 5 stolova i
**pre-commit hook** koji blokira direktan commit na `main`.

## Kako se radi

```
claude-grid                    # odaberi repo -> svaki panel sam uzme slobodan stol (sp-claim)
Ctrl-b n                       # novi panel = novi slobodan stol
Ctrl-b o                       # novi panel na ODREĐENOM stolu (fzf) — povratak na postojeći rad
Ctrl-b x                       # ugasi panel = auto sp-release (odbije ako rad nije mergean)
claude-grid-tmux.sh feat/x     # otvori panel točno na stolu koji drži granu feat/x
claude-grid-tmux.sh wt2 wt5    # 2 panela, na wt2 i wt5
```

**`sp-claim` resetira stol na `main`**, pa je dobar za nov posao.
**`sp-open` ne dira granu**, pa je dobar za povratak na postojeći rad.
Za povratak zato uvijek koristi `Ctrl-b o` ili `claude-grid-tmux.sh <grana>`.

## Tijek jednog featurea (ovo najčešće izvrši Claude u panelu)

```bash
sp-name moja-tema                  # scratch/wtN -> feat/moja-tema  (PRVO, uvijek)
# (npm install / pip install… — ignorirani fajlovi poput node_modules su PER-STOL)
# ...radi, commitaj često...
git push -u origin feat/moja-tema  # čim ima nešto vrijedno
git merge main                     # kad god nešto drugo sleti u main — odmah, ne na kraju
# kraj:
git merge main                     # konflikte rješavaš OVDJE, u grani
git -C ~/projekti/app merge --ff-only feat/moja-tema
git -C ~/projekti/app push origin main
sp-release                         # vrati stol
```
Nakon toga u **svim ostalim** aktivnim stolovima napravi `git merge main`.

## Pravila koja se najčešće prekrše

1. **`sp-name <tema>` odmah**, nikad `git switch -c`. `sp-release` briše samo `feat/*`
   grane, pa ručno napravljena grana ostane visjeti.
2. **`main` se mergea U granu**, a `main` se samo fast-forwarda (`--ff-only`).
   Hook blokira commit na `main`, a konfliktan merge na `main` je commit.
   `--no-verify` nije rješenje.
3. **Drift je skuplji od paralelizma.** Što grana dulje ne povuče `main`, to je merge gori.
4. **Paralelno se odlučuje po fajlovima, ne po temama.** Dva „nepovezana" featurea koja
   oba diraju isti veliki fajl idu **jedan za drugim**.

### Provjera prije paralelnog rada (30 s)
```bash
cd ~/projekti/app
for b in $(git branch --list 'feat/*' --format='%(refname:short)'); do
  git diff --name-only $(git merge-base $b main)..$b
done | sort | uniq -d        # fajlovi koje dira više od jedne grane → ne paralelno
```

## Planiranje s Claudeom (preporučeno)

Otvori **običnu** `claude` sesiju u glavnom repou (ne panel grida, jer bi panel potrošio stol)
i reci: *„planiram A, B i C, složi mi grid-plan"*. Traži od njega:
1. koliko panela i koju naredbu (`claude-grid-tmux.sh 2`);
2. po panelu: slug za `sp-name`, **koje fajlove posjeduje**, koje ne smije dirati,
   i gotov tekst za paste u taj panel;
3. redoslijed landanja i kad koji panel mora `git merge main`;
4. što **ne** ide paralelno i zašto, s imenima fajlova koji se sijeku.

Ta ista sesija radi završni `merge --ff-only` i `push`.

## Pregled

```
sp-status        # stol / grana / slobodan-zauzet / vlasnik / dirty / ahead-behind
sp-wip           # sav nedovršeni rad: stolovi, siroče grane, stashevi, remote, gdje su bili razgovori
sp-adopt feat/x  # ubaci postojeću granu u slobodan stol
sp-release --force   # oslobodi i nemergeano (GUBIŠ taj rad)
```

## Poznate zamke

- **„slobodan" u `sp-status` ≠ dostupan za `sp-claim`.** `sp-claim` traži stol bez locka,
  na grani `scratch/*`, čist i bez nemergeanih commitova. Stol na `feat/*` grani ne dolazi u obzir.
- **`sp-release` ne prima ime stola.** Uvijek radi na stolu u kojem stojiš (`$PWD`).
  Zato prvo `cd` u stol, pa `sp-release`.
- **`sp-release` može reći „oslobođen", a grana ipak ostane** ako je ispred svog upstreama.
  Provjeri s `git branch --list 'feat/*'`.
- **Lock je vezan na tmux panel.** Dok panel živi, stol je zauzet. Ako pool „nestaje":
  `ls ~/.config/claudegrid/locks/<repo>/`.
- **Transkripti su po mapi:** `claude --resume` u stolu vidi samo razgovore iz tog stola.
