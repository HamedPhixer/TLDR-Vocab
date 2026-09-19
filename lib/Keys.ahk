;================================================================================
; Keys.ahk - the keys, and the window that changes them
;================================================================================
; Tray menu > Settings, KEYS. Click "change" beside an action and press the new
; keys: hold Ctrl, Alt, Shift or Win and press a key, or click a mouse button.
; It is checked, used straight away, and kept in Vocab.ini under [Keys]. Only
; keys that differ from the default are written there, so "default" simply
; deletes the line. "off" leaves an action with no key at all (written as
; "none"), for someone who never uses it.
;
; HOW THE RECORDING WORKS
; AutoHotkey's own Hotkey box cannot record the Win key or a mouse click, and
; most of these keys are both. So while one row is recording:
;   the keyboard    an InputHook catches every key and blocks it - the Win key
;                   too, so pressing it does not open the Start menu. The key
;                   that is not a modifier ends the recording; the modifiers
;                   held at that moment are read from their physical state.
;   the mouse       five temporary hotkeys (*LButton ... *XButton2), live only
;                   while a modifier is held, so the plain click on "change"
;                   and any other ordinary click go through untouched.
;   Vocab's keys    are switched off, so pressing the current Win + F7 records
;                   it instead of opening the word list.
; Everything is switched back once the modifiers are let go - letting go of
; Win with its hotkey already live again could still trip the Start menu.
;
; WHAT IS REFUSED, AND WHAT ONLY GETS A WARNING
;   refused   a key on its own that is needed for typing or clicking (a letter,
;             Space, Enter, a plain click); the same with only Shift, which is
;             just a capital letter or a Shift-click; keys Windows keeps for
;             itself (Win + L, Alt + Tab, Alt + F4, Ctrl + Alt + Del,
;             Ctrl + Shift + Esc); Ctrl + A, C, V, X, Y or Z, which every
;             program needs; and a key another action already has
;   warned    a key on its own that is not for typing (F9, a mouse side
;             button); anything with Ctrl or Alt that programs may use; Win
;             with a key Windows may use. These work - Vocab just takes them
;             over while it runs, and the window says so
;
; Character keys are stored by key position (vkC0 is the key left of 1), not
; by the character, so they keep working when the keyboard is switched to
; Persian. The window shows them as the English character.
;================================================================================
#Requires AutoHotkey v2.0

class Keys {
    ; id is the line's name in Vocab.ini [Keys]; short is for the tray tip
    static List := [
        {id: "Word",      name: "Look up a word",          short: "word",      def: "#LButton",  fn: LookupUnderMouse},
        {id: "Translate", name: "Translate a passage",     short: "translate", def: "+#LButton", fn: LookupSentenceUnderMouse},
        {id: "Summary",   name: "Summarise a block",       short: "summary",   def: "^#LButton", fn: LookupParagraphUnderMouse},
        {id: "Selection", name: "Look up selected text",   short: "selection", def: "#vkC0",     fn: LookupSelection},
        {id: "Box",       name: "Draw a box to read",      short: "box",       def: "+#vkC0",    fn: LookupBox},
        {id: "WordList",  name: "Open the word list",      short: "word list", def: "#F7",       fn: (*) => Dict.Toggle()}
    ]
    static cur := Map()             ; id -> the hotkey in use now ("" = none)

    ; Registers every action's key: the one in Vocab.ini when it is still
    ; usable, the default otherwise. A hand-edited line that does not work is
    ; logged and reported once, and the default takes over.
    static Start() {
        bad := []
        for a in Keys.List
            Keys.cur[a.id] := ""
        for a in Keys.List {
            hk := Trim(IniRead(VocabIni(), "Keys", a.id, ""))
            if (hk = "none")                    ; switched off in Settings
                continue
            if (hk != "") {
                c := Keys.Check(hk, a.id)
                if (c.err != "" || !Keys.On(hk, a)) {
                    VocabLog("Keys: " a.id "=" hk " in Vocab.ini is not usable ("
                        . (c.err != "" ? c.err : "AutoHotkey refused it") "), using the default")
                    bad.Push(a.name)
                    hk := ""
                }
            }
            if (hk = "") {
                hk := a.def
                if (Keys.Check(hk, a.id).err != "" || !Keys.On(hk, a)) {
                    VocabLog("Keys: the default " hk " for " a.id " is taken, so it has no key")
                    bad.Push(a.name)
                    hk := ""
                }
            }
            Keys.cur[a.id] := hk
        }
        if bad.Length
            TrayTip("Some keys in Vocab.ini could not be used:`n" Join(bad, ", ")
                . "`nTray menu > Settings", AppName, 2)
    }

    static Find(id) {
        for a in Keys.List
            if (a.id = id)
                return a
    }

    static On(hk, a) {
        HotIf()
        try {
            Hotkey(hk, a.fn, "On")
            return true
        }
        return false
    }

    static Off(hk) {
        HotIf()
        if (hk != "")
            try Hotkey(hk, "Off")
    }

    static AllOff() {
        for a in Keys.List
            Keys.Off(Keys.cur[a.id])
    }

    static AllOn() {
        for a in Keys.List
            if (Keys.cur[a.id] != "")
                Keys.On(Keys.cur[a.id], a)
    }

    ; Gives an action a new key and keeps it. live = the keys are switched on
    ; right now (false while recording, when they are all off anyway).
    ; Returns "" or why AutoHotkey would not take it.
    static Set(id, hk, live := true) {
        a := Keys.Find(id)
        old := Keys.cur[id]
        if (hk = "") {                      ; off: no key at all, kept as "none"
            if live
                Keys.Off(old)
            Keys.cur[id] := ""
            try IniWrite("none", VocabIni(), "Keys", id)
            BuildTray()
            return ""
        }
        HotIf()
        try Hotkey(hk, a.fn, "Off")         ; only proves AutoHotkey accepts the name
        catch
            return "AutoHotkey does not accept " Keys.Label(hk)
        if live {
            Keys.Off(old)
            if !Keys.On(hk, a) {
                Keys.On(old, a)
                return "AutoHotkey does not accept " Keys.Label(hk)
            }
        }
        Keys.cur[id] := hk
        try {
            if (hk = a.def)
                IniDelete(VocabIni(), "Keys", id)
            else
                IniWrite(hk, VocabIni(), "Keys", id)
        }
        BuildTray()
        return ""
    }

    ;----------------------------------------------------------------------------
    ; Reading a hotkey
    ;----------------------------------------------------------------------------
    ; mods in a fixed order, the key, and a same-key test that ignores how it
    ; was written: "#``" and "#vkC0" are the same key.
    static Parse(hk) {
        if !RegExMatch(hk, "^([~*$<>^!+#]*)(.+)$", &m)
            return {mods: "", key: "", vk: 0, sc: 0, same: ""}
        p := m[1], key := m[2]
        mods := (InStr(p, "^") ? "^" : "") (InStr(p, "!") ? "!" : "")
            . (InStr(p, "+") ? "+" : "") (InStr(p, "#") ? "#" : "")
        vk := 0, sc := 0
        if !InStr(key, " & ")
            try vk := GetKeyVK(key), sc := GetKeySC(key)
        return {mods: mods, key: key, vk: vk, sc: sc, same: mods "|" ((vk || sc) ? vk "|" sc : StrLower(key))}
    }

    static IsModifier(vk) => (vk >= 0x10 && vk <= 0x12) || (vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C

    ; Keys that type something or move the caret, and the two main clicks:
    ; on their own they are what everyone uses all day.
    static IsTyping(vk) {
        return (vk >= 0x30 && vk <= 0x5A) || (vk >= 0x60 && vk <= 0x6F) || (vk >= 0xBA && vk <= 0xC0)
            || (vk >= 0xDB && vk <= 0xDF) || vk = 0xE2 || (vk >= 0x20 && vk <= 0x28) || vk = 0x2E
            || vk = 0x0D || vk = 0x09 || vk = 0x08 || vk = 0x1B || vk = 0x01 || vk = 0x02
    }

    static IsMouse(vk) => (vk >= 0x01 && vk <= 0x06 && vk != 0x03)

    ; The name to store for a key pressed while recording. Character keys go
    ; by position (vkXX) so a Persian keyboard layout does not change them.
    static KeyName(vk, sc) {
        if ((vk >= 0x30 && vk <= 0x39) || (vk >= 0x41 && vk <= 0x5A)
            || (vk >= 0xBA && vk <= 0xC0) || (vk >= 0xDB && vk <= 0xDF) || vk = 0xE2)
            return Format("vk{:X}", vk)
        n := sc ? GetKeyName(Format("sc{:X}", sc)) : ""
        if (n = "")
            n := GetKeyName(Format("vk{:X}", vk))
        return (n != "") ? n : Format("vk{:X}sc{:X}", vk, sc)
    }

    ; "+#LButton" -> "Shift + Win + Click"; tight drops the spaces
    static Label(hk, tight := false) {
        if (hk = "")
            return "none"
        p := Keys.Parse(hk)
        parts := []
        for m in [["^", "Ctrl"], ["!", "Alt"], ["+", "Shift"], ["#", "Win"]]
            if InStr(p.mods, m[1])
                parts.Push(m[2])
        parts.Push(Keys.KeyText(p.key, p.vk))
        return Join(parts, tight ? "+" : " + ")
    }

    static KeyText(key, vk) {
        static mouse := Map("lbutton", "Click", "rbutton", "Right-click", "mbutton", "Middle-click"
            , "xbutton1", "Mouse back", "xbutton2", "Mouse forward")
        static oem := Map(0xBA, ";", 0xBB, "=", 0xBC, ",", 0xBD, "-", 0xBE, ".", 0xBF, "/"
            , 0xC0, "``", 0xDB, "[", 0xDC, "\", 0xDD, "]", 0xDE, "'", 0xE2, "\")
        if mouse.Has(StrLower(key))
            return mouse[StrLower(key)]
        if ((vk >= 0x30 && vk <= 0x39) || (vk >= 0x41 && vk <= 0x5A))
            return Chr(vk)
        if oem.Has(vk)
            return oem[vk]
        n := ""
        try n := GetKeyName(key)
        n := (n != "") ? n : key
        return StrUpper(SubStr(n, 1, 1)) SubStr(n, 2)
    }

    ;----------------------------------------------------------------------------
    ; Is it a good key?
    ;----------------------------------------------------------------------------
    ; {err: why it is refused, warn: what to know} - both "" when all is well
    static Check(hk, id) {
        p := Keys.Parse(hk)
        lbl := Keys.Label(hk)
        if (p.key = "")
            return {err: "that is not a key", warn: ""}
        if (!(p.vk || p.sc) && !InStr(p.key, " & "))
            return {err: p.key " is not a key AutoHotkey knows", warn: ""}
        strong := RegExMatch(p.mods, "[\^!#]")
        if (!strong && Keys.IsTyping(p.vk))
            return {err: (p.mods = "+")
                ? lbl " is just typing (or Shift-clicking). Hold Ctrl, Alt or Win as well."
                : lbl " on its own is needed for typing and clicking. Hold Ctrl, Alt or Win with it.", warn: ""}
        if (p.mods = "#" && p.vk = 0x4C)
            return {err: "Windows locks the PC on Win + L before any program sees it.", warn: ""}
        if ((p.mods = "!" || p.mods = "!+") && p.vk = 0x09)
            return {err: "Alt + Tab switches windows - Windows keeps it.", warn: ""}
        if (p.mods = "!" && p.vk = 0x73)
            return {err: "Alt + F4 closes windows - taking it would be a trap.", warn: ""}
        if ((p.mods = "^!" && p.vk = 0x2E) || (p.mods = "^+" && p.vk = 0x1B))
            return {err: lbl " belongs to Windows.", warn: ""}
        if (p.mods = "^" && p.vk >= 0x41 && p.vk <= 0x5A && InStr("ACVXYZ", Chr(p.vk), true))
            return {err: lbl " is copy, paste or undo in every program - and the selection key sends Ctrl + C itself.", warn: ""}
        for a in Keys.List
            if (a.id != id && Keys.cur.Has(a.id) && Keys.cur[a.id] != ""
                && Keys.Parse(Keys.cur[a.id]).same = p.same)
                return {err: lbl " is already the key for " a.name ".", warn: ""}

        warn := ""
        if (p.mods = "")
            warn := "On its own, " lbl " stops doing its usual job everywhere while " AppName " runs."
        else if InStr(p.mods, "#") {
            if (!Keys.IsMouse(p.vk) && !(p.vk >= 0x70 && p.vk <= 0x87))       ; F1-F24 with Win are free
                warn := "Windows may use " lbl " for something of its own. " AppName " takes it over while it runs."
        } else
            warn := "Programs may use " lbl " themselves. While " AppName " runs, it does this instead."
        return {err: "", warn: warn}
    }

    static ModsDown() {
        return (GetKeyState("Ctrl", "P") ? "^" : "") (GetKeyState("Alt", "P") ? "!" : "")
            . (GetKeyState("Shift", "P") ? "+" : "")
            . ((GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) ? "#" : "")
    }

    static TrayText() {
        lines := ""
        for a in Keys.List
            if (Keys.cur.Has(a.id) && Keys.cur[a.id] != "")
                lines .= "`n" Keys.Label(Keys.cur[a.id], true) " " a.short
        ; a tray tip holds 127 characters: the keys come first, the version
        ; only if there is room, and past that whole lines are dropped
        tip := AppName " " VocabVersion lines
        if (StrLen(tip) <= 127)
            return tip
        tip := AppName lines
        while (StrLen(tip) > 127)
            tip := SubStr(tip, 1, InStr(tip, "`n", , -1) - 1)
        return tip
    }
}

;================================================================================
; The KEYS section of the settings window (Settings.ahk builds the window)
;================================================================================
class KeysWin {
    static rows := Map(), status := "", ih := "", rec := "", waiting := false
    static mouseOn := false, mouseCond := "", mouseFn := "", releaser := ""

    ; adds the rows to g from y down; returns the y below them
    static AddTo(g, y) {
        g.SetFont("s9 Norm c" CMuted, FontUI)
        g.Add("Text", "x22 y" y " w556 BackgroundTrans +0x80"
            , "Click change, then press the new keys: hold Ctrl, Alt, Shift or Win and press a key "
            . "or click a mouse button. It works straight away. Esc cancels.")
        y += 44
        for a in Keys.List {
            g.SetFont("s10 Norm c" CText, FontUI)
            g.Add("Text", "x22 y" (y + 7) " w190 BackgroundTrans +0x80", a.name)
            g.SetFont("s10 Bold c" CText, FontUI)
            k := g.Add("Text", "x214 y" y " w200 h32 Center +0x200 +0x80 Background" CCardHi, "")
            g.SetFont("s9 Norm c" CBlue, FontUI)
            ch := Link(g.Add("Text", "x428 y" (y + 8) " w50 BackgroundTrans +0x80", "change")
                , ObjBindMethod(KeysWin, "Record", a))
            g.SetFont("s9 Norm c" CDim, FontUI)
            off := Link(g.Add("Text", "x482 y" (y + 8) " w26 BackgroundTrans +0x80", "off")
                , ObjBindMethod(KeysWin, "TurnOff", a))
            df := Link(g.Add("Text", "x514 y" (y + 8) " w60 BackgroundTrans +0x80", "default")
                , ObjBindMethod(KeysWin, "Default", a))
            this.rows[a.id] := {key: k, change: ch, off: off, def: df}
            y += 42
        }
        g.SetFont("s9 Norm c" CMuted, FontUI)
        this.status := g.Add("Text", "x22 y" (y + 4) " w556 h40 BackgroundTrans +0x80", "")
        return y + 48
    }

    static Refresh() {
        for a in Keys.List {
            r := this.rows[a.id]
            r.key.Opt("+Background" CCardHi)
            r.key.SetFont("c" CText)
            if (Keys.cur[a.id] = "") {
                r.key.SetFont("c" CDim)
                r.key.Text := "off"
            } else
                r.key.Text := Keys.Label(Keys.cur[a.id])
            r.off.Visible := (Keys.cur[a.id] != "")
            r.def.Visible := (Keys.cur[a.id] != a.def)
        }
    }

    ; no key at all for this action - for someone who never uses it
    static TurnOff(a, *) {
        if this.rec
            this.Cancel("")
        Keys.Set(a.id, "")
        this.Refresh()
        this.Say(a.name ": off. " Chr(0x201C) "change" Chr(0x201D) " or " Chr(0x201C) "default" Chr(0x201D)
            . " brings it back.", CMuted)
    }

    static Say(msg, color := "") {
        this.status.SetFont("c" (color != "" ? color : CMuted))
        this.status.Text := msg
    }

    ; the window is closing: a recording in progress is dropped
    static Stop() {
        if this.rec
            this.Cancel("")
        this.Say("")
    }

    static Default(a, *) {
        if this.rec
            this.Cancel("")
        c := Keys.Check(a.def, a.id)
        if (c.err != "") {
            this.Say("The default is not free: " c.err, CRed)
            return
        }
        err := Keys.Set(a.id, a.def)
        this.Refresh()
        if (err != "")
            this.Say(err, CRed)
        else
            this.Say(a.name ": back to " Keys.Label(a.def) ".", CGreen)
    }

    ;----------------------------------------------------------------------------
    ; Recording
    ;----------------------------------------------------------------------------
    static Record(a, *) {
        if this.waiting                     ; still waiting for the last one's keys to come up
            return
        if this.rec
            this.Cancel("")
        this.Refresh()
        this.rec := a
        r := this.rows[a.id]
        r.key.Opt("+Background" CTrack)
        r.key.SetFont("c" CBlue)
        r.key.Text := "press the keys" Chr(0x2026)
        this.Say("Recording " a.name ". Esc cancels.", CBlue)

        Keys.AllOff()
        ih := InputHook("L0 T15")           ; collects no text; gives up after 15 s
        ih.VisibleNonText := false
        ih.KeyOpt("{All}", "NS")            ; tell us about every key, and block it
        ih.OnKeyDown := ObjBindMethod(KeysWin, "KeyDown")
        ih.OnKeyUp := ObjBindMethod(KeysWin, "KeyUp")
        ih.OnEnd := ObjBindMethod(KeysWin, "Ended")
        this.held := Map()
        this.ih := ih
        ih.Start()
        this.Mouse(true)
    }

    ; The modifiers held right now: as seen by this hook, or physically down.
    ; Both, because Windows marks keys from remote desktop or an on-screen
    ; keyboard as not physical, and a modifier pressed before recording
    ; started never came past the hook.
    static Mods() {
        m := Keys.ModsDown()
        for vk, sym in Map(0x11, "^", 0xA2, "^", 0xA3, "^", 0x12, "!", 0xA4, "!", 0xA5, "!"
                , 0x10, "+", 0xA0, "+", 0xA1, "+", 0x5B, "#", 0x5C, "#")
            if (this.held.Has(vk) && !InStr(m, sym))
                m .= sym
        return (InStr(m, "^") ? "^" : "") (InStr(m, "!") ? "!" : "") (InStr(m, "+") ? "+" : "") (InStr(m, "#") ? "#" : "")
    }

    static held := Map()

    static KeyUp(ih, vk, sc) {
        if this.held.Has(vk)
            this.held.Delete(vk)
    }

    static KeyDown(ih, vk, sc) {
        if Keys.IsModifier(vk)
            this.held[vk] := true
        if (!this.rec || this.waiting || Keys.IsModifier(vk))
            return
        mods := this.Mods()
        if (vk = 0x1B && mods = "") {
            this.Cancel("Nothing changed.")
            return
        }
        this.Got(mods Keys.KeyName(vk, sc))
    }

    ; the temporary mouse hotkeys: live only while recording and while a
    ; modifier is held (or for the middle and side buttons, which are fine alone)
    static Mouse(on) {
        if !this.mouseCond {
            this.mouseCond := (hk) => KeysWin.rec && !KeysWin.waiting
                && (KeysWin.Mods() != "" || !RegExMatch(hk, "i)[LR]Button$"))
            this.mouseFn := ObjBindMethod(KeysWin, "Clicked")
        }
        if (on = this.mouseOn)
            return
        HotIf(this.mouseCond)
        for b in ["*LButton", "*RButton", "*MButton", "*XButton1", "*XButton2"]
            try Hotkey(b, this.mouseFn, on ? "On" : "Off")
        HotIf()
        this.mouseOn := on
    }

    static Clicked(hk) {
        this.Got(this.Mods() SubStr(hk, 2))
    }

    static Got(hk) {
        a := this.rec
        c := Keys.Check(hk, a.id)
        if (c.err != "") {
            this.Finish()
            this.Say("Not changed. " c.err, CRed)
            return
        }
        if (Keys.Parse(hk).same = Keys.Parse(Keys.cur[a.id]).same) {
            this.Finish()
            this.Say(a.name " already uses " Keys.Label(hk) ".", CMuted)
            return
        }
        err := Keys.Set(a.id, hk, false)
        this.Finish()
        if (err != "")
            this.Say("Not changed. " err, CRed)
        else
            this.Say(a.name ": " Keys.Label(hk) " - works now." (c.warn != "" ? "`n" c.warn : "")
                , (c.warn != "") ? CAmber : CGreen)
    }

    static Cancel(msg) {
        this.Finish()
        if (msg != "")
            this.Say(msg, CMuted)
    }

    ; Stop listening, but keep blocking keys until every modifier is up, then
    ; switch Vocab's keys back on.
    static Finish() {
        this.Mouse(false)
        this.rec := ""
        this.Refresh()
        this.waiting := true
        if !this.releaser
            this.releaser := ObjBindMethod(KeysWin, "Release")
        this.releaseBy := A_TickCount + 3000
        SetTimer(this.releaser, 30)
    }

    static releaseBy := 0

    static Release() {
        if (this.Mods() != "" && A_TickCount < this.releaseBy)
            return
        SetTimer(this.releaser, 0)
        if this.ih {
            ih := this.ih
            this.ih := ""
            ih.Stop()
        }
        Keys.AllOn()
        this.waiting := false
    }

    static Ended(ih) {
        if (ih.EndReason = "Timeout" && this.rec)
            this.Cancel("Nothing was pressed, so nothing changed.")
    }
}
