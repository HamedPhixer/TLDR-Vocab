;================================================================================
; App.ahk - the ini, the icon, the tray, and starting a lookup
;================================================================================
#Requires AutoHotkey v2.0

EnsureIni() {
    if FileExist(VocabIni())
        return
    FileAppend("
    (
[Gemini]
; Easiest from the tray menu: Settings. Everything in this file is there.
; Optional, free: Gemini explains sentences in plain English, writes the
; summaries, and picks the meaning of a word that fits the sentence. Without
; it the dictionary, the Persian and the pronunciation all still work.
; Get a key at https://aistudio.google.com/apikey (sign in with Google,
; Create API key) and paste it after the = , or in Settings.
ApiKey=
; Leave empty to use the newest free Flash model automatically.
Model=

[Network]
; auto = follow the Windows proxy when one is switched on (a VPN app in
; "system proxy" mode, for example). Or name one: 127.0.0.1:10809
; none = always connect directly.
Proxy=auto

[Window]
Locked=0

[Sound]
Speaker=1
SayOnLookup=0

[General]
; 1 = start as administrator (Windows asks each time), so the selection key
; can copy from programs that run as administrator. Applies from next start.
RunAsAdmin=0

[Keys]
; Set in Settings. Only keys that differ from the default are listed;
; delete a line to go back to the default.
    )", VocabIni())
}

; IconFile as a full path: a bare name, or anything not starting at a drive
; letter or a network share, is taken to sit next to this script.
IconPath() {
    if (IconFile = "")
        return ""
    return RegExMatch(IconFile, "^([A-Za-z]:|\\\\)") ? IconFile : A_ScriptDir "\" IconFile
}

SetScriptIcon() {
    path := IconPath()
    if (path = "")
        return
    if !FileExist(path) {
        TrayTip("Icon not found:`n" path, AppName, 2)
        return
    }
    try TraySetIcon(path, IconNum)
    catch
        TrayTip("Not a usable icon file:`n" path, AppName, 2)
}

; The taskbar button takes the window's own icons, which are set separately
; from the tray's. Only real icons (image type 1) are handed over.
SetWindowIcon(hwnd) {
    path := IconPath()
    if (path = "" || !FileExist(path))
        return
    try {
        small := LoadPicture(path, "Icon" IconNum " w16 h16", &t1)
        big   := LoadPicture(path, "Icon" IconNum " w32 h32", &t2)
        if (t1 = 1)
            SendMessage(0x80, 0, small, , hwnd)         ; WM_SETICON, ICON_SMALL
        if (t2 = 1)
            SendMessage(0x80, 1, big, , hwnd)           ; ICON_BIG
    }
}

BuildTray() {
    tm := A_TrayMenu
    tm.Delete()
    tm.Add("Open dictionary", (*) => Dict.Toggle())
    tm.Add()
    tm.Add("Settings", (*) => Settings.Show())
    tm.Add("Open the " AppName " folder", (*) => Run('explorer.exe "' A_ScriptDir '"'))
    tm.Add()
    tm.Add("Reload", (*) => Reload())
    tm.Add("Exit", (*) => ExitApp())
    tm.Default := "Open dictionary"
    A_IconTip := Keys.TrayText()
}

; A view is Popup or Dict: Begin() draws the word at once, Update() redraws as
; each track answers. ocr says the word was read off the screen rather than
; typed or copied, which is the only case where Gemini is allowed to overrule
; it - see Popup.Update().
; reuse = the Translate | Summary switch: a finished lookup of the same text in
; that mode is shown again instead of asked for again (see ModeMemo).
StartLookup(word, context, view, anchor := "", ocr := false, mode := "word", reuse := false) {
    if (SpeakAuto && mode = "word" && StrLen(word) <= 40)
        Speak.Say(word)
    view.Begin(word, context, anchor, ocr, mode)
    lk := reuse ? ModeMemo.Get(word, mode) : ""
    if (lk && lk.Done) {
        view.Attach(lk)
        view.Update(lk)
        return
    }
    lk := Lookup(word, context, ObjBindMethod(view, "Update"), mode)
    if (mode != "word")
        ModeMemo.Put(lk)
    view.Attach(lk)
}

; A correction is only taken if it looks like a word and is not what we already
; have - Gemini echoing the word back, or answering with a sentence, changes
; nothing.
UsableFix(fix, word) {
    fix := Trim(fix)
    return (fix != "" && Lookup.Norm(fix) != Lookup.Norm(word)
        && RegExMatch(fix, "^[A-Za-z][A-Za-z'\- ]{1,40}$") && StrSplit(fix, " ").Length <= 3)
}

