# Changelog

Each version's notes. The release on GitHub is built from the section with its number.

## 1.2.0-beta.3 — 2026-09-20

### Fixed

- A connection that fails on the first try — it happens on some networks — no longer means "Could not
  reach GitHub": the update check and the update's downloads try once more, a few seconds later.

## 1.2.0-beta.2 — 2026-09-20

Fixes from a last review of the one-click update. From 1.2.0-beta.1, **Update now** brings you here.

### Fixed

- "Not now" while the update was unpacking or checking the new version did not stop it.
- If the update helper itself ever ran into an error, TLDR Vocab stayed closed with no message. It now
  starts again and says what happened.
- The update could not start with AutoHotkey's "UI Access" edition.
- Network errors showed double brackets: "Could not reach GitHub ((0x80072EFD))".

## 1.2.0-beta.1 — 2026-09-19

A test version of 1.2.0.

### New

- **Update with one click.** When a new version is out, its notice opens a window with what is new
  and **Update now**. TLDR Vocab downloads it, checks every file against the published check sums,
  closes, swaps the files and starts again — or, if anything goes wrong, puts the old version back.
  Your words, settings and saved lookups are never touched, and the version you had is kept in the
  "previous version" folder.
- The same window has **Download page**, for anyone who would rather update by hand; the README
  explains how.

This first version with it can update to the next one — updating *to* it from 1.1.0-beta.2 is still
by hand, once.

## 1.1.0-beta.2 — 2026-09-19

The second test version of 1.1.0.

### New

- **Checks for updates.** Once a day it asks GitHub whether there is a newer version, and a tray notice
  says so — click it to open the download page. Test versions are only offered to people already on
  one. Settings → General can switch it off, and has "check now"; so does the tray menu.
- **Translate a passage** (was "translate a sentence"), with a new choice in Settings → Translation:
  the sentences around the one you click (as before), or only that one sentence.
- **Settings scrolls,** and can be made shorter or taller; it opens as tall as you left it.

### Changed

- The word list's "lock" is replaced by a gear that opens Settings.
- The speaker button is always there; the setting that hid it is gone.
- Settings says the proxy must be HTTP; SOCKS proxies do not work.
- README: starting as administrator at sign-in without the Windows prompt (Task Scheduler), and credit
  for the icon (Magnific, Flaticon).

## 1.1.0-beta.1 — 2026-09-19

A test version of 1.1.0.

### New

- **Translate into other languages.** Settings → Translation: Persian (still the default) or Arabic, Urdu,
  Turkish, Spanish, French, German, Italian, Portuguese, Dutch, Polish, Russian, Ukrainian, Hindi,
  Indonesian, Vietnamese, Chinese, Japanese or Korean. What you read is always English. Words you saved
  before keep the language they were saved in.
- **Pin a card.** The pin at the top right of a card keeps it on screen: drag it anywhere, close it with
  its ×. The next lookup opens a new card beside it, so you can keep several.
- **Start with Windows:** the README explains how, and Settings links to it.

### Changed

- Version numbers, release notes from this file, and test versions published as pre-releases.

## 1.0.0 — 2026-09-19

The first release.
