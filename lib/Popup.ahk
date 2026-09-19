;================================================================================
; Popup.ahk - the lookup popup
;================================================================================
#Requires AutoHotkey v2.0

; Where it goes and how tall it may get are decided once, in Plan(), when a
; lookup starts. Below the word it grows downward from just under the word;
; above, upward from just over it - and past capH it scrolls instead of
; growing. "+ N more" freezes the current height, so opening the rest scrolls
; in place rather than moving the popup somewhere the pointer is not.
class Popup {
    static g := "", pane := "", st := "", anchor := "", visible := false, closer := ""
    static side := "below", capH := 400, px := 0, w := 0, h := 0
    static misread := ""            ; what the screen said before Gemini fixed it

    static Ensure() {
        if this.g
            return
        g := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x08000000 -DPIScale")    ; NOACTIVATE
        g.BackColor := CCard
        g.MarginX := 0, g.MarginY := 0
        this.g := g
        this.pane := ScrollPane(g)
        this.closer := ObjBindMethod(Popup, "Close")
    }

    static Begin(word, context, anchor, ocr := false, mode := "word") {
        this.Stop()
        this.st := {word: word, context: context, lk: "", choice: "", userChose: false
            , expanded: false, flash: "", maxSenses: 40, lockH: 0
            , ocr: ocr, misread: Popup.misread, fixed: false, mode: mode}
        Popup.misread := ""
        this.anchor := anchor
        this.Plan((mode = "paragraph") ? PopWide : PopW)
        this.pane.Clear()
        this.Render()
    }

    static Attach(lk) => this.st.lk := lk

    static Update(lk) {
        if (!this.visible || this.st.lk != lk)
            return
        ; The screen reader can hand us a damaged word: "teaching" inside a
        ; player's highlight box comes back as "eachin", because the box's
        ; edges sit on the first and last letter. Gemini reads the sentence and
        ; says what the word was; the lookup then starts again on that word, so
        ; the definition, the Persian and whatever gets saved are all the right
        ; word. Only for words read off the screen, and only once.
        fix := Dig(lk.ai.data, "corrected")
        if (this.st.ocr && !this.st.fixed && UsableFix(fix, this.st.word)) {
            this.st.fixed := true
            Popup.misread := this.st.word
            sentence := Dig(lk.ai.data, "example")
            StartLookup(Trim(fix), (sentence != "") ? sentence : this.st.context, Popup, this.anchor)
            return
        }
        this.Render()
    }

    static Message(text, x, y) {
        this.Stop()
        this.st := {message: text, lk: "", lockH: 0}
        this.anchor := {x: x, y: y, w: 1, h: 16}
        this.Plan(280)
        this.pane.Clear()
        this.Render()
        SetTimer(this.closer, -1800)
    }

    static Stop() {
        this.Ensure()
        SetTimer(this.closer, 0)
        if (this.st && this.st.lk)
            this.st.lk.Cancel()
    }

    ; Where the popup goes, around the text it is about (the anchor): below or
    ; above when there is room for a proper popup there; otherwise beside it,
    ; right then left; and when the text fills the screen - a big block, a big
    ; box - over the middle of it. Wherever it goes, it stays on the screen:
    ; with only "below" and "above" to choose from, a block that filled the
    ; screen pushed it off the edge.
    static Plan(w) {
        a := this.anchor
        wa := WorkAreaAt(a.x + a.w / 2, a.y + a.h / 2)
        want := Min(PopMaxH, 320)
        below := wa[4] - Round(a.y + a.h) - 8
        above := Round(a.y) - 8 - wa[2]
        right := wa[3] - Round(a.x + a.w) - 8
        left := Round(a.x) - 8 - wa[1]
        full := wa[4] - wa[2] - 16
        this.side := (below >= want) ? "below" : (above >= want) ? "above"
            : (right >= w) ? "right" : (left >= w) ? "left"
            : (Max(below, above) >= 160) ? ((below >= above) ? "below" : "above") : "over"
        this.capH := Min(PopMaxH, (this.side = "below") ? below : (this.side = "above") ? above : full)
        this.w := w, this.wa := wa
        this.px := (this.side = "right") ? Round(a.x + a.w) + 8
                 : (this.side = "left") ? Round(a.x) - 8 - w
                 : (this.side = "over") ? Round(a.x + (a.w - w) / 2)
                 : Round(a.x) - 14
        this.px := Max(wa[1], Min(this.px, wa[3] - w))
    }

    static PlaceY(h) {
        a := this.anchor, wa := this.wa
        y := (this.side = "below") ? Round(a.y + a.h) + 8
           : (this.side = "above") ? Round(a.y) - 8 - h
           : (this.side = "over") ? Round(a.y + (a.h - h) / 2)
           : Round(a.y)                         ; beside: level with the top of the text
        return Max(wa[2], Min(y, wa[4] - h))
    }

    static Render() {
        st := this.st
        if st.HasProp("message")
            ch := this.pane.Build(this.w, (g, W) => Popup.DrawMessage(g, W))
        else
            ch := this.pane.Build(this.w, (g, W) => RenderLookup(g, W, Popup.st, Popup))
        h := Min(ch, st.lockH ? st.lockH : this.capH)
        y := this.PlaceY(h)
        this.g.Show("NoActivate x" this.px " y" y " w" this.w " h" h)
        this.pane.Show(h)
        if !this.visible {
            DwmAttr(this.g.Hwnd, 33, 2)                 ; rounded corners (Windows 11)
            DwmAttr(this.g.Hwnd, 34, 0x402F2A)          ; border in CTrack (BGR)
        }
        this.h := h, this.visible := true
    }

    static DrawMessage(g, W) {
        f := Flow(g, 14, 10, W - 20)
        f.Text(this.st.message, CMuted, "s9 Norm")
        return f.y + 8
    }

    ; A click outside the popup closes it; one inside is its own business
    static ClickAway() {
        MouseGetPos(&mx, &my)
        try WinGetPos(&x, &y, &w, &h, this.g.Hwnd)
        catch
            return
        if (mx < x || mx >= x + w || my < y || my >= y + h)
            this.Close()
    }

    static Close(*) {
        this.visible := false
        if !this.g
            return
        SetTimer(this.closer, 0)
        this.g.Hide()
        this.pane.Clear()
        if (this.st && this.st.lk)
            this.st.lk.Cancel()
    }

    ; Run the whole lookup again, in place: same word, same sentence, same
    ; corner of the screen. Answers that arrived are cached and come back at
    ; once; the ones that failed are asked for again.
    static Again() {
        st := this.st
        if st.HasProp("word")           ; the same kind of card again: a sentence stays a sentence
            StartLookup(st.word, st.context, Popup, this.anchor, false, st.mode)
    }

    ; the Translate | Summary switch: same text, same place, the other card
    static Switch(mode, *) {
        st := this.st
        if st.HasProp("word")
            StartLookup(st.word, st.context, Popup, this.anchor, false, mode, true)
    }

    static Choose(key) {
        this.st.choice := key, this.st.userChose := true
        this.Render()
    }

    static ToggleMore() {
        st := this.st
        st.expanded := !st.expanded
        st.lockH := st.expanded ? this.h : 0
        this.Render()
    }

    static Save() {
        if !this.st.lk
            return
        res := Store.Upsert(BuildRecord(this.st))
        this.st.flash := ((res = "saved") ? "saved " : "updated ") Chr(0x2713)
        this.Render()
        Dict.Refresh()
    }
}

