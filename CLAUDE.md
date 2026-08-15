# CLAUDE.md (Nonja)

How to work in this repository. The behaviour is documented elsewhere — do not restate it here.

## Where the truth lives

- **[SPEC.md](SPEC.md)** — every decision and the reasoning behind it, including the pitfalls
  worth reading before touching the settings window. Undecided things stay under 保留.
  Change the text here before changing the implementation
- **[README.md](README.md)** — the outward description, the build and check commands, and the
  standing risk that macOS moves the notification store
- **[build.sh](build.sh) / [release.sh](release.sh)** — the comments inside the scripts are the
  procedure. Do not write a second copy of it in prose
- **[lp/](lp/)** — the landing page, deployed to `nonja.kkweb.io`. Its own pnpm workspace;
  `pnpm lp:dev` from the root. Copy lives in `lp/messages/`, English and Japanese

## Language

Commit messages, PR titles and bodies, the README, and release notes are written in English.
This file is part of that.

**Comments in the source and SPEC.md stay in Japanese.** That is what the repository already
does. Do not translate them.

## Commits

**Conventional Commits, as gocci, konechi and okigae write them.** `feat:`, `fix:`, `docs:`,
`perf:`, `refactor:`, `chore:`. Scope the landing page as `feat(lp):`.

The subject says what changed for whoever uses the app, not which file moved. The body is
where the reasoning goes — why this way, what was tried and dropped, what was measured.

Commits made before 2026-08-16 do not follow this. Leave them; do not rewrite pushed history.

## Gather what you can before asking

Every request costs the other person a turn. Almost nothing here needs a human to look at a
screen — the app answers about itself.

```sh
./Nonja.app/Contents/MacOS/Nonja --selftest   # rule behaviour, no UI involved. Run after every change
./Nonja.app/Contents/MacOS/Nonja --dump       # what it can actually read right now
./Nonja.app/Contents/MacOS/Nonja --press UUID # whether the jump to an app works
```

For layout, read the elements rather than looking at a screenshot. Windows overlap and move
between displays, so a picture misleads while the numbers do not:

```sh
osascript -e 'tell application "System Events" to tell process "Nonja" \
  to tell window "Nonja の設定" to get {description, position, size} of every UI element'
```

If two requests have not resolved something, find a way to read it directly before asking a
third time.

**Build with `NONJA_VERSION=99.0.0 ./build.sh` whenever the change has to be seen running.**
A plain build stamps 0.0.0, Sparkle finds the released version newer, and the app replaces
itself with the release moments after launch — the fix disappears and rebuilding does not
bring it back. It looks exactly like a build that never applied. Confirm which build is live
with `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Nonja.app/Contents/Info.plist`.

## When something reads as broken, suspect the store first

Nonja depends on an undocumented location that Apple can move in any system update. Before
treating an empty list as a bug in the code, run `--dump` and confirm the store is still
readable. SPEC.md carries this as a standing risk, not a defect.
