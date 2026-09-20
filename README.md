# TLDR Vocab

**Point at any English text on your screen and understand it — in plain English and in your own language.**

A word in a game, a line of dialogue in a paused video, a paragraph in a blog: press a key, and a
small card appears beside it with the meaning, the pronunciation, and the translation. It reads the
screen itself (Windows' own OCR), so it works on anything you can see — not only on text you can
select.

For Windows 10 and 11. English → Persian by default, or any of 18 other languages (Settings → Translation):
Arabic, Urdu, Turkish, Spanish, French, German, Italian, Portuguese, Dutch, Polish, Russian, Ukrainian,
Hindi, Indonesian, Vietnamese, Chinese, Japanese and Korean.

![A word looked up on a web page: meaning, pronunciation, the meaning that fits the sentence, and the translation](https://raw.githubusercontent.com/HamedPhixer/TLDR-Vocab/main/docs/images/word.png)

## Download

From the [latest release](https://github.com/HamedPhixer/TLDR-Vocab/releases/latest):

| File | For |
|---|---|
| `TLDR-Vocab-x.y.z-portable.zip` | **Most people.** Nothing to install: unzip anywhere, double-click `Start TLDR Vocab.bat`. |
| `TLDR-Vocab-x.y.z.zip` | If you already have [AutoHotkey v2](https://www.autohotkey.com/) installed: unzip, double-click `Vocab.ahk`. |

A dictionary icon appears in the tray. Right-click it for Settings — or click the gear in the word list.

## Updating

Your words, settings and saved lookups are never part of a download, so updating never touches them.

**With one click.** When a new version is out, a notice says so (once a day; Settings → General can switch
that off, or check now). Click it: a window shows what is new. **Update now** downloads the new version,
checks every file against the check sums published with it, closes TLDR Vocab, swaps the files and starts
it again — about ten seconds. If anything goes wrong on the way, nothing is changed; if the new version
does not start, the old one is put back by itself. The version you had is kept in the **previous version**
folder: to go back, copy what is in it over the TLDR Vocab folder.

![The update window: what is new, with Update now, Download page and Not now](https://raw.githubusercontent.com/HamedPhixer/TLDR-Vocab/main/docs/images/update.png)

**By hand**, if you prefer:

1. Right-click the tray icon → **Exit**.
2. Download the new zip (the same kind you have — portable or not) and unzip it **into the same folder**.
   When Windows asks, choose **Replace the files in the destination**.
3. Start TLDR Vocab again.

Updating with one click works from 1.2.0 on. From an older version, update by hand once.

## The keys

All of them can be changed — or switched off — in Settings.

| Keys | What it does |
|---|---|
| **Win + Click** | The word you click on: meaning, pronunciation, translation, and the meaning that fits the sentence it is in. The click never reaches the window underneath. |
| **Shift + Win + Click** | **Translate a passage**: the sentences around the one you click, explained in plain English and translated — up to ten, stopping at a line that ends with `. ! ? : ;`. Or only the sentence you click: Settings → Translation. |
| **Ctrl + Win + Click** | **Summary**: the whole block of text under the mouse, summarised in both languages — a game note, a blog post. |
| **Win + `** | Whatever text is selected (\` is the key left of 1). |
| **Shift + Win + `** | Draw a box: the screen dims, drag a rectangle over the text, let go. Only what is inside is read. |
| **Win + F7** | Your saved word list. |
| **Esc** | Closes the card. A click outside it does too. |

**Translate a passage** — the sentences around the one you click, in plain English and in your language:

![The Translate card: the sentences taken, the same thing in simple English, and the translation](https://raw.githubusercontent.com/HamedPhixer/TLDR-Vocab/main/docs/images/translate.png)

**Summary** — a whole block of text, shortened in both languages:

![The Summary card: a paragraph in simple English, its translation, and what the screen reading actually read](https://raw.githubusercontent.com/HamedPhixer/TLDR-Vocab/main/docs/images/summary.png)

The selection and the box pick the card by length: a few words get the dictionary, a sentence or so
gets Translate, anything longer gets Summary. Wrong guess? Click **TRANSLATE | SUMMARY** at the top
of the card to redo the same text the other way.

**Pin a card** to keep it: the pin at its top right leaves it on screen, where you can drag it anywhere, and
its × closes it. The next lookup opens a new card beside it, so you can keep several at once.

## Your word list

**+ save** on any card keeps the word, the meaning you picked, its translation and the sentence you found
it in. **Win + F7** opens the list: search it, click a word to see everything kept for it, or type a word
and press Enter to look it up online. The gear opens Settings.

![The word list: saved words with their translations, and everything kept for the one picked](https://raw.githubusercontent.com/HamedPhixer/TLDR-Vocab/main/docs/images/wordlist.png)

## Gemini (optional, free)

Without a key, word lookups, translations and pronunciation all work. With a free Gemini key you also get
sentences explained in plain English, summaries, and the meaning of a word that fits where you
found it.

1. Right-click the tray icon → **Settings**
2. Click **get a free key** — sign in with Google, press *Create API key*
3. Paste it into the Key box and click **test**

Your key stays in `Vocab.ini` on your PC. It is never part of this repository or its downloads.

![Settings: the language, the Gemini key, the proxy, and every key shown with a change button](https://raw.githubusercontent.com/HamedPhixer/TLDR-Vocab/main/docs/images/settings.png)

## Where the answers come from

- **Definitions:** [freedictionaryapi.com](https://freedictionaryapi.com), Wiktionary, Datamuse
- **Translations and the spoken words:** Google Translate's free web addresses, with Lingva and MyMemory
  as fallbacks. These are the addresses Google's own website uses, not an official service: they
  work, but could change or be blocked at any time — the fallbacks, and the Windows voice, then take
  over.
- **Explanations and summaries:** Gemini, with your key

Once a day it also asks GitHub whether there is a newer version of TLDR Vocab, and tells you if there
is — nothing is downloaded or changed unless you click **Update now**. Settings → General switches the
check off.

Behind a VPN, the *Proxy* setting follows Windows' own proxy by default. It takes **HTTP** proxies only
(like `127.0.0.1:10809`) — SOCKS proxies do not work.

## Files it makes, all in its own folder

| File | What |
|---|---|
| `Vocab.ini` | your settings and Gemini key |
| `words.json` | the words you save — plain, readable JSON |
| `cache\` | definitions and pronunciations, so a repeat is instant |
| `errors.log` | only if something goes wrong |
| `previous version\` | after an update: the version before it |

To remove it: quit from the tray icon and delete the folder (and the Startup shortcut, if you made one).

## Start with Windows

TLDR Vocab does not start with Windows by itself. To make it:

1. Press **Win + R**, type `shell:startup` and press Enter. The Startup folder opens.
2. In the TLDR Vocab folder, right-click **Start TLDR Vocab.bat** (portable) or **Vocab.ahk** (with AutoHotkey
   installed) and choose **Show more options → Create shortcut**.
3. Move the new shortcut into the Startup folder.

From the next sign-in it starts on its own. To stop that, delete the shortcut from the Startup folder.

*Start as administrator* in Settings is off unless you turn it on. With it on, Windows asks for permission at
every sign-in. It is only needed for the selection key in programs that themselves run as administrator — so
leave it off, or use the way below, which starts it as administrator without asking.

### As administrator, without the prompt

Task Scheduler can start TLDR Vocab as administrator at every sign-in, with no prompt: Windows asks once,
when the task is made. Use this *instead of* the Startup-folder shortcut, not as well.

Start menu → **Task Scheduler** → **Create Task…** (not *Create Basic Task*):

1. **General:** name it *TLDR Vocab*; tick **Run with highest privileges**; keep *Run only when user is logged on*.
2. **Triggers → New:** *Begin the task:* **At log on**, *Specific user:* you.
3. **Actions → New:** *Start a program*.
   - *Program:* `AutoHotkey64.exe` in the TLDR Vocab folder (portable), or
     `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` (AutoHotkey installed)
   - *Add arguments:* the full path of `Vocab.ahk`, in quotes — `"C:\...\TLDR Vocab\Vocab.ahk"`
   - *Start in:* the TLDR Vocab folder, without quotes

   With AutoHotkey installed you can instead put `Vocab.ahk` itself as the *Program* and leave the
   arguments empty: Windows then opens it the way a double-click does. That stops working if `.ahk` files
   are ever set to open in an editor, which naming `AutoHotkey64.exe` never does.
4. **Conditions:** untick **Start the task only if the computer is on AC power** — or a laptop on battery
   never starts it.
5. **Settings:** untick **Stop the task if it runs longer than 3 days** — or Windows closes TLDR Vocab
   after three days.

To undo it: find *TLDR Vocab* in the Task Scheduler Library and delete it.

If you move the TLDR Vocab folder, make the task again: it points at the old place.

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

Written for AutoHotkey v2.0.

## Credits

Design and direction: **HamedPhixer**. Code written with Claude (Anthropic), via Claude Code.

The icon: [Dictionary icons created by Magnific - Flaticon](https://www.flaticon.com/free-icons/dictionary).

The portable download includes [AutoHotkey](https://www.autohotkey.com/) 2.0, free software under
the GNU GPL v2 — see `AutoHotkey license.txt` in that zip, and its source at
[github.com/AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey).

## License

[MIT](LICENSE) © 2026 HamedPhixer
