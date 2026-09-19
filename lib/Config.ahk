;================================================================================
; Config.ahk - what is set in the script rather than in Settings
;================================================================================
#Requires AutoHotkey v2.0

; The name it shows, and the version - for the tray tip, the settings window,
; the notices and the update check. The files keep the short name Vocab.
global AppName := "TLDR Vocab"
global RepoUrl := "https://github.com/HamedPhixer/TLDR-Vocab"     ; the README and the releases
global VocabVersion := "1.1.0-beta.2"      ; MAJOR.MINOR.PATCH - see "Releasing" in README.md

; The Gemini key, the proxy, the sound and the keys are set in the settings
; window (tray menu > Settings, see Settings.ahk), which keeps them in
; Vocab.ini. What is below is the rest, set here in the code.
;
; The keys are in Keys.ahk. The default clicks swallow the click only
; while Win is held, so an ordinary click is never touched. Windows Terminal
; can claim Win+` for its drop-down window; whichever of the two sees the key
; first wins.

; Icon for the tray AND the dictionary window's taskbar button. Leave it ""
; for AutoHotkey's own.
;
; A plain file name means a file next to Vocab.ahk - the way to do it, so the
; icon travels with the folder. A full path only exists on the PC it was typed
; on (docs\decisions.md).
;     global IconFile := "dictionary.png"          next to Vocab.ahk
;     global IconFile := "C:\Windows\System32\imageres.dll"
;     global IconNum  := 100                        a Windows icon, by number
; A missing or unusable file just gets a tray notice - the script runs anyway.
global IconFile := "dictionary.png"
global IconNum  := 1

; The colours: a dark palette, used by every window and card
global CBg := "181B24", CCard := "202430", CCardHi := "2A3040", CTrack := "2A2F40"
global CText := "EBEEF5", CMuted := "8C94AA", CDim := "5F677D"
global CGreen := "00E676", CAmber := "FFB300", CRed := "FF4D6D", CBlue := "3D9BE9"
global FontUI := "Segoe UI"
global FontFa := "Segoe UI"     ; has full Persian coverage; "Tahoma" also works

; Hearing the word: the speaker on every card, and - when Settings > SOUND says
; so (kept in Vocab.ini) - each word said out loud as it is looked up. A
; recording from Google's free endpoint, kept in cache\audio-us afterwards, or
; the Windows voice offline - see the top of Speak.ahk. This is the default.
global SpeakAuto := 0           ; 1 = say every word as you look it up

global PopW    := 400           ; popup width
global PopWide := 520           ; and for a paragraph summary, which is wider
global PopMaxH := 560           ; the tallest the popup gets before it scrolls
global LinkHwnds := Map()       ; clickable texts, for the hand cursor
global NoticeClick := ""        ; what clicking the latest tray notice does (Notice, App.ahk)
