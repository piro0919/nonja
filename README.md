# Nonja

A quiet inbox for macOS notifications. Notification + Ninja.

Banners interrupt. Notification Center piles everything into one stream with no
sense of read or unread and no way to deal with a batch. Nonja turns off neither
of those for you — it gives you somewhere else to look.

Turn banners off in System Settings. Notifications still land in Notification
Center, and Nonja reads them from there, groups them by app, and lets you clear a
whole app in one click. Clicking a notification opens the app exactly where the
real notification would have taken you.

macOS 14+. No Xcode needed: `./build.sh` compiles with the Swift that ships with
the Command Line Tools.

## What it does

- **Reads notifications in the background.** No banner, no popup, nothing on screen
  until you ask for it.
- **Groups by app.** A stream sorted only by time is what made Notification Center
  hard to read in the first place.
- **Jumps to the source.** Clicking a row presses the real notification, so you land
  wherever that app meant to take you.
- **Clears itself.** Per-app rules hold notifications for a while and drop the ones
  you never touched.
- **Shows no numbers.** A bell that is filled means something is waiting. That is the
  whole status display. Whether it is five or five hundred does not change what you
  are going to do about it.

## Permissions

| Permission | Why |
| --- | --- |
| Full Disk Access | Reading the Notification Center database |
| Accessibility | Pressing the real notification so the app opens |

Both are granted in System Settings under Privacy & Security. Nonja checks on
launch and points you at the right pane if either is missing. It never writes to
the Notification Center database.

## Shape of the thing

| file | what it does |
| --- | --- |
| `Sources/Store.swift` | Reads the Notification Center database, decodes each payload |
| `Sources/Engine.swift` | Applies the rules and decides what belongs in the inbox |
| `Sources/Opener.swift` | Finds the real notification by UUID and presses it |
| `Sources/ListWindow.swift` | The list — grouping, filtering, per-group actions |
| `Sources/RulesWindow.swift` | Settings: rules, confirm basis, launch at login |
| `Sources/Mark.swift` | Draws the menu bar mark, filled or outlined |
| `Sources/State.swift` | What has been dealt with, stored as JSON |
| `Sources/Updater.swift` | Sparkle. Checks once at launch, speaks only when there is an update |
| `Sources/SelfTest.swift` | Checks the rules without touching the screen |

## Building and checking

```sh
./build.sh                               # produces Nonja.app
./Nonja.app/Contents/MacOS/Nonja --selftest   # rule behaviour
./Nonja.app/Contents/MacOS/Nonja --dump       # what it can read
./Nonja.app/Contents/MacOS/Nonja --press UUID # jump to an app
./Nonja.app/Contents/MacOS/Nonja --login on   # register at login
```

`./release.sh <version>` builds, runs the self test, packages a DMG and a zip,
signs the appcast, and pushes a GitHub release.

Development builds are signed with a self-signed certificate. Ad-hoc signing
changes identity on every build, and macOS drops both permissions each time.

## A warning worth reading

Nonja depends on where macOS keeps its notifications, which Apple has never
documented. The path most articles point at is already dead on current macOS.
This one works today and may stop working after any system update. When it does,
Nonja says so on screen rather than sitting there looking empty.

`SPEC.md` holds the reasoning behind every decision here, in Japanese, including
the routes that were tried and abandoned.
