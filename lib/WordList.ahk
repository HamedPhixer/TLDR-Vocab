;================================================================================
; WordList.ahk - the dictionary window
;================================================================================
#Requires AutoHotkey v2.0

; Borderless but resizable: the window keeps WS_THICKFRAME so Windows still
; knows how to resize it, WM_NCCALCSIZE hands the frame's pixels back to the
; client area so nothing is drawn, and WM_NCHITTEST says which edge the
; pointer is on. The same hit test is what "lock" switches off - a locked
; window reports plain client area everywhere, so there is nothing to drag
; and no edge to pull.
;
; The one thing that frame still did on its own was paint itself: on losing
; focus Windows redraws the inactive frame, and with no frame area left it
; drew it straight over the window's edge - a white outline. WM_NCACTIVATE is
; answered with lParam -1, which is Windows' own "switch state, skip the
; repaint".
class Dict {
    static g := "", lv := "", search := "", view := "", pane := "", grip := ""
    static title := "", count := "", lockBtn := "", minBtn := "", closeBtn := ""
    static countX := 0, locked := 0, split := 0.5, gapY := 0, st := "", delArmed := 0
    static paneRect := "", renderedW := 0, filterer := "", renderer := ""

    static Top := 80, Pad := 18, Gap := 10

    static Build() {
        g := Gui("-Caption +Resize -MaximizeBox -DPIScale +MinSize380x420", "Vocabulary")
        g.BackColor := CBg
        g.MarginX := 0, g.MarginY := 0
        this.g := g
        this.st := {kind: "empty"}
        this.filterer := ObjBindMethod(Dict, "Refresh")
        this.renderer := ObjBindMethod(Dict, "RenderPane")
        sp := Float(IniRead(VocabIni(), "Window", "Split", 0.5))
        this.split := (sp >= 0.1 && sp <= 0.9) ? sp : 0.5

        g.SetFont("s11 Bold c" CText, FontUI)
        this.title := g.Add("Text", "x18 y12 BackgroundTrans +0x80", "Vocabulary")
        this.title.GetPos(, , &tw)
        this.countX := 18 + tw + 10
        g.SetFont("s9 Norm c" CMuted, FontUI)
        this.count := g.Add("Text", "x" this.countX " y16 w120 BackgroundTrans +0x80", "")
        g.SetFont("s9 Norm c" CDim, FontUI)
        this.lockBtn := Link(g.Add("Text", "x260 y15 w52 Right BackgroundTrans +0x80", "lock"), (*) => Dict.ToggleLock())
        g.SetFont("s13 Norm c" CMuted, FontUI)
        this.minBtn := Link(g.Add("Text", "x320 y6 w22 Center BackgroundTrans +0x80", Chr(0x2013)), (*) => WinMinimize(Dict.g.Hwnd))
        this.closeBtn := Link(g.Add("Text", "x346 y7 w22 Center BackgroundTrans +0x80", Chr(0xD7)), (*) => Dict.Hide())

        g.SetFont("s10 Norm c" CText, FontUI)
        this.search := g.Add("Edit", "x18 y46 w300 h24 -E0x200 Background" CCardHi)
        SendMessage(0x1501, 1, StrPtr("Search your words   " Chr(0xB7) "   Enter looks it up online"), this.search)
        SendMessage(0xD3, 3, 6 | (6 << 16), this.search)            ; EM_SETMARGINS
        this.search.OnEvent("Change", (*) => SetTimer(Dict.filterer, -120))
        g.Add("Button", "Default Hidden w0 h0", "go").OnEvent("Click", (*) => Dict.Enter())

        this.lv := g.Add("ListView", "x18 y80 w300 h200 -E0x200 -Hdr -Multi +LV0x10000 Background" CCard
            , ["Word", "Persian", "Meaning"])
        this.lv.ModifyCol(2, "Right")
        this.lv.OnEvent("ItemSelect", ObjBindMethod(Dict, "OnSelect"))
        DarkList(this.lv)
        il := DllCall("comctl32\ImageList_Create", "int", 1, "int", 26, "uint", 0x21, "int", 1, "int", 1, "ptr")
        SendMessage(0x1003, 1, il, this.lv)                          ; LVM_SETIMAGELIST: taller rows

        ; the divider's grip: a short line in the gap. No events, so clicks go
        ; through it to the window, which is what starts the drag
        this.grip := g.Add("Text", "x0 y0 w36 h2 Background" CTrack)

        this.view := Gui("+Parent" g.Hwnd " -Caption -DPIScale")
        this.view.BackColor := CCard
        this.view.MarginX := 0, this.view.MarginY := 0
        this.pane := ScrollPane(this.view)

        g.OnEvent("Size", ObjBindMethod(Dict, "OnSize"))
        g.OnEvent("Escape", ObjBindMethod(Dict, "OnEscape"))
        g.OnEvent("Close", (*) => Dict.Hide())
        this.locked := Integer(IniRead(VocabIni(), "Window", "Locked", 0))
        this.SetLock()
        ; make Windows re-ask WM_NCCALCSIZE now that the handler can answer
        DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37)
        DwmAttr(g.Hwnd, 33, 2)
        DwmAttr(g.Hwnd, 34, 0x402F2A)
        SetWindowIcon(g.Hwnd)
    }

    static Toggle() {
        if !this.g
            this.Build()
        if DllCall("IsWindowVisible", "ptr", this.g.Hwnd) {
            if (WinActive(this.g.Hwnd) && WinGetMinMax(this.g.Hwnd) != -1)
                this.Hide()
            else
                WinActivate(this.g.Hwnd)        ; also brings it back from the taskbar
            return
        }
        this.ShowWin()
    }

    static ShowWin(activate := true) {
        ini := VocabIni()
        w := Integer(IniRead(ini, "Window", "W", 540)), h := Integer(IniRead(ini, "Window", "H", 680))
        x := IniRead(ini, "Window", "X", ""), y := IniRead(ini, "Window", "Y", "")
        onScreen := false
        if (x != "" && y != "")
            loop MonitorGetCount() {
                MonitorGet(A_Index, &l, &t, &r, &b)
                if (x + 40 >= l && x + 40 < r && y + 10 >= t && y + 10 < b)
                    onScreen := true
            }
        if !onScreen {
            wa := WorkAreaAt(0, 0)
            x := wa[1] + (wa[3] - wa[1] - w) // 2, y := wa[2] + (wa[4] - wa[2] - h) // 2
        }
        this.g.Show((activate ? "" : "NoActivate ") "x" x " y" y " w" w " h" h)
        WinMove(x, y, w, h, this.g.Hwnd)        ; Show sized it with a frame it no longer has
        this.Refresh()
        this.RenderPane()
        if activate
            this.search.Focus()
    }

    static Hide() {
        this.SavePos()
        this.g.Hide()
    }

    static SavePos() {
        if (!this.g || !DllCall("IsWindowVisible", "ptr", this.g.Hwnd) || WinGetMinMax(this.g.Hwnd) = -1)
            return                              ; minimized, it sits at -32000
        WinGetPos(&x, &y, &w, &h, this.g.Hwnd)
        ini := VocabIni()
        IniWrite(x, ini, "Window", "X"), IniWrite(y, ini, "Window", "Y")
        IniWrite(w, ini, "Window", "W"), IniWrite(h, ini, "Window", "H")
    }

    static OnSize(g, minMax, w, h) {
        if (minMax = -1)
            return
        this.Layout(w, h)
        if (this.paneRect[3] != this.renderedW)
            SetTimer(this.renderer, -40)        ; new width: re-wrap once the drag settles
    }

    ; Everything below the search box follows from the split: the list gets
    ; that share of the height, the pane the rest, each with a floor
    static Layout(w, h) {
        P := this.Pad, top := this.Top
        x := w - P - 20
        this.closeBtn.Move(x, 7)
        this.minBtn.Move(x - 26, 6)
        this.lockBtn.Move(x - 26 - 58, 15)
        this.count.Move(this.countX, 16, Max(0, x - 26 - 58 - this.countX - 6))
        this.search.Move(P, 46, w - 2 * P, 24)
        avail := h - top - P - this.Gap
        lvH := Max(60, Min(Round(avail * this.split), avail - 140))
        paneH := avail - lvH
        this.lv.Move(P, top, w - 2 * P, lvH)
        cw := w - 2 * P - 22                    ; less the vertical scrollbar
        c1 := Min(130, Round(cw * 0.3)), c2 := Min(150, Round(cw * 0.34))
        this.lv.ModifyCol(1, c1), this.lv.ModifyCol(2, c2), this.lv.ModifyCol(3, cw - c1 - c2)
        this.gapY := top + lvH
        this.grip.Move((w - 36) // 2, this.gapY + 4, 36, 2)
        this.paneRect := [P, this.gapY + this.Gap, w - 2 * P, paneH]
        this.view.Show("NoActivate x" P " y" (this.gapY + this.Gap) " w" (w - 2 * P) " h" paneH)
        this.pane.Show(paneH)
        ; A resize here keeps the window's old pixels (that is what answering
        ; WM_NCCALCSIZE with 0 means), and a transparent Text that moves does
        ; not wipe the spot it left - so "lock", the dash and the cross left
        ; ghosts of themselves. The header strip is repainted from scratch.
        rc := Buffer(16)
        NumPut("int", 0, "int", 0, "int", w, "int", 42, rc)
        DllCall("RedrawWindow", "ptr", this.g.Hwnd, "ptr", rc, "ptr", 0, "uint", 0x85)  ; INVALIDATE|ERASE|ALLCHILDREN
    }

    ; the gap between the list and the pane, in window coordinates
    static OverDivider() {
        if (this.locked || !this.paneRect)
            return false
        MouseGetPos(&mx, &my)
        WinGetPos(&wx, &wy, &ww, , this.g.Hwnd)
        y := my - wy, x := mx - wx
        return (y >= this.gapY && y < this.gapY + this.Gap && x >= this.Pad && x < ww - this.Pad)
    }

    static DragSplit() {
        static ns := DllCall("LoadCursor", "ptr", 0, "ptr", 32645, "ptr")
        WinGetPos(&wx, &wy, &ww, &wh, this.g.Hwnd)
        avail := wh - this.Top - this.Pad - this.Gap
        DllCall("SetCapture", "ptr", this.g.Hwnd)
        last := -1
        while GetKeyState("LButton", "P") {
            DllCall("SetCursor", "ptr", ns)
            MouseGetPos(, &my)
            lvH := Max(60, Min(my - wy - this.Top - this.Gap // 2, avail - 140))
            if (lvH != last) {
                this.split := lvH / avail
                this.Layout(ww, wh)
                last := lvH
            }
            Sleep 15
        }
        DllCall("ReleaseCapture")
        IniWrite(Round(this.split, 3), VocabIni(), "Window", "Split")
    }

    static OnEscape(*) {
        if (this.search.Value != "") {
            this.search.Value := ""
            this.Refresh()
        } else
            this.Hide()
    }

    static ToggleLock() {
        this.locked := !this.locked
        IniWrite(this.locked, VocabIni(), "Window", "Locked")
        this.SetLock()
    }

    static SetLock() {
        this.lockBtn.SetFont("c" (this.locked ? CText : CDim))
        this.lockBtn.Value := this.locked ? "locked" : "lock"
    }

    ; The list, newest first, filtered by the search box. keep: a word whose
    ; row should stay selected afterwards.
    static Refresh(keep := "") {
        if !this.g
            return
        q := Trim(this.search.Value)
        this.lv.Opt("-Redraw")
        this.lv.Delete()
        n := 0, i := Store.words.Length, sel := 0
        while (i >= 1) {
            w := Store.words[i]
            if (q = "" || InStr(w["word"], q) || InStr(Dig(w, "persian"), q) || InStr(Dig(w, "meaning"), q)) {
                row := this.lv.Add(, w["word"], Dig(w, "persian"), Dig(w, "meaning"))
                n++
                if (keep != "" && w["word"] == keep)
                    sel := row
            }
            i--
        }
        if sel
            this.lv.Modify(sel, "Select Focus Vis")
        this.lv.Opt("+Redraw")
        total := Store.words.Length
        this.count.Value := (q = "") ? total " word" ((total = 1) ? "" : "s") : n " of " total
    }

    static Enter() {
        q := Trim(this.search.Value)
        if (q = "")
            return
        if (i := Store.Find(q)) {
            this.ShowEntry(Store.words[i])
            return
        }
        StartLookup(q, "", Dict)
    }

    static OnSelect(lv, item, selected) {
        if !selected
            return
        word := lv.GetText(item, 1)
        if (this.st.kind = "entry" && this.st.rec["word"] == word)
            return                              ; already showing - a re-select after an edit
        if (i := Store.Find(word))
            this.ShowEntry(Store.words[i])
    }

    static ShowEntry(rec) {
        this.st := {kind: "entry", rec: rec}
        this.delArmed := 0
        this.pane.scroll := 0
        this.RenderPane()
    }

    ; Picking a meaning in a saved entry rewrites what is saved for the word
    static ChooseSaved(key) {
        rec := this.st.rec
        if (key = "ai") {
            ai := Dig(rec, "ai")
            if !(text := AiText(ai))
                return
            rec["meaning"] := text, rec["persian"] := Dig(ai, "persian"), rec["pos"] := Dig(ai, "pos")
        } else if RegExMatch(key, "^g(\d+)\.(\d+)$", &m) {
            grp := Dig(rec, "defs", Integer(m[1]))
            s := Dig(grp, "senses", Integer(m[2]))
            if !s
                return
            rec["meaning"] := s["d"], rec["pos"] := grp["pos"]
            p := (Dig(s, "fa") != "") ? s["fa"] : FaForPos(Dig(rec, "fa"), grp["pos"])
            if (p = "")
                p := Dig(rec, "fa", "main")
            if (p != "")
                rec["persian"] := p
        } else
            return
        Store.Save()
        this.Refresh(rec["word"])
        this.RenderPane()
    }

    ; Dict is a view too: a search from the box lands here
    static Begin(word, context, anchor, ocr := false, mode := "word") {
        if (this.st.kind = "lookup" && this.st.lk)
            this.st.lk.Cancel()
        this.st := {kind: "lookup", word: word, context: context, lk: "", choice: "", userChose: false
            , expanded: true, flash: "", maxSenses: 60, mode: mode}
        this.pane.scroll := 0
        this.RenderPane()
    }

    static Attach(lk) => this.st.lk := lk

    static Update(lk) {
        if (this.st.kind = "lookup" && this.st.lk == lk)
            this.RenderPane()
    }

    static Again() {
        st := this.st
        if (st.kind = "lookup")
            StartLookup(st.word, st.context, Dict, "", false, st.mode)
    }

    static Switch(mode, *) {
        st := this.st
        if (st.kind = "lookup")
            StartLookup(st.word, st.context, Dict, "", false, mode, true)
    }

    static Choose(key) {
        this.st.choice := key, this.st.userChose := true
        this.RenderPane()
    }

    static ToggleMore() {
        this.st.expanded := !this.st.expanded
        this.RenderPane()
    }

    static Save() {
        st := this.st
        if (st.kind != "lookup" || !st.lk)
            return
        res := Store.Upsert(BuildRecord(st))
        st.flash := ((res = "saved") ? "saved " : "updated ") Chr(0x2713)
        this.Refresh(st.word)
        this.RenderPane()
    }

    static Delete() {
        if (A_TickCount - this.delArmed > 3000) {
            this.delArmed := A_TickCount
            this.RenderPane()
            SetTimer(this.renderer, -3100)      ; the prompt goes back by itself
            return
        }
        this.delArmed := 0
        if (i := Store.Find(this.st.rec["word"]))
            Store.Remove(i)
        this.st := {kind: "empty"}
        this.Refresh()
        this.RenderPane()
    }

    static RenderPane() {
        if (!this.g || !this.paneRect)
            return
        r := this.paneRect
        kind := this.st.kind
        if (kind = "lookup")
            this.pane.Build(r[3], (c, W) => RenderLookup(c, W, Dict.st, Dict))
        else if (kind = "entry")
            this.pane.Build(r[3], (c, W) => RenderEntry(c, W, Dict.st))
        else
            this.pane.Build(r[3], (c, W) => Dict.DrawEmpty(c, W))
        this.pane.Show(r[4])
        this.renderedW := r[3]
    }

    static DrawEmpty(c, W) {
        f := Flow(c, 14, 14, W - 28)
        f.Text("Pick a word from the list, or type one above and press Enter.", CMuted, "s9 Norm")
        if (Keys.cur["Word"] != "")
            f.Text("Anywhere on screen, " Keys.Label(Keys.cur["Word"]) " on a word looks it up, and its + save puts it here."
                , CDim, "s8 Norm")
        return f.y + 10
    }
}

; Dark scrollbars need the dark theme FORCED: "allow dark" only takes effect
; when Windows itself is in dark app mode, and in light mode the list came out
; with white scrollbars. The theme also brings its dark-blue selection and
; faint lines between the columns; every dark list theme draws those lines.
;
; The three helpers are exported by number only, and DllCall cannot call by
; number - so they are looked up with GetProcAddress and called by address.
; Each is skipped if this Windows lacks it; the theme is applied regardless.
DarkList(lv) {
    static ux := DllCall("LoadLibrary", "str", "uxtheme.dll", "ptr")
    static setMode := DllCall("GetProcAddress", "ptr", ux, "ptr", 135, "ptr")   ; SetPreferredAppMode
    static flush   := DllCall("GetProcAddress", "ptr", ux, "ptr", 136, "ptr")   ; FlushMenuThemes
    static allow   := DllCall("GetProcAddress", "ptr", ux, "ptr", 133, "ptr")   ; AllowDarkModeForWindow
    if setMode
        DllCall(setMode, "int", 2)                                      ; 2 = force dark
    if flush
        DllCall(flush)
    if allow
        DllCall(allow, "ptr", lv.Hwnd, "int", 1)
    DllCall("uxtheme\SetWindowTheme", "ptr", lv.Hwnd, "str", "DarkMode_Explorer", "ptr", 0)
}

DictNcCalc(wParam, lParam, msg, hwnd) {
    if (wParam && Dict.g && hwnd = Dict.g.Hwnd)
        return 0                                ; the whole window is client area
}

DictNcActivate(wParam, lParam, msg, hwnd) {
    if (Dict.g && hwnd = Dict.g.Hwnd)
        return DllCall("DefWindowProc", "ptr", hwnd, "uint", msg, "ptr", wParam, "ptr", -1, "ptr")
}

DictHitTest(wParam, lParam, msg, hwnd) {
    if (!Dict.g || hwnd != Dict.g.Hwnd)
        return
    if Dict.locked
        return 1                                ; HTCLIENT: nothing to drag, no edge to pull
    x := lParam << 48 >> 48, y := lParam << 32 >> 48
    WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    bw := 7
    onL := x < wx + bw, onR := x >= wx + ww - bw, onT := y < wy + bw, onB := y >= wy + wh - bw
    if (onT && onL)
        return 13
    if (onT && onR)
        return 14
    if (onB && onL)
        return 16
    if (onB && onR)
        return 17
    if onL
        return 10
    if onR
        return 11
    if onT
        return 12
    if onB
        return 15
    return (y < wy + 40) ? 2 : 1                ; the top strip drags, like a title bar
}

DictMouseDown(wParam, lParam, msg, hwnd) {
    if (Dict.g && hwnd = Dict.g.Hwnd && Dict.OverDivider()) {
        Dict.DragSplit()
        return 0
    }
}

; The wheel scrolls whichever pane the pointer is over - the popup first, as
; it sits on top - and otherwise leaves the message to the list
PaneWheel(wParam, lParam, msg, hwnd) {
    MouseGetPos(&mx, &my)
    delta := (wParam >> 16) & 0xFFFF
    if (delta > 0x7FFF)
        delta -= 0x10000
    for sp in [Popup.visible ? Popup.pane : "", Dict.pane]
        if (sp && sp.Over(mx, my)) {
            sp.ScrollBy(Round(-delta / 120 * 60))
            return 0
        }
}

DictMoved(wParam, lParam, msg, hwnd) {
    if (Dict.g && hwnd = Dict.g.Hwnd)
        Dict.SavePos()
}
