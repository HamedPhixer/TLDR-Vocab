;================================================================================
; Popup.ahk - the lookup popup, and the ones pinned to the screen
;================================================================================
; A PopupCard is one popup window. The global Popup is always the LIVE one:
; every lookup goes to it, and a click outside it or Esc closes it. The pin at
; the top of a card detaches it: it becomes a pinned card that stays until its
; x is clicked, can be dragged anywhere by any empty part of it, and keeps
; working on its own - "look up again", the Translate | Summary switch,
; "+ save". Popup is then a fresh live card, so the next lookup opens beside
; the pinned one instead of replacing it. Pin as many as you like.
;
; Where the live card goes and how tall it may get are decided once, in
; Plan(), when a lookup starts. Below the word it grows downward from just
; under the word; above, upward from just over it - and past capH it scrolls
; instead of growing. "+ N more" freezes the current height, so opening the
; rest scrolls in place rather than moving the popup somewhere the pointer is
; not. A pinned card stays exactly where it was put.
;================================================================================
#Requires AutoHotkey v2.0

global Popup := PopupCard()

class PopupCard {
    static pinned := []             ; the cards pinned to the screen

    __New() {
        this.g := "", this.pane := "", this.st := "", this.anchor := "", this.visible := false
        this.closer := "", this.side := "below", this.capH := 400, this.px := 0, this.w := 0, this.h := 0
        this.wa := "", this.isPinned := false
        this.misread := ""          ; what the screen said before Gemini fixed it
    }

    Ensure() {
        if this.g
            return
        g := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x08000000 -DPIScale")    ; NOACTIVATE
        g.BackColor := CCard
        g.MarginX := 0, g.MarginY := 0
        this.g := g
        this.pane := ScrollPane(g)
        this.closer := ObjBindMethod(this, "Close")
    }

    Begin(word, context, anchor, ocr := false, mode := "word") {
        this.Stop()
        this.st := {word: word, context: context, lk: "", choice: "", userChose: false
            , expanded: false, flash: "", maxSenses: 40, lockH: 0
            , ocr: ocr, misread: this.misread, fixed: false, mode: mode}
        this.misread := ""
        this.anchor := anchor
        this.Plan((mode = "paragraph") ? PopWide : PopW)
        this.pane.Clear()
        this.Render()
    }

    Attach(lk) => this.st.lk := lk

    Update(lk) {
        if (!this.visible || this.st.lk != lk)
            return
        ; The screen reader can hand us a damaged word: "teaching" inside a
        ; player's highlight box comes back as "eachin", because the box's
        ; edges sit on the first and last letter. Gemini reads the sentence and
        ; says what the word was; the lookup then starts again on that word, so
        ; the definition, the translation and whatever gets saved are all the
        ; right word. Only for words read off the screen, and only once.
        fix := Dig(lk.ai.data, "corrected")
        if (this.st.ocr && !this.st.fixed && UsableFix(fix, this.st.word)) {
            this.st.fixed := true
            this.misread := this.st.word
            sentence := Dig(lk.ai.data, "example")
            StartLookup(Trim(fix), (sentence != "") ? sentence : this.st.context, this, this.anchor)
            return
        }
        this.Render()
    }

    Message(text, x, y) {
        this.Stop()
        this.st := {message: text, lk: "", lockH: 0}
        this.anchor := {x: x, y: y, w: 1, h: 16}
        this.Plan(280)
        this.pane.Clear()
        this.Render()
        SetTimer(this.closer, -1800)
    }

    Stop() {
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
    Plan(w) {
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

    PlaceY(h) {
        a := this.anchor, wa := this.wa
        y := (this.side = "below") ? Round(a.y + a.h) + 8
           : (this.side = "above") ? Round(a.y) - 8 - h
           : (this.side = "over") ? Round(a.y + (a.h - h) / 2)
           : Round(a.y)                         ; beside: level with the top of the text
        return Max(wa[2], Min(y, wa[4] - h))
    }

    Render() {
        st := this.st
        if st.HasProp("message")
            ch := this.pane.Build(this.w, (g, W) => this.DrawMessage(g, W))
        else
            ch := this.pane.Build(this.w, (g, W) => RenderLookup(g, W, this.st, this))
        h := Min(ch, st.lockH ? st.lockH : this.capH)
        if (this.isPinned && this.visible) {    ; where it was put, only its height changes
            WinGetPos(&x, &y, , , this.g.Hwnd)
            this.g.Show("NoActivate x" x " y" y " w" this.w " h" h)
        } else
            this.g.Show("NoActivate x" this.px " y" this.PlaceY(h) " w" this.w " h" h)
        this.pane.Show(h)
        if !this.visible {
            DwmAttr(this.g.Hwnd, 33, 2)                 ; rounded corners (Windows 11)
            DwmAttr(this.g.Hwnd, 34, 0x402F2A)          ; border in CTrack (BGR)
        }
        this.h := h, this.visible := true
    }

    DrawMessage(g, W) {
        f := Flow(g, 14, 10, W - 20)
        f.Text(this.st.message, CMuted, "s9 Norm")
        return f.y + 8
    }

    ; A click outside the live popup closes it; one inside is its own business
    ClickAway() {
        MouseGetPos(&mx, &my)
        try WinGetPos(&x, &y, &w, &h, this.g.Hwnd)
        catch
            return
        if (mx < x || mx >= x + w || my < y || my >= y + h)
            this.Close()
    }

    ; The live card hides, ready for the next lookup; a pinned one is done for
    ; good and goes away completely.
    Close(*) {
        this.visible := false
        if !this.g
            return
        SetTimer(this.closer, 0)
        if (this.st && this.st.lk)
            this.st.lk.Cancel()
        if this.isPinned {
            for i, card in PopupCard.pinned
                if (card == this) {
                    PopupCard.pinned.RemoveAt(i)
                    break
                }
            this.pane.Clear()
            this.pane.Forget()
            DropGui(this.g)
            this.g := ""
            return
        }
        this.g.Hide()
        this.pane.Clear()
    }

    ; This card stays on screen, and the next lookup gets a new live card
    Pin() {
        global Popup
        if (this.isPinned || !this.st.HasProp("word"))
            return
        this.isPinned := true
        SetTimer(this.closer, 0)
        PopupCard.pinned.Push(this)
        if (Popup == this)
            Popup := PopupCard()
        this.Render()                           ; the pin becomes an x
    }

    ; Run the whole lookup again, in place: same word, same sentence, same
    ; corner of the screen. Answers that arrived are cached and come back at
    ; once; the ones that failed are asked for again.
    Again() {
        st := this.st
        if st.HasProp("word")           ; the same kind of card again: a sentence stays a sentence
            StartLookup(st.word, st.context, this, this.anchor, false, st.mode)
    }

    ; the Translate | Summary switch: same text, same place, the other card
    Switch(mode, *) {
        st := this.st
        if st.HasProp("word")
            StartLookup(st.word, st.context, this, this.anchor, false, mode, true)
    }

    Choose(key) {
        this.st.choice := key, this.st.userChose := true
        this.Render()
    }

    ToggleMore() {
        st := this.st
        st.expanded := !st.expanded
        st.lockH := st.expanded ? this.h : 0
        this.Render()
    }

    Save() {
        if !this.st.lk
            return
        res := Store.Upsert(BuildRecord(this.st))
        this.st.flash := ((res = "saved") ? "saved " : "updated ") Chr(0x2713)
        this.Render()
        Dict.Refresh()
    }

    ; A pinned card is dragged by any part of it that is not a link: the click
    ; is handed to Windows as a click on a title bar (WM_LBUTTONDOWN)
    static DragPinned(wParam, lParam, msg, hwnd) {
        if LinkHwnds.Has(hwnd)
            return
        root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")     ; GA_ROOT
        for card in PopupCard.pinned
            if (card.g && card.g.Hwnd = root) {
                PostMessage(0xA1, 2, 0, , root)                         ; WM_NCLBUTTONDOWN, HTCAPTION
                return 0
            }
    }
}

; The pin at the top of a popup card, or the x of one already pinned - one of
; the actions CardLinks() draws. Nothing for the word list's pane, which is not
; a popup.
PinAction(owner) {
    if !(owner is PopupCard)
        return ""
    return owner.isPinned
        ? {text: Chr(0xE711), face: "Segoe MDL2 Assets", color: CMuted, w: 22, fn: (*) => owner.Close()}
        : {text: Chr(0xE718), face: "Segoe MDL2 Assets", color: CDim, w: 22, fn: (*) => owner.Pin()}
}
