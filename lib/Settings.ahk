;================================================================================
; Settings.ahk - the settings window
;================================================================================
; Tray menu > Settings, or the gear in the word list. A window that scrolls,
; and can be made shorter or taller. Six sections, all kept in Vocab.ini and all working
; the moment they change - there is no Save button - except administrator,
; which can only take effect at the next start:
;   TRANSLATION  the language translations go into (Language.ahk), and how
;             much Translate takes (TranslateScope, in Sentence.ahk)
;   GEMINI    the key (hidden unless "show" is clicked), a "test" that asks
;             Google whether the key is good, the link to get a free one, and
;             the model (empty = automatic)
;   NETWORK   the proxy - see Http.Proxy in Lookup.ahk
;   SOUND     saying each word out loud as it is looked up
;   GENERAL   start as administrator - see the top of Vocab.ahk - a link to
;             the README's "Start with Windows", and the update check
;             (Update.ahk, and Install.ahk for updating)
;   KEYS      the key rows from Keys.ahk
;
; "test" asks for the list of models, one row of it. That proves the key and
; the connection without spending any of the free quota lookups use.
;
; With no key set, the app says so where it matters, and every one of those
; places opens this window at the key box: a tray notice at start (click it),
; and a line on the Translate, Summary and word cards.
;================================================================================
#Requires AutoHotkey v2.0

; the [Sound] section, read once at start; the window writes it
LoadSoundSettings() {
    global SpeakAuto
    try SpeakAuto := Integer(IniRead(VocabIni(), "Sound", "SayOnLookup", SpeakAuto))
}

GeminiKeyUrl() => "https://aistudio.google.com/apikey"

; At start, when there is no key: a tray notice, and clicking it opens the key box
NoKeyNotice() {
    if (GeminiKey() != "")
        return
    Notice("Word lookups work without it. For plain-English explanations and summaries, "
        . "add a free Gemini key - click here, or tray icon > Settings.", AppName ": no Gemini key"
        , () => Settings.Show("gemini"))
}

; The line a card shows where Gemini's part would be, when there is no key or
; Google turned it down - a link straight to the key box.
NoKeyLine(f, lk) {
    txt := (lk && lk.ai.enabled)
        ? "Google turned down the Gemini key - click to check it in Settings"
        : "This part needs a free Gemini key - click to add one"
    return Link(f.Text(txt, CAmber, "s8 Norm"), (*) => Settings.Show("gemini"))
}

KeyTrouble(lk) => (lk && (!lk.ai.enabled || InStr(lk.ai.note, "key rejected")))

class Settings {
    static g := "", pane := "", key := "", showLink := "", model := "", proxy := "", noteBox := ""
    static auto := "", admin := "", updates := "", updateNote := "", lang := "", scope := "", saver := "", tester := "", req := "", shown := false
    static W := 608                 ; the content is laid out 600 wide, plus the scroll thumb

    ; Opens where it was left, as tall as it was left - or as tall as its
    ; content, whichever is less, and never taller than the screen
    static Show(section := "") {
        if !this.g
            this.Build()
        this.Load()
        KeysWin.Refresh()
        if DllCall("IsWindowVisible", "ptr", this.g.Hwnd)
            WinActivate(this.g.Hwnd)
        else {
            wa := WorkAreaAt(0, 0)
            h := Integer(IniRead(VocabIni(), "Window", "SettingsH", 0))
            h := Min((h >= 200) ? h : this.pane.contentH, this.pane.contentH, wa[4] - wa[2] - 60)
            this.g.Show("w" this.W " h" h)
        }
        if (section = "gemini") {
            this.key.Focus()
            if (Trim(this.key.Value) = "")
                this.Note("Click " Chr(0x201C) "get a free key" Chr(0x201D) " - it takes about two minutes.", CMuted)
        }
    }

    ; The window is a frame that can be made shorter or taller - not wider -
    ; around one pane that scrolls with the wheel (ScrollPane, in Cards.ahk).
    ; Everything in it is laid out once, in Fill.
    static Build() {
        g := Gui("+Resize -MaximizeBox -MinimizeBox -DPIScale +MinSize" this.W "x200", AppName " settings")
        g.BackColor := CBg
        g.MarginX := 0, g.MarginY := 0
        this.g := g
        this.saver := ObjBindMethod(Settings, "Save")
        this.tester := ObjBindMethod(Settings, "TestPoll")
        this.pane := ScrollPane(g, CBg)
        h := this.pane.Build(this.W, (c, W) => Settings.Fill(c))
        g.Opt("+MaxSize" this.W "x" h)
        this.pane.Show(h)
        g.OnEvent("Size", (g, minMax, w, h) => Settings.pane.Show(h))
        g.OnEvent("Close", (*) => Settings.Close())
        g.OnEvent("Escape", (*) => Settings.Close())
        DwmAttr(g.Hwnd, 20, 1)                  ; dark title bar
        SetWindowIcon(g.Hwnd)
    }

    ; every section, top to bottom, into the pane's content c; returns its height
    static Fill(c) {
        c.OnEvent("Escape", (*) => Settings.Close())    ; Esc while a box in it has the focus
        c.SetFont("s12 Bold c" CText, FontUI)
        c.Add("Text", "x22 y14 BackgroundTrans +0x80", "Settings")
        c.SetFont("s9 Norm c" CMuted, FontUI)
        c.Add("Text", "x22 y42 w556 BackgroundTrans +0x80", "Saved as you change them, and used straight away.")
        c.SetFont("s9 Norm c" CDim, FontUI)
        c.Add("Text", "x478 y20 w100 Right BackgroundTrans +0x80", AppName " " VocabVersion)

        ; TRANSLATION
        y := this.Head(c, 72, "TRANSLATION")
        this.Label(c, y, "Into")
        names := []
        for l in Lang.List
            names.Push(l.name)
        c.SetFont("s10 Norm c" CText, FontUI)
        this.lang := c.Add("DropDownList", "x100 y" y " w200 r12", names)
        DarkList(this.lang, "DarkMode_CFD")
        this.lang.OnEvent("Change", (*) => Settings.PickLanguage())
        c.SetFont("s8 Norm c" CDim, FontUI)
        c.Add("Text", "x314 y" (y + 1) " w264 BackgroundTrans +0x80"
            , "What you read is always English. Words you saved keep the language they were saved in.")
        y += 42
        this.Label(c, y, "Passage")
        c.SetFont("s10 Norm c" CText, FontUI)
        this.scope := c.Add("DropDownList", "x100 y" y " w200", ["up to ten sentences", "only the one sentence"])
        DarkList(this.scope, "DarkMode_CFD")
        this.scope.OnEvent("Change", (*) => Settings.Save())
        c.SetFont("s8 Norm c" CDim, FontUI)
        c.Add("Text", "x314 y" (y + 1) " w264 BackgroundTrans +0x80"
            , "What Translate takes: the sentences around the one you click, or just that one, "
            . "up to its first stop.")
        y += 42

        ; GEMINI
        y := this.Head(c, y + 6, "GEMINI")
        c.SetFont("s9 Norm c" CMuted, FontUI)
        c.Add("Text", "x22 y" y " w556 BackgroundTrans +0x80"
            , "Explains sentences in plain English, writes the summaries, and picks the meaning of a word "
            . "that fits where you found it. Without a key, the dictionary, the translation and the "
            . "pronunciation all still work.")
        y += 50
        this.Label(c, y, "Key")
        this.key := this.Edit(c, y, 330, "Password")
        this.key.OnEvent("Change", (*) => SetTimer(Settings.saver, -500))
        c.SetFont("s9 Norm c" CBlue, FontUI)
        this.showLink := Link(c.Add("Text", "x444 y" (y + 4) " w40 BackgroundTrans +0x80", "show")
            , (*) => Settings.ToggleShow())
        Link(c.Add("Text", "x490 y" (y + 4) " w40 BackgroundTrans +0x80", "test"), (*) => Settings.Test())
        y += 32
        c.SetFont("s9 Norm c" CBlue, FontUI)
        Link(c.Add("Text", "x100 y" y " BackgroundTrans +0x80", "get a free key"), (*) => Run(GeminiKeyUrl()))
        c.SetFont("s9 Norm c" CDim, FontUI)
        c.Add("Text", "x192 y" y " w386 BackgroundTrans +0x80"
            , "sign in with Google, press Create API key, copy it, paste it above")
        y += 22
        c.SetFont("s9 Norm c" CMuted, FontUI)
        this.noteBox := c.Add("Text", "x100 y" y " w478 h34 BackgroundTrans +0x80", "")
        y += 38
        this.Label(c, y, "Model")
        this.model := this.Edit(c, y, 478)
        SendMessage(0x1501, 1, StrPtr("automatic - newest free Flash, the next when its quota runs out"), this.model)
        this.model.OnEvent("Change", (*) => SetTimer(Settings.saver, -500))
        y += 36

        ; NETWORK - WinHTTP, which every request goes through, speaks to HTTP
        ; proxies only: a VPN app's HTTP port works, its SOCKS port does not
        y := this.Head(c, y + 6, "NETWORK")
        this.Label(c, y, "Proxy")
        this.proxy := this.Edit(c, y, 170)
        SendMessage(0x1501, 1, StrPtr("auto"), this.proxy)
        this.proxy.OnEvent("Change", (*) => SetTimer(Settings.saver, -500))
        c.SetFont("s8 Norm c" CDim, FontUI)
        c.Add("Text", "x284 y" (y - 4) " w294 BackgroundTrans +0x80"
            , "auto follows Windows (a VPN app's " Chr(0x201C) "system proxy" Chr(0x201D) "), none goes direct, "
            . "or an HTTP proxy like 127.0.0.1:10809. SOCKS proxies do not work.")
        y += 44

        ; SOUND
        y := this.Head(c, y + 6, "SOUND")
        this.auto := this.Check(c, y, "Say each word out loud as it is looked up")
        y += 34

        ; GENERAL
        y := this.Head(c, y + 6, "GENERAL")
        this.admin := this.Check(c, y, "Start as administrator")
        c.SetFont("s8 Norm c" CDim, FontUI)
        c.Add("Text", "x44 y" (y + 22) " w534 BackgroundTrans +0x80"
            , "Only needed for the selection key in programs that themselves run as administrator. "
            . "Windows asks each time " AppName " starts. Takes effect from the next start.")
        y += 58
        c.SetFont("s9 Norm c" CBlue, FontUI)
        Link(c.Add("Text", "x22 y" y " BackgroundTrans +0x80", "Start " AppName " with Windows - how")
            , (*) => Run(RepoUrl "#start-with-windows"))
        y += 34
        this.updates := this.Check(c, y, "Check for updates when " AppName " starts")
        c.SetFont("s9 Norm c" CBlue, FontUI)
        Link(c.Add("Text", "x360 y" (y + 2) " w70 BackgroundTrans +0x80", "check now"), (*) => Settings.CheckNow())
        y += 24
        c.SetFont("s8 Norm c" CDim, FontUI)
        this.updateNote := c.Add("Text", "x44 y" y " w534 BackgroundTrans +0x80"
            , "Once a day it asks GitHub for the newest version and only tells you if there is one.")
        y += 30

        ; KEYS
        y := this.Head(c, y + 6, "KEYS")
        return KeysWin.AddTo(c, y) + 8
    }

    static Head(g, y, title) {
        g.SetFont("s8 Bold c" CBlue, FontUI)
        g.Add("Text", "x22 y" y " BackgroundTrans +0x80", title)
        g.Add("Text", "x22 y" (y + 20) " w556 h1 Background" CTrack)
        return y + 30
    }

    static Label(g, y, text) {
        g.SetFont("s10 Norm c" CText, FontUI)
        g.Add("Text", "x22 y" (y + 3) " w76 BackgroundTrans +0x80", text)
    }

    static Edit(g, y, w, opts := "") {
        g.SetFont("s10 Norm c" CText, FontUI)
        e := g.Add("Edit", "x100 y" y " w" w " h26 -E0x200 -Wrap r1 " opts " Background" CCardHi)
        SendMessage(0xD3, 3, 6 | (6 << 16), e)                          ; EM_SETMARGINS
        return e
    }

    ; A themed checkbox draws its text black whatever the colour, so the box
    ; has no text and the words beside it are a label that clicks it
    static Check(g, y, text) {
        c := g.Add("Checkbox", "x22 y" (y + 3) " w16 h16")
        c.OnEvent("Click", (*) => Settings.Save())
        g.SetFont("s10 Norm c" CText, FontUI)
        Link(g.Add("Text", "x44 y" y " BackgroundTrans +0x80", text), (*) => (c.Value := !c.Value, Settings.Save()))
        return c
    }

    static Load() {
        ini := VocabIni()
        this.key.Value := Trim(IniRead(ini, "Gemini", "ApiKey", ""))
        this.model.Value := Trim(IniRead(ini, "Gemini", "Model", ""))
        px := Trim(IniRead(ini, "Network", "Proxy", "auto"))
        this.proxy.Value := (px = "auto") ? "" : px
        this.auto.Value := SpeakAuto ? 1 : 0
        this.admin.Value := (IniRead(ini, "General", "RunAsAdmin", 0) = 1) ? 1 : 0
        this.updates.Value := (IniRead(ini, "General", "CheckUpdates", 1) = 1) ? 1 : 0
        for i, l in Lang.List
            if (l.code = Lang.Code())
                this.lang.Value := i
        this.scope.Value := (TranslateScope() = 1) ? 2 : 1
        this.Note("")
    }

    static Save(*) {
        global SpeakAuto
        if !this.g
            return
        ini := VocabIni()
        try {
            IniWrite(Trim(this.key.Value), ini, "Gemini", "ApiKey")
            IniWrite(Trim(this.model.Value), ini, "Gemini", "Model")
            px := Trim(this.proxy.Value)
            IniWrite((px = "") ? "auto" : px, ini, "Network", "Proxy")
            SpeakAuto := this.auto.Value
            IniWrite(SpeakAuto, ini, "Sound", "SayOnLookup")
            IniWrite(this.admin.Value, ini, "General", "RunAsAdmin")
            IniWrite(this.updates.Value, ini, "General", "CheckUpdates")
            IniWrite((this.scope.Value = 2) ? 1 : 10, ini, "Translation", "Sentences")
        } catch as e
            this.Note("Could not write Vocab.ini: " e.Message, CRed)
    }

    static Close() {
        SetTimer(this.saver, 0)
        this.Save()                             ; a change typed a moment ago
        KeysWin.Stop()
        WinGetClientPos(, , , &h, this.g.Hwnd)  ; the height it was left at, for next time
        try IniWrite(h, VocabIni(), "Window", "SettingsH")
        this.g.Hide()
    }

    ; a new language is used from the next lookup; the word list's column
    ; turns to match it
    static PickLanguage() {
        Lang.Set(Lang.List[this.lang.Value].code)
        Dict.Refresh()
    }

    ; "check now": the answer goes on the line under it; a new version's line
    ; opens the update window
    static CheckNow() {
        this.updateNote.SetFont("c" CMuted)
        this.updateNote.Text := "asking GitHub" Chr(0x2026)
        Update.Check(false, ObjBindMethod(Settings, "UpdateAnswer"))
    }

    static UpdateAnswer(text, found) {
        this.updateNote.SetFont("c" (found ? CGreen : CMuted))
        this.updateNote.Text := found ? text " Click here to see what is new and update." : text
        if (found && !LinkHwnds.Has(this.updateNote.Hwnd))
            Link(this.updateNote, (*) => Update.found && Install.Offer(Update.found))
    }

    static Note(msg, color := "") {
        this.noteBox.SetFont("c" (color != "" ? color : CMuted))
        this.noteBox.Text := msg
    }

    static ToggleShow() {
        this.shown := !this.shown
        SendMessage(0xCC, this.shown ? 0 : 0x25CF, 0, this.key)        ; EM_SETPASSWORDCHAR
        this.key.Redraw()
        this.showLink.Text := this.shown ? "hide" : "show"
    }

    ;----------------------------------------------------------------------------
    ; "test": one small request that needs the key, and no quota
    ;----------------------------------------------------------------------------
    static Test() {
        k := Trim(this.key.Value)
        if (k = "") {
            this.Note("Paste a key first - " Chr(0x201C) "get a free key" Chr(0x201D) " opens the page.", CAmber)
            return
        }
        if this.req                             ; one test at a time
            return
        SetTimer(this.saver, 0)
        this.Save()
        this.Note("asking Google" Chr(0x2026), CMuted)
        this.req := Http(AiTrack.Api "models?pageSize=1"
            , {timeout: 8000, headers: Map("x-goog-api-key", k)})
        SetTimer(this.tester, 100)
    }

    static TestPoll() {
        if !this.req.Poll()
            return
        SetTimer(this.tester, 0)
        r := this.req, this.req := ""
        msg := r.Ok ? "" : AiTrack.ErrMsg(r)
        if r.Ok {
            AiTrack.keyBad := ""
            this.Note("The key works.", CGreen)
        } else if AiTrack.IsKeyError(r, msg)
            this.Note("Google says this key is not valid. Copy it again from the page - all of it.", CRed)
        else if (r.status = 429)
            this.Note("The key is fine, but its free quota is used up for now. It comes back by itself.", CAmber)
        else if InStr(msg, "location is not supported")
            this.Note("Gemini is not offered in your region. A VPN, with the proxy below, gets around it.", CRed)
        else if (r.err != "")
            this.Note("Could not reach Google (" r.err "). Check the internet, or the proxy below.", CRed)
        else
            this.Note("Google answered: " ((msg != "") ? Http.Short(msg) : r.Why), CRed)
    }
}
