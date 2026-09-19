;================================================================================
; Vocab.ahk - look up any English word on screen, keep the ones worth keeping
;================================================================================
; AutoHotkey v2 (2.0 or later). Start it with the v2 AutoHotkey64.exe - the
; portable zip carries one, and "Start Vocab.bat" uses it. A v1 AutoHotkey
; would choke on the first line.
;
; KEYS - the defaults. Any of them can be changed in Settings (tray menu),
; which records the new ones; see Keys.ahk.
;   Win + Click         the word you click on. Works on anything you can
;                       see - a web page, a game, a paused video - because it
;                       reads the screen around the pointer with Windows' own
;                       OCR rather than asking the app for its text. Reads text
;                       of any size, from 8 px labels to full-screen subtitles;
;                       see WordAtPoint for why that takes three attempts.
;                       The click itself never reaches the window underneath.
;   Shift + Win + Click TRANSLATE: the text under the mouse - up to ten
;                       sentences, ending at any line that ends with a stop -
;                       in plain English and in Persian. A selection of more
;                       than a few words goes here too. See Sentence.ahk
;   Ctrl + Win + Click  SUMMARY: the whole block of text under the mouse,
;                       summarised in both languages - a game note, a blog
;                       paragraph. The screen is read whole and the block is
;                       outlined for a moment so you can see what was taken.
;                       See Paragraph.ahk
;                       Both cards have TRANSLATE | SUMMARY at the top: the
;                       other one redoes the same text the other way, for when
;                       the guess by length was wrong. Switching back is free.
;   Win + `             the selected text instead (copied with Ctrl+C); with
;                       nothing selected it falls back to the word under the
;                       mouse
;   Shift + Win + `     draw a box over any text and let go: only what is
;                       inside is read, and sent where it fits by its length,
;                       like the selection. See Box.ahk
;   Win + F7            the dictionary window, open or closed
;   Esc                 closes the lookup popup, while one is showing
;
; THE POPUP
;   The speaker beside the word says it out loud; "look up again" runs the
;   whole lookup once more, for when Gemini or a dictionary did not answer.
;   If the screen was misread - a player's highlight box cutting the first and
;   last letter, say - Gemini says what the word really was and the lookup
;   starts over on the right one, with "read as ..." showing what it saw.
;   Appears next to the word without taking focus, so a game or player keeps
;   its keyboard. It stays until you click somewhere outside it (or press Esc),
;   so moving the mouse around never loses it. Its size is settled once, when
;   it opens: after that it scrolls with the wheel rather than growing, so
;   "+ N more" never makes it jump. Sections:
;     IN THIS SENTENCE  the sentence the word was in (cut at its full stops,
;                       tidied by Gemini once it answers), then Gemini's
;                       reading of the word there, with the Persian for THAT
;                       meaning (only with a key)
;     PERSIAN           the translation, plus alternatives per part of speech
;     DEFINITIONS       one line from each dictionary entry, so a word with two
;                       unrelated meanings shows both; "+ N more" opens the rest
;   The green dot marks the meaning that will be saved - Gemini's when there is
;   one, otherwise the first definition. Click any other definition to pick it
;   instead. "+ save" keeps the word, that meaning, the Persian that goes with
;   it, and the sentence you found it in.
;
; THE DICTIONARY WINDOW
;   An ordinary window with a taskbar button, not always on top. Drag it by
;   the top strip, resize it from any edge or corner; drag the gap between the
;   list and the pane below to share the height differently. "lock" pins all
;   three. The dash minimizes to the taskbar, the cross hides to the tray.
;   Typing in the search box filters your words; Enter looks the text up
;   online instead and shows the answer in the pane with its own "+ save".
;   Clicking a saved word shows everything kept for it - from the saved copy,
;   no network - and the green dot works there too: click another definition
;   and that becomes the word's saved meaning.
;
; GEMINI - optional, free. Tray menu > Settings: paste a key, "test" checks it.
;   Without one, everything above still works from the free dictionaries;
;   the cards that need it say so, with a link to the key box.
;
; THE CODE
;   This file only starts things. Everything else is in lib\ - lib\All.ahk
;   lists each part and what it does. tests\ checks them (run-tests.ps1),
;   tools\ has a helper for looking at what the OCR sees, and
;   docs\decisions.md explains why things are the way they are.
;
; FILES Vocab makes, all next to this script
;   Vocab.ini     settings, the Gemini key, where the window was
;   words.json    your dictionary - plain, readable JSON. Each word already
;                 carries a "review" block (box, due, history) that nothing
;                 reads yet: it is there for a Leitner-box review mode later
;   cache\        every definition and translation fetched, one file per word,
;                 and the pronunciations in cache\audio-us
;   errors.log    anything that went wrong, instead of a dialog in your face;
;                 trimmed at start once it passes 200 KB
;================================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#Include %A_LineFile%\..\lib\All.ahk

; Administrator is optional (Settings > GENERAL, off unless chosen). Without
; it, one thing does not work: the selection key cannot copy from a program
; that itself runs as administrator, because Windows does not let a normal
; program send keys to an elevated one. Everything else - reading the screen
; included - works the same. If the Windows prompt is declined, Vocab simply
; carries on without it.
if (!A_IsAdmin && IniRead(VocabIni(), "General", "RunAsAdmin", 0) = 1) {
    try {
        Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
        ExitApp
    }
}

;================================================================================
; Start-up
;================================================================================
CoordMode("Mouse", "Screen")    ; every thread inherits this
EnsureIni()
TrimLog()
LoadSoundSettings()
Store.Load()
SetTimer(() => PronFill.Start(), -5000)
SetScriptIcon()
Keys.Start()
BuildTray()
NoKeyNotice()
OnMessage(0x83, DictNcCalc)             ; WM_NCCALCSIZE
OnMessage(0x84, DictHitTest)            ; WM_NCHITTEST
OnMessage(0x86, DictNcActivate)         ; WM_NCACTIVATE
OnMessage(0x201, DictMouseDown)         ; WM_LBUTTONDOWN - the divider
OnMessage(0x20A, PaneWheel)             ; WM_MOUSEWHEEL
OnMessage(0x20, OnSetCursor)            ; WM_SETCURSOR
OnMessage(0x232, DictMoved)             ; WM_EXITSIZEMOVE
OnExit((*) => Dict.SavePos())

; While the popup is up, a click anywhere outside it closes it. The "~" lets
; the click through untouched, so it still does whatever it was for.
#HotIf Popup.visible
Esc::Popup.Close()
~LButton::
~RButton::
~MButton::Popup.ClickAway()
#HotIf

