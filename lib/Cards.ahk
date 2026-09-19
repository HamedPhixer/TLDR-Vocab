;================================================================================
; Cards.ahk - drawing a lookup or a saved word
;================================================================================
#Requires AutoHotkey v2.0

; The content of the popup and of the dictionary pane is rebuilt from scratch
; on every change: AHK cannot delete a control, and a fresh Gui is cheap. Text
; is laid out top to bottom by Flow; a Text control given a width but no
; height gets the height its wrapped text needs, which is what makes this work.
class Flow {
    __New(g, x, y, w) {
        this.g := g, this.x := x, this.y := y, this.w := w
    }

    ; +0x80 is SS_NOPREFIX - without it an "&" in a definition would vanish
    ; and underline the next letter
    Text(text, color, font := "s9 Norm", opts := "", gap := 3, indent := 0, face := "") {
        this.g.SetFont(font " c" color, (face != "") ? face : FontUI)
        c := this.g.Add("Text", "x" (this.x + indent) " y" this.y " w" (this.w - indent) " BackgroundTrans +0x80 " opts, text)
        if (face = FontFa)
            WrapByWords(c, text, this.w - indent)
        c.GetPos(, , , &h)
        this.y += h + gap
        return c
    }

    Label(text, color := "") {
        this.y += 7
        return this.Text(text, (color != "") ? color : CDim, "s7 Bold", "", 3)
    }

    ; A translation, in the chosen language - or in code, for a word saved in
    ; another one. Right-to-left languages get RTL reading order and are
    ; right-aligned, so punctuation lands where they expect it, and are wrapped
    ; at spaces (WrapByWords); the rest are ordinary text.
    Tr(text, font := "s12 Norm", color := "", indent := 0, code := "") {
        color := (color != "") ? color : CGreen
        if Lang.Rtl(code)
            return this.Text(text, color, font, "Right +E0x2000", 2, indent, FontFa)
        return this.Text(text, color, font, "", 2, indent)
    }
}

; Windows wraps right-to-left text inside a word: Persian breaks between two
; letters that do not join, so "dashtan" can end a line as its first two
; letters. English only ever breaks at a space. So right-to-left text is split
; into lines here, at spaces, each line measured with the control's own font,
; and the control just shows them.
WrapByWords(c, text, w) {
    if !InStr(text, " ")
        return
    hdc := DllCall("GetDC", "ptr", c.Hwnd, "ptr")
    ; WM_GETFONT straight to the handle: SendMessage() looks the control up and
    ; cannot find it while its window is still hidden, as a pane being laid out is
    hfont := DllCall("SendMessageW", "ptr", c.Hwnd, "uint", 0x31, "ptr", 0, "ptr", 0, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hfont, "ptr")
    rc := Buffer(16, 0)
    width(s) {
        NumPut("int", 0, "int", 0, "int", 30000, "int", 1000, rc)
        ; DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX | DT_RTLREADING
        DllCall("DrawTextW", "ptr", hdc, "wstr", s, "int", -1, "ptr", rc, "uint", 0x20C20)
        return NumGet(rc, 8, "int")
    }
    lines := [], line := ""
    for word in StrSplit(text, " ") {
        if (word = "")
            continue
        cand := (line = "") ? word : line " " word
        if (line != "" && width(cand) > w - 4)
            lines.Push(line), line := word
        else
            line := cand
    }
    lines.Push(line)
    if (lines.Length > 1) {
        wrapped := Join(lines, "`n")
        NumPut("int", 0, "int", 0, "int", w, "int", 0, rc)
        ; DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX | DT_RTLREADING: the height of those lines
        DllCall("DrawTextW", "ptr", hdc, "wstr", wrapped, "int", -1, "ptr", rc, "uint", 0x20C10)
        c.Text := wrapped
        c.Move(, , , NumGet(rc, 12, "int"))
    }
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("ReleaseDC", "ptr", c.Hwnd, "ptr", hdc)
}

; A content area that scrolls with the wheel: a child Gui inside a host Gui,
; moved up and down, with a thin thumb on the right. Each popup is one, the
; dictionary pane is another, and so is the settings window. Build() lays the
; new content out off-screen and returns its height, so the caller can size
; the host first; Show() swaps it in and keeps the scroll position, so picking
; a definition does not jump back to the top.
class ScrollPane {
    static byHost := Map()          ; host window -> its pane, for the wheel

    __New(host, bg := "") {
        this.host := host, this.content := "", this.next := "", this.nextH := 0
        this.scroll := 0, this.contentH := 0, this.w := 0, this.h := 0
        this.bg := (bg != "") ? bg : CCard
        this.bar := host.Add("Text", "x0 y0 w3 h10 Hidden Background" CDim)
        ScrollPane.byHost[host.Hwnd] := this
    }

    ; The pane under the mouse, if any: the window there, or the nearest of its
    ; parents that hosts a pane. Whatever is on top is what the wheel scrolls -
    ; a pinned popup over the word list, the live popup over a pinned one.
    static At(mx, my) {
        h := DllCall("WindowFromPoint", "int64", (my << 32) | (mx & 0xFFFFFFFF), "ptr")
        while h {
            if ScrollPane.byHost.Has(h)
                return ScrollPane.byHost[h]
            h := DllCall("GetAncestor", "ptr", h, "uint", 1, "ptr")      ; GA_PARENT
        }
        return ""
    }

    ; for a host that is about to go for good
    Forget() {
        if ScrollPane.byHost.Has(this.host.Hwnd)
            ScrollPane.byHost.Delete(this.host.Hwnd)
    }

    ; draw(g, width) lays out the content and returns its height
    Build(w, draw) {
        if this.next
            DropGui(this.next)
        c := Gui("+Parent" this.host.Hwnd " -Caption -DPIScale")
        c.BackColor := this.bg
        c.MarginX := 0, c.MarginY := 0
        this.next := c, this.w := w
        return this.nextH := draw.Call(c, w - 8)
    }

    Show(h) {
        old := ""
        if this.next {
            old := this.content
            this.content := this.next, this.contentH := this.nextH, this.next := ""
        }
        this.h := h
        if !this.content
            return
        this.scroll := Max(0, Min(this.scroll, this.contentH - h))
        this.content.Show("NoActivate x0 y" (-this.scroll) " w" (this.w - 8) " h" Max(this.contentH, h))
        if old
            DropGui(old)
        this.UpdateBar()
    }

    ScrollBy(dy) {
        s := Max(0, Min(this.scroll + dy, this.contentH - this.h))
        if (s = this.scroll || !this.content)
            return
        this.scroll := s
        DllCall("SetWindowPos", "ptr", this.content.Hwnd, "ptr", 0, "int", 0, "int", -s, "int", 0, "int", 0, "uint", 0x15)
        this.UpdateBar()
    }

    UpdateBar() {
        if (this.contentH <= this.h) {
            this.bar.Visible := false
            return
        }
        th := Max(24, Round(this.h * this.h / this.contentH))
        this.bar.Move(this.w - 5, Round((this.h - th) * this.scroll / (this.contentH - this.h)), 3, th)
        this.bar.Visible := true
    }

    Clear() {
        if this.content
            DropGui(this.content)
        this.content := "", this.scroll := 0, this.contentH := 0
        this.bar.Visible := false
    }
}

; WM_MOUSEWHEEL: the wheel scrolls whichever pane is under the pointer, and
; otherwise leaves the message alone - the word list scrolls itself
PaneWheel(wParam, lParam, msg, hwnd) {
    MouseGetPos(&mx, &my)
    delta := (wParam >> 16) & 0xFFFF
    if (delta > 0x7FFF)
        delta -= 0x10000
    if (sp := ScrollPane.At(mx, my)) {
        sp.ScrollBy(Round(-delta / 120 * 60))
        return 0
    }
}

Link(ctrl, fn) {
    ctrl.OnEvent("Click", fn)
    LinkHwnds[ctrl.Hwnd] := true
    return ctrl
}

; A card is rebuilt on every change, so its links are forgotten with it -
; otherwise LinkHwnds would grow all day, and a handle Windows hands out again
; later could get the hand cursor.
DropGui(g) {
    for ctrl in g
        if LinkHwnds.Has(ctrl.Hwnd)
            LinkHwnds.Delete(ctrl.Hwnd)
    g.Destroy()
}

OnSetCursor(wParam, lParam, msg, hwnd) {
    static hand := DllCall("LoadCursor", "ptr", 0, "ptr", 32649, "ptr")
    static ns   := DllCall("LoadCursor", "ptr", 0, "ptr", 32645, "ptr")
    static cross := DllCall("LoadCursor", "ptr", 0, "ptr", 32515, "ptr")
    if (Box.dim && wParam = Box.dim.Hwnd) {
        DllCall("SetCursor", "ptr", cross)
        return true
    }
    if LinkHwnds.Has(wParam) {
        DllCall("SetCursor", "ptr", hand)
        return true
    }
    if (Dict.g && wParam = Dict.g.Hwnd && (lParam & 0xFFFF) = 1 && Dict.OverDivider()) {
        DllCall("SetCursor", "ptr", ns)
        return true
    }
}

; The links at the top right of a card, laid out right to left - the first in
; the list is the rightmost - each with its own width. An empty entry is
; skipped, so a card can leave one out with "". A glyph (the pin) names its
; font in face. Returns where the leftmost one starts.
CardLinks(g, x, y, acts) {
    for a in acts {
        if !a
            continue
        glyph := a.HasProp("face")
        g.SetFont((glyph ? "s10 Norm c" : "s9 Bold c") a.color, glyph ? a.face : FontUI)
        x -= a.w
        Link(g.Add("Text", "x" x " y" (glyph ? y - 1 : y) " w" a.w " Right BackgroundTrans +0x80", a.text), a.fn)
        x -= 8
    }
    return x
}

; The word, a speaker to hear it, the phonetic, and the actions on the right
; (see CardLinks) - each action with its own width: "delete" needs far less
; room than "click again to delete".
Header(f, word, phon, actions) {
    g := f.g
    right := 0
    for a in actions
        if a
            right += a.w + 8
    room := f.w - right - 30                        ; 30: the speaker beside it
    ; Decided by the width the word really takes, not its letter count: two
    ; words of 22 letters overran "look up again" at full size. Too wide, and
    ; it is drawn again smaller and wrapping, the wide copy hidden.
    g.SetFont("s15 Bold c" CText, FontUI)
    wt := g.Add("Text", "x" f.x " y" f.y " BackgroundTrans +0x80", word)
    wt.GetPos(&wx, &wy, &ww, &wh)
    if (ww > room) {
        wt.Visible := false
        g.SetFont("s12 Bold c" CText, FontUI)
        wt := g.Add("Text", "x" f.x " y" f.y " w" room " BackgroundTrans +0x80", word)
        wt.GetPos(&wx, &wy, &ww, &wh)
    }
    bottom := wy + wh, x := wx + ww + 8
    g.SetFont("s11 Norm c" CMuted, "Segoe MDL2 Assets")         ; the speaker glyph
    sp := Link(g.Add("Text", "x" x " y" (wy + wh - 24) " w20 BackgroundTrans +0x80", Chr(0xE767))
        , (*) => Speak.Say(word))
    sp.GetPos(, , &spw)
    x += spw + 4
    if (phon != "") {
        g.SetFont("s9 Norm c" CMuted, FontUI)
        pt := g.Add("Text", "x" x " y" (wy + wh - 20) " BackgroundTrans +0x80", phon)
        pt.GetPos(&px, , &pw, &ph)
        if (px + pw > f.x + f.w - right) {          ; no room beside the word
            pt.Move(f.x, bottom)
            bottom += ph
        }
    }
    CardLinks(g, f.x + f.w, wy + 6, actions)
    f.y := bottom + 2
}

; One pickable meaning: the dot, then the text; clicking it calls pick(key).
; key is a parameter here, so each row's click remembers its own - a closure
; made inside a loop would see only the loop's last value.
SenseRow(f, key, on, text, pick) {
    f.g.SetFont("s9 Norm c" (on ? CGreen : CDim), FontUI)
    f.g.Add("Text", "x" f.x " y" f.y " w12 BackgroundTrans +0x80", on ? Chr(0x25CF) : Chr(0x2022))
    return Link(f.Text(text, CText, "s9 Norm", "", 3, 14), (*) => pick.Call(key))
}

; a part of speech and its translations, the way the translator groups them
TrRow(f, pos, text, code := "") {
    f.g.SetFont("s8 Norm Italic c" CMuted, FontUI)
    f.g.Add("Text", "x" f.x " y" (f.y + 3) " w90 BackgroundTrans +0x80", pos)
    f.Tr(text, "s10 Norm", CText, 90, code)
}

Ellipsis(f) => f.Text(Chr(0x2026), CDim, "s9 Norm")

PosLine(f, grp) => f.Text(grp["pos"] ((Dig(grp, "of") != "") ? "   " Chr(0xB7) "   " grp["of"] : ""), CAmber, "s8 Norm Italic", "", 1)

RenderLookup(g, W, st, owner) {
    if (st.HasProp("mode") && st.mode = "sentence")
        return RenderSentence(g, W, st, owner)
    if (st.HasProp("mode") && st.mode = "paragraph")
        return RenderParagraph(g, W, st, owner)
    lk := st.lk
    pick := ObjBindMethod(owner, "Choose")
    f := Flow(g, 14, 10, W - 28)
    saved := Store.Find(st.word)
    action := (st.flash != "") ? st.flash : saved ? "saved " Chr(0x2713) : "+ save"
    acts := [PinAction(owner), {text: action, color: (saved || st.flash != "") ? CMuted : CGreen, w: 84, fn: (*) => owner.Save()}]
    if lk        ; a source that answered with nothing is worth another try
        acts.Push({text: "look up again", color: CBlue, w: 94, fn: (*) => owner.Again()})
    Header(f, st.word, (lk && lk.def.data) ? Dig(lk.def.data, "phonetic") : "", acts)

    lemma := ""
    if (lk && lk.ai.data && lk.ai.data["lemma"] != "")
        lemma := lk.ai.data["lemma"]
    else if (lk && lk.def.data)
        lemma := Dig(lk.def.data, "lemma")
    if (lemma != "" && Lookup.Norm(lemma) != Lookup.Norm(st.word))
        f.Text(Chr(0x2192) " " lemma, CMuted, "s9 Norm")
    if (st.HasProp("misread") && st.misread != "")
        f.Text("the screen read " Chr(0x201C) st.misread Chr(0x201D) ", Gemini corrected it"
            , CAmber, "s8 Norm Italic")

    if (lk && lk.ai.enabled) {
        f.Label((st.context != "") ? "IN THIS SENTENCE" : "GEMINI", CBlue)
        if (st.context != "") {         ; the sentence itself - Gemini's tidied copy once it has one
            ex := (lk.ai.data && Dig(lk.ai.data, "example") != "") ? lk.ai.data["example"] : st.context
            f.Text(Chr(0x201C) ex Chr(0x201D), CMuted, "s8 Norm Italic", "", 5)
        }
        if !lk.ai.done
            f.Text("asking Gemini" Chr(0x2026), CDim, "s9 Norm Italic")
        else if lk.ai.data {
            a := lk.ai.data
            SenseRow(f, "ai", Chosen(st) = "ai", a["meaning"] ((a["pos"] != "") ? "  (" a["pos"] ")" : ""), pick)
            if (a["persian"] != "")
                f.Tr(a["persian"])
            if (a["note"] != "")
                f.Text(a["note"], CAmber, "s8 Norm", "", 3, 14)
        } else if KeyTrouble(lk)
            NoKeyLine(f, lk)
        else
            f.Text("Gemini: " lk.ai.note, CDim, "s8 Norm Italic")
    }

    f.Label(Lang.Label())
    if (!lk || !lk.fa.done)
        Ellipsis(f)
    else if lk.fa.data {
        fa := lk.fa.data
        if (fa["main"] != "")
            f.Tr(fa["main"])
        for i, grp in fa["groups"]
            if (i <= 3)
                TrRow(f, grp["pos"], Join(grp["terms"], Lang.Sep(), 5))
    } else
        f.Text("no translation found  (" Join(lk.fa.tried, ", ") ")", CDim, "s8 Norm Italic")

    f.Label("DEFINITIONS")
    if (!lk || (!lk.def.done && !lk.def.data))
        Ellipsis(f)
    else if lk.def.data {
        total := 0, shown := 0
        for gi, grp in lk.def.data["groups"] {
            total += grp["senses"].Length
            if (!st.expanded && gi > 4) || shown >= st.maxSenses
                continue
            limit := st.expanded ? 8 : (gi = 1) ? 2 : 1
            PosLine(f, grp)
            for si, s in grp["senses"] {
                if (si > limit || shown >= st.maxSenses)
                    break
                key := "g" gi "." si
                SenseRow(f, key, Chosen(st) = key, s["d"], pick)
                if ((tr := Lang.SenseTr(lk.def.data, s)) != "")
                    f.Tr(tr, "s9 Norm", CGreen, 14)
                if (st.expanded && s["ex"] != "")
                    f.Text(Chr(0x201C) s["ex"] Chr(0x201D), CMuted, "s8 Norm Italic", "", 3, 14)
                shown++
            }
        }
        if (total > shown && !st.expanded)
            Link(f.Text("+ " (total - shown) " more meaning" ((total - shown = 1) ? "" : "s"), CBlue, "s8 Norm"), (*) => owner.ToggleMore())
        else if st.expanded
            Link(f.Text("fewer", CBlue, "s8 Norm"), (*) => owner.ToggleMore())
    } else
        f.Text("no dictionary entry  (" Join(lk.def.tried, ", ") ")", CDim, "s8 Norm Italic")

    if (st.context != "" && !(lk && lk.ai.enabled)) {       ; with a key it is under IN THIS SENTENCE
        f.y += 6
        f.Text(Chr(0x201C) st.context Chr(0x201D), CMuted, "s8 Norm Italic")
    }
    if lk {
        src := []
        for t in [lk.def, lk.fa, lk.ai]
            if (t.source != "")
                src.Push(t.source (t.cached ? " (saved copy)" : ""))
        if src.Length {
            f.y += 4
            f.Text(Join(src, "   " Chr(0xB7) "   "), CDim, "s7 Norm")
        }
        ; the word card works whole without Gemini, so only a quiet line
        if !lk.ai.enabled
            Link(f.Text("Gemini is off: add a free key for the meaning that fits the sentence"
                , CDim, "s7 Norm"), (*) => Settings.Show("gemini"))
    }
    return f.y + 8
}

; A saved word, entirely from words.json. The top shows what is saved; the dots
; below pick what that is - Gemini's meaning, or any stored definition.
RenderEntry(g, W, st) {
    rec := st.rec
    code := (Dig(rec, "lang") != "") ? rec["lang"] : "fa"     ; saved before there was a choice: Persian
    EnsureAi(rec)
    pick := ObjBindMethod(Dict, "ChooseSaved")
    f := Flow(g, 14, 10, W - 28)
    armed := (A_TickCount - Dict.delArmed < 3000)
    Header(f, rec["word"], Dig(rec, "phonetic")
        , [{text: armed ? "click again to delete" : "delete", color: armed ? CRed : CDim
          , w: armed ? 130 : 50, fn: (*) => Dict.Delete()}])
    sub := []
    if (Dig(rec, "kind") = "sentence")          ; stored as "sentence"; the card it came from says TRANSLATE
        sub.Push("translate")
    else if (Dig(rec, "pos") != "")
        sub.Push(rec["pos"])
    if (Dig(rec, "lemma") != "" && Lookup.Norm(rec["lemma"]) != Lookup.Norm(rec["word"]))
        sub.Push(Chr(0x2192) " " rec["lemma"])
    if sub.Length
        f.Text(Join(sub, "   "), CMuted, "s9 Norm")
    if (Dig(rec, "persian") != "")
        f.Tr(rec["persian"], "s13 Norm", "", 0, code)
    if (Dig(rec, "meaning") != "")
        f.Text(rec["meaning"], CText, "s10 Norm", "", 4)

    ai := Dig(rec, "ai")
    ; not "aiText": names are case-insensitive, so a variable of that name
    ; would shadow AiText() and nothing could call it
    if (gem := AiText(ai)) {
        f.Label("GEMINI", CBlue)
        SenseRow(f, "ai", gem == Dig(rec, "meaning")
            , gem ((Dig(ai, "pos") != "") ? "  (" ai["pos"] ")" : ""), pick)
        if (Dig(ai, "persian") != "")
            f.Tr(ai["persian"], "s11 Norm", "", 0, code)
        if (Dig(ai, "note") != "")
            f.Text(ai["note"], CAmber, "s8 Norm", "", 3, 14)
    }

    exs := Dig(rec, "examples") || []
    if exs.Length {
        f.Label("SEEN IN")
        i := exs.Length
        while (i >= 1) {
            f.Text(Chr(0x201C) Dig(exs[i], "text") Chr(0x201D), CMuted, "s9 Norm Italic", "", 1)
            f.Text(Dig(exs[i], "seen"), CDim, "s7 Norm", "", 5)
            i--
        }
    }
    fa := Dig(rec, "fa")
    if (fa is Map && Dig(fa, "groups") is Array && fa["groups"].Length) {
        f.Label(Lang.Label(code))
        for grp in fa["groups"]
            TrRow(f, grp["pos"], Join(grp["terms"], Lang.Sep(code), 6), code)
    }
    defs := Dig(rec, "defs") || []
    if defs.Length {
        f.Label("DEFINITIONS")
        for gi, grp in defs {
            PosLine(f, grp)
            for si, s in grp["senses"] {
                SenseRow(f, "g" gi "." si, s["d"] == rec["meaning"], s["d"], pick)
                if (Dig(s, "fa") != "")
                    f.Tr(s["fa"], "s9 Norm", CGreen, 14, code)
                if (Dig(s, "ex") != "")
                    f.Text(Chr(0x201C) s["ex"] Chr(0x201D), CMuted, "s8 Norm Italic", "", 3, 14)
            }
        }
    }
    f.y += 8
    f.Text("added " Dig(rec, "added") ((Dig(rec, "source") != "") ? "   " Chr(0xB7) "   " rec["source"] : ""), CDim, "s7 Norm")
    last := exs.Length ? Dig(exs[exs.Length], "text") : ""
    again := (Dig(rec, "kind") = "sentence")     ; a saved sentence comes back as a sentence card
        ? (*) => StartLookup(rec["word"], "", Dict, "", false, "sentence")
        : (*) => StartLookup(rec["word"], last, Dict)
    Link(f.Text("look it up again", CBlue, "s8 Norm"), again)
    return f.y + 10
}

WorkAreaAt(x, y) {
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b) {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            return [l, t, r, b]
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
    return [l, t, r, b]
}

DwmAttr(hwnd, attr, val) {
    buf := Buffer(4)
    NumPut("int", val, buf)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", attr, "ptr", buf, "uint", 4)
}

