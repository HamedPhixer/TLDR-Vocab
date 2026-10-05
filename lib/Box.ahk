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
; THE SCREEN FREEZES WHEN THE KEY IS PRESSED
; A tooltip that shows while the mouse rests on something - in a game, say -
; is gone the moment the mouse moves to draw, and the dimming covering the
; screen can be enough to close it too. So the first thing the key does is
; take a picture of the whole screen, before anything of Vocab's is on it, and
; show that picture under the dimming: the box is drawn on the screen as it
; was, and read from the picture, not from the screen as it is by then.
; The picture lives only in memory, in the window that shows it, and goes
; with that window once the box is read or cancelled - nothing is saved, and
; the clipboard is not touched. A whole 4K screen is about 33 MB for those
; few seconds. If Windows cannot make a picture that big, the box works as
; it used to, on the live screen.
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
    else if !Box.still                  ; not while the last box is still being read
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
    static shot := "", still := ""      ; the frozen screen, and the window showing it

    static Begin() {
        if Popup.visible {
            Popup.Close()
            Sleep 40
        }
        if !this.ticker
            this.ticker := ObjBindMethod(Box, "Track"), this.giveUp := ObjBindMethod(Box, "Cancel")
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        this.Freeze(vx, vy, vw, vh)
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 -DPIScale")    ; NOACTIVATE
        g.BackColor := "000000"
        g.Show("NoActivate x" vx " y" vy " w" vw " h" vh)
        WinSetTransparent(70, g.Hwnd)
        this.dim := g
        this.active := true, this.dragging := false
        SetTimer(this.giveUp, -20000)
    }

    ; The picture of the screen, shown over it - see THE SCREEN FREEZES above.
    ; The window takes the bitmap as its own, without copying it, and frees it
    ; when it is destroyed (Thaw).
    static Freeze(vx, vy, vw, vh) {
        if !(this.shot := Ocr.Shot())
            return
        s := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 -DPIScale")    ; NOACTIVATE
        try s.Add("Picture", "x0 y0", "HBITMAP:" this.shot.hbm)
        catch {
            DllCall("DeleteObject", "ptr", this.shot.hbm)
            s.Destroy(), this.shot := ""
            return
        }
        s.Show("NoActivate x" vx " y" vy " w" vw " h" vh)
        this.still := s
    }

    static Thaw() {
        if this.still {
            try this.still.Destroy()                    ; the picture goes with it
        } else if this.shot
            DllCall("DeleteObject", "ptr", this.shot.hbm)
        this.still := "", this.shot := ""
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
        this.Clear(true)                        ; the frozen screen stays until it is read
        if (r[3] < 8 || r[4] < 8) {
            this.Thaw()
            Popup.Message("Drag a box around the text", r[1], r[2])
            return
        }
        if !this.shot
            Sleep 60                            ; let the dimming leave the screen
        Box.Read(r[1], r[2], r[3], r[4])
    }

    static Cancel(*) {
        this.Clear()
    }

    static Clear(keepStill := false) {
        if this.ticker
            SetTimer(this.ticker, 0), SetTimer(this.giveUp, 0)
        for g in [this.frame, this.dim]
            if g
                try g.Destroy()
        this.frame := "", this.dim := ""
        this.active := false, this.dragging := false
        if !keepStill
            this.Thaw()
    }

    ;----------------------------------------------------------------------------
    ; Reading it
    ;----------------------------------------------------------------------------
    static Read(x, y, w, h) {
        cut := false, err := ""
        try text := Box.TextIn(x, y, w, h, &cut, this.shot)
        catch as e
            err := e
        this.Thaw()                             ; read - the live screen comes back
        if err {
            VocabLog("OCR (box): " err.Message)
            Popup.Message("Could not read the screen: " err.Message, x, y + h)
            return
        }
        if (text = "") {
            Popup.Message("No text in the box", x, y + h)
            return
        }
        Outline.Flash(x - 3, y - 3, w + 6, h + 6)
        n := CountWords(text)
        mode := (n <= 4) ? "word" : (n <= SentenceMaxWords()) ? "sentence" : "paragraph"
        if (mode != "paragraph")
            text := RegExReplace(text, "\s+", " ")
        if (mode = "word" && (text := CleanWord(text)) = "") {
            Popup.Message("No word in the box", x, y + h)
            return
        }
        ; the popup keeps clear of the box if it can - see Popup.Plan
        StartLookup(text, "", Popup, {x: x, y: y, w: w, h: h, cut: cut}, mode = "word", mode)
    }

    ; The text in the box, top to bottom. How much to enlarge follows the box's
    ; height - a box drawn around one line is only a little taller than its
    ; text - for the reason WinOcr.WordPasses explains: enlarging helps small
    ; text and ruins big text. The first reading that finds anything is used.
    ; No more than a summary takes (SummaryMaxChars), whole lines; cut says
    ; some were left out. With a shot (Ocr.Shot) the box is read out of that
    ; picture, not the live screen.
    static TextIn(x, y, w, h, &cut := false, shot := "") {
        for s in Ocr.Engine.BoxScales(h) {
            ; everything in the box, top to bottom; a paragraph gap is kept as
            ; a line break for the Summary card (see Lines.ahk)
            rows := PageRows(Ocr.Screen(x, y, w, h, s, shot))
            if rows.Length {
                last := LastRowWithin(rows, 1, rows.Length)
                cut := last < rows.Length
                return JoinRows(rows, 1, last)
            }
        }
        return ""
    }
}
