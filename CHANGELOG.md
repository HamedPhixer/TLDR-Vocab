# Changelog

Each version's notes. The release on GitHub is built from the section with its number.

## 1.2.1 — 2026-09-26

### Changed

- **A Gemini model that has used up its free requests for the day is left alone until they start again**
  (midnight in California), instead of being asked first on every lookup. The newest Flash allows only 20
  a day on a free key. When every model is out, the card says until when. A model that is only busy, or
  out of its per-minute requests, is skipped for about a minute.
- The list of Gemini models is asked for once a day instead of at every start, and what is known about the
  models — including which ones are resting — is kept across a restart (in `cache\gemini.json`).

## 1.2.0 — 2026-09-26

Everything since 1.0.0 — tried out first in the 1.1.0 and 1.2.0 test versions — plus a few last fixes.

### New

- **Update with one click.** When a new version is out, a notice opens a window with what is new and
  **Update now**. TLDR Vocab downloads it, checks every file, swaps them and starts again — or puts the
  old version back if anything goes wrong. Your words, settings and saved lookups are never touched.
  From 1.0.0, this one update is by hand: unzip it over your folder.
- **Checks for updates** once a day; Settings → General can switch it off.
- **Translate into other languages:** Persian (still the default), Arabic, Urdu, Turkish, Spanish, French,
  German, Italian, Portuguese, Dutch, Polish, Russian, Ukrainian, Hindi, Indonesian, Vietnamese, Chinese,
  Japanese or Korean — Settings → Translation.
- **Pin a card** to keep it on screen and drag it anywhere; the next lookup opens a new card beside it.
- **Translate a passage** (was "translate a sentence"): the sentences around the one you click, or only
  that one — Settings → Translation.
- **A daily backup of your words.** Before the first word you save each day, `words.json` is copied into
  the new `backups` folder. The last 10 are kept, plus one a month for 6 months. If `words.json` ever
  cannot be read, the newest backup is loaded by itself.
- **Start with Windows:** the README explains how.

### Changed

- **Gemini waits less.** A model that is overloaded or out of free quota is skipped for a minute, instead
  of being asked first — and waited on — every time. If no answer comes within 10 seconds (a normal one
  takes 2 to 6), the question is sent once more and the first answer is used — what pressing "look up
  again" used to do by hand. A connection that fails outright is tried again before the next model, and
  after 30 seconds the card says so instead of waiting on.
- Gemini thinks a little on every model (2.5 models did not think at all), so the meaning fits the
  sentence better.
- Settings scrolls, and can be made shorter or taller.
- The word list's "lock" is now a gear that opens Settings; the speaker button is always there.
- The update check runs 2 seconds after start instead of 8, and still once a day when TLDR Vocab runs
  for days without a restart. A day it could not reach GitHub is tried again an hour later.

### Fixed

- The sentence a looked-up word came with could lose its ends when its line was wider than the part of
  the screen read for the word — and Gemini then explained the word from half a sentence. Such a sentence
  is now read whole, the way Translate reads.
- A selected phrase is looked up without the marks around it: `__delaunay triangulation__` from Markdown
  now finds "delaunay triangulation".
- A footnote stuck to a word — "abridged[119]" copied from Wikipedia, or "abridged119" when the screen
  read the small number as part of the word — no longer stops the lookup.
- A connection that fails on the first try — it happens on some networks — no longer means "Could not
  reach GitHub".

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
