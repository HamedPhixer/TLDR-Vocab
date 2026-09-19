# Why Vocab works the way it does

The code comments say what each part does and why. This file keeps the history
behind that: what was tried first, what went wrong, and what it changed to. Read
it before "simplifying" something that looks odd.

## Reading the screen

**Windows' own OCR, not a downloaded engine.** It ships with every English
Windows, needs no key, and reads a word in about 60 ms. Tesseract and
PaddleOCR/RapidOCR would add 30–100 MB to the download; Gemini can read images
very well but costs quota and 1–3 s. Kept as possible options, not needed yet.

**How much to enlarge.** Measured on rendered text at 8, 12, 14, 37, 66 and
103 px: enlarging helps small text and ruins big text — a 100 px subtitle
enlarged 2× came back as nothing, or as pieces ("plu", "lung", "e"). 1.5× read
every size tested, so the word lookup tries 1.5×, then 1×, then 3×.

**Translate and Summary read the whole monitor, then read again.** Translate
used to read a 1000 × 320 px strip around the pointer. On 1920 and 2560 px wide
screens that cut the ends off most lines of an article. Now the whole monitor
is read at 1× only to find the text, and that text is read again at 1.5× for
the words. Summary got the same second read later: small print read at 1×
came out noticeably worse.

## What Translate takes

This went through five versions; the last one is the rule the user asked for.

1. **Cut at the full stop.** Dialogue like "Wait. No. Not that one." came out
   one useless piece at a time.
2. **The whole block when short (≤ 70 words), else the sentence plus
   neighbours up to 12 words.** Better, but a strip-sized read cut the block.
3. **The paragraph up to 80 words, filled with whole sentences around the
   pointer.** Took a chat, a list or separate lines as one text.
4. **"Would the next word have fitted on this line?"** — the way a reader tells
   a wrapped line from one ended with Enter. It worked on its own, but needs to
   know where the right edge is, and guessed it from whatever else was on
   screen: in a chat window, wider messages nearby made a wrapped sentence look
   ended. Dropped as too fragile.
5. **Now:** a line that *ends* with a stop (`. ! ? : ;` or `…`) ends the text —
   the next line is something else. Inside it, a stop followed by a space and a
   word separates sentences; up to 10 are taken, the one under the pointer
   first, then the next, then the one before. Bits of 1–3 words ("No.") do not
   count. Known limits, accepted: a line without punctuation runs on into the
   next one, and a line that happens to end on a full stop in the middle of a
   paragraph cuts it there. The box is for anything more exact.

The example sentence kept with a *word* only cuts at `. ! ?` and `…` — cutting
at `:` or `;` left Gemini half a sentence of context.

## Sources

- **dictionaryapi.dev** was a definitions source until it had answered nothing
  but HTTP 522 for months (September 2026). Removed.
- **Google's `gtx` translate client** has refused requests as automated at
  times; that is why the Persian track has four sources.
- **Pronunciations** missing from the dictionaries come from Datamuse (ARPAbet,
  converted to IPA, stress mark at the start of the stressed syllable).

## Gemini

- **Models:** the app asks the API which models the key can use and lines up
  the three newest Flash, then the two newest Flash-Lite. Each has its own free
  quota, so a 429 moves to the next one.
- **The fallback guesses are the `-latest` aliases.** They were
  `gemini-2.5-flash(-lite)` until Google retired those (HTTP 404, September
  2026) — a failed model list then pinned every lookup to dead models.
- **A failed model list is not remembered,** so a moment without network does
  not decide the models until a restart.
- **The key test** asks for the model list, not a generation, so it costs none
  of the free quota.

## Hearing words

- **American voice** (`tl=en-US`); plain `en` gave the British one. The cache
  moved from `cache\audio` to `cache\audio-us` because the old folder held
  British recordings.
- **The Windows voice is a fallback and is never saved**, so the next time
  Google answers, the word gets a real recording.

## The translation language (1.1.0)

- **Only the language translations go into is a choice.** What is read stays English: the OCR, picking the
  word, the pronunciation symbols and the base-form rules are all English-specific, and making them general
  is a much bigger job than the translation side, where every translator already takes any pair.
- **Everything language-specific is in `lib\Language.ahk`**; no other file names a language.
- **The saved data kept its Persian names.** `"persian"` holds the translation and `"fa"` its details,
  whatever the language — renaming them would have meant rewriting every saved `words.json`. Each record
  saved since notes its language in `"lang"`; one without it is Persian.
- **Gemini is asked for `"translation"`,** not `"persian"`: a Spanish answer under a key called "persian"
  invites confusion. The reply is filed under the old name as soon as it arrives.
- **Definitions are cached once for all languages,** but some senses carry a short translation, in the
  language of the day. Those carry `"faLang"`, and are only shown in that language.

## Pinned cards (1.1.0)

- **The popup became a class with instances** (`PopupCard`), and the global `Popup` always holds the live
  one. Everything that called `Popup.Something()` kept working unchanged; pinning moves the card into a
  list and puts a fresh card in `Popup`. The alternative — a second popup class — would have copied
  200 lines.
- **A pinned card is dragged by any empty part of it,** handed to Windows as a title-bar click. There is
  no title bar to add, and links still work because a click on a link is never passed on.
- **Pinning is one way:** a pinned card closes, it does not unpin. Unpinning would need to decide what
  happens to the live card already showing.

## The update check (1.1.0)

- **In 1.1.0 it only told; it did not update.** A half update is the one failure that breaks the app for
  good, so updating itself waited for 1.2.0, built around exactly that (below). The check asks GitHub's releases list, not the "latest" address, because "latest" skips test
  versions and someone on a beta should hear of the next beta.
- **A test version is offered only to someone already on one** — the same rule GitHub's own "latest"
  link follows. Version order: 1.10 after 1.2, and 1.1.0-beta.2 before 1.1.0.
- **Once a day,** and silent unless there is news: a failed check at start says nothing (it is logged).

## Updating itself (1.2.0)

1.1.0 only told; 1.2.0 can do it, and the user picks — "Update now" or the download page, never on its
own. How it is built (the steps are at the top of `lib\Install.ahk`):

- **Nothing in the folder changes until everything is checked.** The zip is downloaded, checked, unpacked
  and every file checked again in the temp folder; the new `Vocab.ahk` must pass AutoHotkey's syntax check
  with the AutoHotkey that will run it. Any failure up to there is a message and nothing else.
- **Check sums from `manifest.json`** (written by `build.ps1`): both zips and every file, SHA-256. The zip
  is also checked against the digest GitHub itself keeps for each release file. Downloads come only from
  this repository's release addresses for that exact version.
- **Integrity, not identity.** This proves the files are the ones published on GitHub, over HTTPS. It
  cannot prove who published them — if the GitHub account were taken over, so would be the updates. That
  needs a code-signing certificate (paid, yearly); not worth it yet. It is the same trust as downloading
  the zip from the release page by hand.
- **A helper does the swap,** because a running app cannot replace itself: `lib\Updater.ahk`, run from a
  copy in the temp folder with a copy of AutoHotkey — so nothing it runs from is in the folder, and the
  portable `AutoHotkey64.exe` can be replaced too. It is the *old* version's helper that runs: the one the
  user already has.
- **Backup first, undo on failure.** Each file replaced is copied into `previous version\` first. A
  failure half-way (a virus scanner or OneDrive holding a file — each copy is tried six times) puts every
  file back. This was tested with a file held open on purpose.
- **Checked after, too.** The new version, started with `--updated-from`, writes a marker when it has
  started. If it quits or never writes it, the helper closes it, puts the old files back and starts the
  old version. Tested with a release made to quit at start: back in eight seconds, identical files.
- **What it may write is a list, and the list is checked twice** (the app, then the helper): paths inside
  the folder only, never `Vocab.ini`, `words.json`, `cache\`, `errors.log`. Old code files a new version
  dropped (`lib\*.ahk` only) are moved to the backup, so a leftover can never be loaded by mistake.
- **A git folder is refused** — the developer's own copy is updated with git, not over it.
- **Found while testing:** AutoHotkey's `FileOpen` skips a UTF-8 BOM, so a file starting with one was
  hashed without it and failed the check. The hash now rewinds to the first byte (and a test covers it).
- **Trap:** a `for` loop's own variable is not visible inside a `() =>` closure in AutoHotkey 2.0 — the
  swap code copies it into a normal variable first.

## Removed on purpose

- **The setting that hid the speaker button.** The button is always there now; a switch to hide one
  small icon was one setting too many.
- **The word list's "lock"**, which switched off dragging and resizing. The gear to Settings took its
  place.

## Keys

- **A custom recorder,** because AutoHotkey's Hotkey control cannot record the
  Win key or mouse buttons, which most of the keys use.
- **Character keys are stored by position** (`vkC0` for the key left of 1), so
  they keep working when the keyboard is switched to Persian.

## Windows and placement

- **The popup:** below or above the text when there is room, else beside it,
  else over its middle. With only below/above, a block that filled the screen
  pushed the popup off the edge.
- **Exclusive-fullscreen games** cannot show any other window — the popup, the
  box, even Windows' notifications. Overlays like Discord's inject into the
  game, which anti-cheat treats like a cheat. Not done, on purpose; borderless
  fullscreen works.
- **The icon** used to be set by full path (`C:\Users\…\Pictures\…`). On
  anyone else's PC that path does not exist and the default icon showed. The
  icon now sits next to the script.
- **Administrator** was always requested at start; since 1.0.0 it is an option
  (the selection key needs it only for programs that run as administrator).

## Open questions

- **"skipped a step with no address"** was logged once (15 September 2026, for
  "cézannes") although the step held an address. Not reproducible on the same
  word or other accented words. The guard makes it harmless — one source
  skipped instead of a crash.
