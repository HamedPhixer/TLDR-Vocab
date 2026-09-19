;================================================================================
; Box.ahk - draw a box, read what is inside it
;================================================================================
; Press the box key (Win + Shift + ` by default), drag a rectangle over the
; text, let go. Only what is inside the box is read - no guessing where a
; sentence or a block ends, which is what the click keys have to do. Esc, a
; right click, or the box key again cancels; so do 20 seconds of nothing.
;
; What it becomes is decided by the number of words, the same split as the
; selection key: up to four go to the dictionary card, up to SentenceMaxWords
; to Translate, anything longer to Summary.
;
; HOW THE DRAWING WORKS - AND FULLSCREEN GAMES
; The screen is dimmed by a see-through window over every monitor, and the
; green frame follows the pointer. The mouse itself is read by hotkeys, not
; by that window: while the box is active, the left button is Vocab's, so the
; drag works even when the dimming cannot appear. Both windows are gone
; before the screen is read, so neither ends up in the picture.
;
; A game in borderless or windowed fullscreen - most of them now - is just a
; window, and all of this works over it. An old-style EXCLUSIVE fullscreen
; game is the one case that may not cooperate: the dimming may not show, or
; showing it may knock the game out of fullscreen. The drawing is kept to
; Begin/Down/Track/Up for that reason. If a game ever shows trouble, those
; four are what get a windowless alternative - press the key at one corner
; and again at the other - and the reading after it stays as it is.
;================================================================================
#Requires AutoHotkey v2.0

LookupBox(*) {
    if Box.active
        Box.Cancel()
    else
        Box.Begin()
}

#HotIf Box.active
*LButton::Box.Down()
*LButton Up::Box.Up()
*RButton::Box.Cancel()
Esc::Box.Cancel()
#HotIf

class Box {
    static active := false, dragging := false, dim := "", frame := ""
    static x0 := 0, y0 := 0, rect := "", ticker := "", giveUp := ""

    static Begin() {
        if Popup.visible {
            Popup.Close()
            Sleep 40
        }
        if !this.ticker
            this.ticker := ObjBindMethod(Box, "Track"), this.giveUp := ObjBindMethod(Box, "Cancel")
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 -DPIScale")    ; NOACTIVATE
        g.BackColor := "000000"
        g.Show("NoActivate x" vx " y" vy " w" vw " h" vh)
        WinSetTransparent(70, g.Hwnd)
        this.dim := g
        this.active := true, this.dragging := false
        SetTimer(this.giveUp, -20000)
    }

    static Down() {
        if this.dragging
            return
        SetTimer(this.giveUp, 0)
        MouseGetPos(&x, &y)
        this.x0 := x, this.y0 := y
        this.rect := [x, y, 0, 0]
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020 -DPIScale")    ; NOACTIVATE | TRANSPARENT
        g.BackColor := CGreen
        this.frame := g
        this.dragging := true
        SetTimer(this.ticker, 15)
    }

    ; the frame follows the pointer: a window with its middle cut out of its
    ; region, like the paragraph outline
    static Track() {
        if !this.dragging
            return
        MouseGetPos(&x, &y)
        x1 := Min(x, this.x0), y1 := Min(y, this.y0)
        w := Abs(x - this.x0), h := Abs(y - this.y0)
        if (this.rect[1] = x1 && this.rect[2] = y1 && this.rect[3] = w && this.rect[4] = h)
            return
        this.rect := [x1, y1, w, h]
        if (w < 6 || h < 6)
            return
        this.frame.Show("NoActivate x" x1 " y" y1 " w" w " h" h)
        outer := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", w, "int", h, "ptr")
        inner := DllCall("CreateRectRgn", "int", 2, "int", 2, "int", w - 2, "int", h - 2, "ptr")
        DllCall("CombineRgn", "ptr", outer, "ptr", outer, "ptr", inner, "int", 4)   ; RGN_DIFF
        DllCall("SetWindowRgn", "ptr", this.frame.Hwnd, "ptr", outer, "int", true)  ; takes the region
        DllCall("DeleteObject", "ptr", inner)
    }

    static Up() {
        if !this.dragging
            return
        this.Track()
        r := this.rect
        this.Clear()
        if (r[3] < 8 || r[4] < 8) {
            Popup.Message("Drag a box around the text", r[1], r[2])
            return
        }
        Sleep 60                                ; let the dimming leave the screen
        Box.Read(r[1], r[2], r[3], r[4])
    }

    static Cancel(*) {
        this.Clear()
    }

    static Clear() {
        if this.ticker
            SetTimer(this.ticker, 0), SetTimer(this.giveUp, 0)
        for g in [this.frame, this.dim]
            if g
                try g.Destroy()
        this.frame := "", this.dim := ""
        this.active := false, this.dragging := false
    }

    ;----------------------------------------------------------------------------
    ; Reading it
    ;----------------------------------------------------------------------------
    static Read(x, y, w, h) {
        try text := Box.TextIn(x, y, w, h)
        catch as e {
            VocabLog("OCR (box): " e.Message)
            Popup.Message("Could not read the screen: " e.Message, x, y + h)
            return
        }
        if (text = "") {
            Popup.Message("No text in the box", x, y + h)
            return
        }
        Outline.Flash(x - 3, y - 3, w + 6, h + 6)
        if (StrLen(text) > 3000)                ; the paragraph lookup's own limit
            text := SubStr(text, 1, 3000)
        n := CountWords(text)
        mode := (n <= 4) ? "word" : (n <= SentenceMaxWords()) ? "sentence" : "paragraph"
        if (mode != "paragraph")
            text := RegExReplace(text, "\s+", " ")
        ; the popup keeps clear of the box if it can - see Popup.Plan
        StartLookup((mode != "word" || InStr(text, " ")) ? text : CleanWord(text), "", Popup
            , {x: x, y: y, w: w, h: h}, mode = "word", mode)
    }

    ; The text in the box, top to bottom. How much to enlarge follows the box's
    ; height - a box drawn around one line is only a little taller than its
    ; text - for the reason WordAtPoint explains: enlarging helps small text
    ; and ruins big text. The first reading that finds anything is used.
    static TextIn(x, y, w, h) {
        Ocr.Init()
        scales := (h < 60) ? [2, 3, 1] : (h < 200) ? [1.5, 1, 2.5] : [1, 1.5]
        for s in scales {
            if Ocr.maxDim                       ; the reader refuses anything bigger
                s := Min(s, Ocr.maxDim / Max(w, h))
            ; everything in the box, top to bottom; a paragraph gap is kept as
            ; a line break for the Summary card (see Lines.ahk)
            rows := PageRows(Ocr.Screen(x, y, w, h, s))
            if rows.Length
                return JoinRows(rows)
        }
        return ""
    }
}
