# TLDR Vocab

**Point at any English text on your screen and understand it — in plain English and in Persian.**

A word in a game, a line of dialogue in a paused video, a paragraph in a blog: press a key, and a
small card appears beside it with the meaning, the pronunciation, and the Persian. It reads the
screen itself (Windows' own OCR), so it works on anything you can see — not only on text you can
select.

For Windows 10 and 11. English → Persian.

## Download

From the [latest release](https://github.com/HamedPhixer/TLDR-Vocab/releases/latest):

| File | For |
|---|---|
| `TLDR-Vocab-x.y.z-portable.zip` | **Most people.** Nothing to install: unzip anywhere, double-click `Start TLDR Vocab.bat`. |
| `TLDR-Vocab-x.y.z.zip` | If you already have [AutoHotkey v2](https://www.autohotkey.com/) installed: unzip, double-click `Vocab.ahk`. |

A dictionary icon appears in the tray. Right-click it for Settings.

## The keys

All of them can be changed — or switched off — in Settings.

| Keys | What it does |
|---|---|
| **Win + Click** | The word you click on: meaning, pronunciation, Persian, and the meaning that fits the sentence it is in. The click never reaches the window underneath. |
| **Shift + Win + Click** | **Translate**: the text you click on, explained in plain English and translated. A line that ends with `. ! ? : ;` ends it; up to ten sentences are taken. |
| **Ctrl + Win + Click** | **Summary**: the whole block of text under the mouse, summarised in both languages — a game note, a blog post. |
| **Win + `** | Whatever text is selected (\` is the key left of 1). |
| **Shift + Win + `** | Draw a box: the screen dims, drag a rectangle over the text, let go. Only what is inside is read. |
| **Win + F7** | Your saved word list. |
| **Esc** | Closes the card. A click outside it does too. |

The selection and the box pick the card by length: a few words get the dictionary, a sentence or so
gets Translate, anything longer gets Summary. Wrong guess? Click **TRANSLATE | SUMMARY** at the top
of the card to redo the same text the other way.

## Gemini (optional, free)

Without a key, word lookups, Persian and pronunciation all work. With a free Gemini key you also get
sentences explained in plain English, summaries, and the meaning of a word that fits where you
found it.

1. Right-click the tray icon → **Settings**
2. Click **get a free key** — sign in with Google, press *Create API key*
3. Paste it into the Key box and click **test**

Your key stays in `Vocab.ini` on your PC. It is never part of this repository or its downloads.

## Where the answers come from

- **Definitions:** [freedictionaryapi.com](https://freedictionaryapi.com), Wiktionary, Datamuse
- **Persian and the spoken words:** Google Translate's free web addresses, with Lingva and MyMemory
  as fallbacks. These are the addresses Google's own website uses, not an official service: they
  work, but could change or be blocked at any time — the fallbacks, and the Windows voice, then take
  over.
- **Explanations and summaries:** Gemini, with your key

## Files it makes, all in its own folder

| File | What |
|---|---|
| `Vocab.ini` | your settings and Gemini key |
| `words.json` | the words you save — plain, readable JSON |
| `cache\` | definitions and pronunciations, so a repeat is instant |
| `errors.log` | only if something goes wrong |

To remove it: quit from the tray icon and delete the folder.

## Known limits

- **Exclusive-fullscreen games** can't show the card or the box — Windows draws nothing over them.
  Use the game's *borderless* or *windowed fullscreen* mode.
- **Translate** takes text by its punctuation. A line without any runs on into the next one; for an
  exact piece of text, draw a box.
- The screen reading is English only.

## For developers

```
Vocab.ahk        starts everything
lib\             the app - lib\All.ahk lists what each file does
tests\           run-tests.ps1: syntax check, logic tests, screen tests
tools\           OcrDebug.ahk - see what the OCR sees
docs\            decisions.md - why things are the way they are
build.ps1        builds both zips into dist\
```

Written for AutoHotkey v2.0. `.\tests\run-tests.ps1` before a release; `.\build.ps1` to build the
zips locally. Pushing a tag `vX.Y.Z` (matching `VocabVersion` in `lib\Config.ahk`) makes GitHub build
both zips and publish the release.

## Credits

Design and direction: **HamedPhixer**. Code written with Claude (Anthropic), via Claude Code.

The portable download includes [AutoHotkey](https://www.autohotkey.com/) 2.0, free software under
the GNU GPL v2 — see `AutoHotkey license.txt` in that zip, and its source at
[github.com/AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey).

## License

[MIT](LICENSE) © 2026 HamedPhixer
