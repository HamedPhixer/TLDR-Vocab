;================================================================================
; Paragraph.ahk - what does this note actually say?
;================================================================================
; The SUMMARY card; the code calls it "paragraph".
; Ctrl + Win + Click anywhere in a block of text: a game's lore note, a blog
; paragraph, a wall of patch notes. It comes back as two or three sentences of
; plain English and the same translated.
;
; WHY IT READS THE WHOLE MONITOR
; A strip around the pointer cannot work here: make it big enough for three
; paragraphs and it swallows the menus above and below as well, and you can
; never tell what it took. So the whole screen under the pointer is read once,
; and the paragraph's extent is decided by the TEXT: lines that sit like
; consecutive lines of one block - gaps no bigger than a couple of lines,
; similar sizes, overlapping sideways - are joined, and everything else on
; screen is left alone. Two or three short paragraphs with small gaps between
; them group together, which is exactly what a game note looks like.
;
; HOW YOU KNOW WHAT IT TOOK
;   the outline      the block is drawn on screen for a moment, so you see the
;                    boundary as it happens
;   WHAT IT READ     the text itself is at the bottom of the card. If it starts
;                    mid-word or trails off, it missed something and you can
;                    aim again
;
; Reading a whole screen, then the block again enlarged, takes about 0.3 s
; rather than a strip's sixty milliseconds - nothing against the time spent
; reading the answer.
;
; Nothing here is saved: a summary is something you read once.
;================================================================================
#Requires AutoHotkey v2.0

LookupParagraphUnderMouse(*) {
    MouseGetPos(&mx, &my)
    if Popup.visible {
        Popup.Close()
        Sleep 40
    }
    try hit := ParagraphAtPoint(mx, my)
    catch as e {
        VocabLog("OCR (paragraph): " e.Message)
        Popup.Message("Could not read the screen: " e.Message, mx, my)
        return
    }
    if (!hit || StrLen(hit.text) < 20) {
        Popup.Message("No block of text under the pointer", mx, my)
        return
    }
    Outline.Flash(hit.x, hit.y, hit.w, hit.h)
    StartLookup(hit.text, "", Popup, hit, false, "paragraph")
}

; Like Translate, two reads: the whole monitor at its own size to find the
; block, then just the block enlarged by the engine's BlockScale for the
; words - small print reads far better that way. The second read is kept only if it found at least most
; of what the first did; otherwise the first stands.
ParagraphAtPoint(mx, my) {
    m := MonitorRectAt(mx, my)
    lines := Ocr.Screen(m[1], m[2], m[3], m[4], 1)
    block := BlockAround(lines, mx - m[1], my - m[2])
    if !block
        return ""
    found := {text: block.text, x: m[1] + block.x, y: m[2] + block.y, w: block.w, h: block.h}
    s := Ocr.Engine.BlockScale
    if (s <= Ocr.MaxScale(found.w, found.h)) {
        lines := Ocr.Screen(found.x, found.y, found.w, found.h, s)
        again := BlockAround(lines, (mx - found.x) * s, (my - found.y) * s)
        if (again && StrLen(again.text) >= StrLen(found.text) * 0.8)
            found.text := again.text
    }
    return found
}

; Every line that belongs with the one under the pointer, and the rectangle
; around the lot. A wider gap than the sentence lookup allows, so a blank line
; between two short paragraphs does not end the block.
BlockAround(lines, px, py) {
    rows := PageRows(lines)             ; see Lines.ahk
    if !rows.Length
        return ""
    here := 0, bestD := 1e9
    for i, r in rows {
        d := (py < r.y1) ? r.y1 - py : (py > r.y2) ? py - r.y2 : 0
        if (d < bestD && d <= r.h * 2 && px >= r.x1 - r.h * 2 && px <= r.x2 + r.h * 2)
            bestD := d, here := i
    }
    if !here
        return ""
    col := ColumnRows(rows, here)   ; the pointer's column only - see Lines.ahk
    rows := col.rows, here := col.at
    first := here, last := here
    while (first > 1 && SameFlow(rows[first - 1], rows[first]))
        first--
    while (last < rows.Length && SameFlow(rows[last], rows[last + 1]))
        last++

    ; at most about 3000 characters, the most a summary is asked for
    chars := 0
    loop last - first + 1 {
        chars += StrLen(rows[first + A_Index - 1].text) + 1
        if (chars > 3000) {
            last := first + A_Index - 1
            break
        }
    }
    x1 := 1e9, y1 := 1e9, x2 := -1e9, y2 := -1e9
    loop last - first + 1 {
        r := rows[first + A_Index - 1]
        x1 := Min(x1, r.x1), y1 := Min(y1, r.y1), x2 := Max(x2, r.x2), y2 := Max(y2, r.y2)
    }
    pad := 6
    return {text: JoinRows(rows, first, last), x: x1 - pad, y: y1 - pad, w: x2 - x1 + pad * 2, h: y2 - y1 + pad * 2}
}

; Consecutive lines of one flow of text. The gap allowance is generous - three
; line heights - because a blank line between two short paragraphs must not end
; the block. What stops it wandering into the next thing on screen is the rest:
; the lines have to be about the same size AND start at about the same left
; edge, which a menu bar, a tooltip or a differently indented block does not.
SameFlow(a, b) {
    gap := b.y1 - a.y2
    line := Max(a.h, b.h)
    return (gap < line * 3 && gap > -a.h * 0.6
        && Abs(a.h - b.h) < line * 0.5
        && Abs(a.x1 - b.x1) < line * 8      ; an indented first line is still the same flow
        && b.x1 < a.x2 && a.x1 < b.x2)
}

;--------------------------------------------------------------------------------
; The outline, drawn for a moment so the block's boundary is visible
;--------------------------------------------------------------------------------
; A window the size of the block with its middle cut out of the window region,
; so only a frame remains and the screen shows through. Click-through and
; never activated, and it goes up AFTER the screen has been read, so it can
; never end up in the picture.
class Outline {
    static g := "", timer := ""

    static Flash(x, y, w, h, ms := 900) {
        Outline.Clear()
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020 -DPIScale")    ; NOACTIVATE | TRANSPARENT
        g.BackColor := CGreen
        g.Show("NoActivate x" Round(x) " y" Round(y) " w" Round(w) " h" Round(h))
        outer := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", Round(w), "int", Round(h), "ptr")
        inner := DllCall("CreateRectRgn", "int", 3, "int", 3, "int", Round(w) - 3, "int", Round(h) - 3, "ptr")
        DllCall("CombineRgn", "ptr", outer, "ptr", outer, "ptr", inner, "int", 4)   ; RGN_DIFF
        DllCall("SetWindowRgn", "ptr", g.Hwnd, "ptr", outer, "int", true)           ; takes the region
        DllCall("DeleteObject", "ptr", inner)
        WinSetTransparent(200, g.Hwnd)
        Outline.g := g
        if !Outline.timer
            Outline.timer := ObjBindMethod(Outline, "Clear")
        SetTimer(Outline.timer, -ms)
    }

    static Clear() {
        if Outline.g {
            try Outline.g.Destroy()
            Outline.g := ""
        }
    }
}

;--------------------------------------------------------------------------------
; The card: the summary, then the text it was made from
;--------------------------------------------------------------------------------
RenderParagraph(g, W, st, owner) {
    lk := st.lk
    ai := (lk && lk.ai.data) ? lk.ai.data : ""
    f := Flow(g, 14, 10, W - 28)

    ModeSwitch(g, f, st, owner)
    CardLinks(g, f.x + f.w, f.y + 2, [PinAction(owner)
        , lk ? {text: "look up again", color: CBlue, w: 94, fn: (*) => owner.Again()} : ""])
    f.y += 26

    f.Label("IN SIMPLE ENGLISH", CBlue)
    if (!lk || !lk.ai.enabled)
        NoKeyLine(f, lk)
    else if !lk.ai.done
        f.Text(lk.ai.Waiting, CDim, "s9 Norm Italic")
    else if (ai && Dig(ai, "summary") != "")
        f.Text(ai["summary"], CText, "s10 Norm")
    else if KeyTrouble(lk)
        NoKeyLine(f, lk)
    else
        f.Text("Gemini: " lk.ai.note, CDim, "s8 Norm Italic")

    f.Label(Lang.Label())
    if (ai && Dig(ai, "persian") != "")
        f.Tr(ai["persian"], "s11 Norm")
    else if (!lk || !lk.fa.done)
        Ellipsis(f)
    else if (lk.fa.data && lk.fa.data["main"] != "") {
        f.Tr(lk.fa.data["main"], "s11 Norm")
        f.Text("translated line by line, not summarised", CDim, "s7 Norm Italic")
    } else
        f.Text("no translation found", CDim, "s8 Norm Italic")

    if (ai && Dig(ai, "note") != "")
        f.Text(ai["note"], CAmber, "s8 Norm")

    ; the evidence: if this starts mid-word or stops short, it missed something
    f.Label("WHAT IT READ")
    f.Text(st.word, CMuted, "s8 Norm")

    if lk {
        ; Google only while its line-by-line translation is the one shown
        src := []
        if (lk.fa.source != "" && !(ai && Dig(ai, "persian") != ""))
            src.Push(lk.fa.source)
        if (lk.ai.source != "")
            src.Push(lk.ai.source)
        if src.Length {
            f.y += 4
            f.Text(Join(src, "   " Chr(0xB7) "   "), CDim, "s7 Norm")
        }
    }
    return f.y + 8
}
