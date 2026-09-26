;================================================================================
; Sentence.ahk - explain a whole sentence instead of one word
;================================================================================
; The TRANSLATE card; the code calls it "sentence", as saved records do.
; Shift + Win + Click on any sentence on screen. It is read with the same OCR as the
; word lookup, then shown in plain English and translated. A selection of more
; than four words (Win + `) comes here too, since a dictionary has nothing to
; say about a sentence.
;
; WHAT NEEDS WHAT
;   the translation the ordinary translators, so it works with no Gemini key
;   plain English   Gemini only. Without a key that section says so, and the
;                   translation still stands on its own.
;
; Everything else is the word popup's and is reused unchanged: the scrolling,
; "+ save", "look up again", the speaker, the pin, the placing. Only the card is
; different, and it is drawn here.
;
; READING THE SENTENCE OFF THE SCREEN
; 1. The block: the lines around the pointer that sit like one piece of text -
;    the gap between them no bigger than a line (a blank line ends it),
;    similar heights, overlapping left and right - and cut at any line that
;    ENDS with a stop (. ! ? : ; or an ellipsis): what follows it is
;    something else. (docs\decisions.md has the four rules this replaced.)
; 2. The sentences: that text cut at the stops inside it - a stop followed by
;    a space and a word - and up to ten of them taken, the one the pointer is
;    on first, then the next, then the one before. Bits of one to three words
;    ("Wait." "No.") do not count towards the ten. Or, set in Settings, only
;    the sentence clicked. That is all SpanRange does; for anything more
;    exact there is the box.
; What was taken is outlined for a moment, like the summary's block.
;================================================================================
#Requires AutoHotkey v2.0

LookupSentenceUnderMouse(*) {
    MouseGetPos(&mx, &my)
    if Popup.visible {
        Popup.Close()
        Sleep 40
    }
    try hit := SentenceAtPoint(mx, my)
    catch as e {
        VocabLog("OCR (sentence): " e.Message)
        Popup.Message("Could not read the screen: " e.Message, mx, my)
        return
    }
    if (!hit || StrLen(hit.text) < 6) {
        Popup.Message("No sentence under the pointer", mx, my)
        return
    }
    Outline.Flash(hit.x - 4, hit.y - 4, hit.w + 8, hit.h + 8)
    StartLookup(hit.text, "", Popup, hit, false, "sentence")
}

; Two reads. The first is the whole monitor at its own size, only to find the
; block: a strip around the pointer cut the ends off any line wider than the
; strip, which on a 1920 or 2560 px screen is most lines of an article. The
; second is just that block, enlarged by the engine's BlockScale (1.5x for
; Windows' reader) for the words themselves; the same sentences are then
; taken from it. Small print the first read misses gets the old strip.
SentenceAtPoint(mx, my) {
    m := MonitorRectAt(mx, my)
    lines := Ocr.Screen(m[1], m[2], m[3], m[4], 1)
    if (hit := BlockAt(lines, mx - m[1], my - m[2])) {
        found := {text: hit.text, x: m[1] + hit.x, y: m[2] + hit.y, w: hit.w, h: hit.h}
        pad := 6, s := Ocr.Engine.BlockScale
        rx := m[1] + hit.bx - pad, ry := m[2] + hit.by - pad, rw := hit.bw + pad * 2, rh := hit.bh + pad * 2
        if (s <= Ocr.MaxScale(rw, rh)) {
            lines := Ocr.Screen(rx, ry, rw, rh, s)
            if (again := BlockAt(lines, (mx - rx) * s, (my - ry) * s))
                found.text := again.text
        }
        return found
    }
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    w := 1000, h := 320, s := Ocr.Engine.BlockScale
    rx := Max(vx, Min(mx - w // 2, vx + vw - w))
    ry := Max(vy, Min(my - h // 2, vy + vh - h))
    lines := Ocr.Screen(rx, ry, w, h, s)
    if (hit := BlockAt(lines, (mx - rx) * s, (my - ry) * s))
        return {text: hit.text, x: rx + hit.x / s, y: ry + hit.y / s, w: hit.w / s, h: hit.h / s}
    return ""
}

; The line under the pointer, joined with the lines around it that belong to
; the same block, then cut back to the sentences SpanRange takes. Returns
; the text, the rectangle around the lines it came from (x y w h), and the
; rectangle around the whole block (bx by bw bh).
BlockAt(lines, px, py, whole := true) {
    rows := PageRows(lines)             ; see Lines.ahk
    if !rows.Length
        return ""
    here := 0, bestD := 1e9
    for i, r in rows {
        d := (py < r.y1) ? r.y1 - py : (py > r.y2) ? py - r.y2 : 0
        if (d < bestD && d <= r.h * 1.3 && px >= r.x1 - r.h && px <= r.x2 + r.h)
            bestD := d, here := i
    }
    if !here
        return ""
    col := ColumnRows(rows, here)
    rows := col.rows, here := col.at
    first := here, last := here
    while (first > 1 && SameBlock(rows[first - 1], rows[first]))
        first--
    while (last < rows.Length && SameBlock(rows[last], rows[last + 1]))
        last++
    ; A full stop at the END of a line ends the text there - the next line is
    ; something else (a chat message, a list item, a line of dialogue). Only
    ; full stops inside a line, followed by a space and a word, separate
    ; sentences of one text; SpanRange counts those.
    lo := here, hi := here
    while (lo > first && !EndsText(rows[lo - 1]))
        lo--
    while (hi < last && !EndsText(rows[hi]))
        hi++
    first := lo, last := hi

    all := "", lineStart := 1, starts := Map()
    loop last - first + 1 {
        i := first + A_Index - 1
        if (all != "")
            all .= " "
        starts[i] := StrLen(all) + 1
        if (i = here)
            lineStart := starts[i]
        all .= rows[i].text
    }
    ; where the pointed-at word sits in all of that, so a sentence is cut
    ; around the word rather than around its line - a line can hold the end of
    ; one sentence and the start of another
    at := lineStart
    best := 1e9
    for i, w in rows[here].words {
        d := (px < w.x) ? w.x - px : (px > w.x + w.w) ? px - w.x - w.w : 0
        if (d < best) {
            best := d
            ahead := []
            loop i - 1
                ahead.Push(rows[here].words[A_Index].text)
            at := lineStart + StrLen(Join(ahead, " ")) + (i > 1 ? 1 : 0)
        }
    }
    ; the lines the chosen sentences came from - what the outline shows and
    ; the popup keeps clear of - and the whole block, for the second read
    span := SpanRange(all, at, whole)
    x1 := 1e9, y1 := 1e9, x2 := -1e9, y2 := -1e9
    bx1 := 1e9, by1 := 1e9, bx2 := -1e9, by2 := -1e9
    loop last - first + 1 {
        i := first + A_Index - 1, r := rows[i]
        bx1 := Min(bx1, r.x1), by1 := Min(by1, r.y1), bx2 := Max(bx2, r.x2), by2 := Max(by2, r.y2)
        if (starts[i] <= span[2] && starts[i] + StrLen(r.text) - 1 >= span[1])
            x1 := Min(x1, r.x1), y1 := Min(y1, r.y1), x2 := Max(x2, r.x2), y2 := Max(y2, r.y2)
    }
    if (x1 > x2)                                ; cannot happen, but never an empty rectangle
        x1 := bx1, y1 := by1, x2 := bx2, y2 := by2
    ; a list's bullet dot is not part of what it says
    return {text: RegExReplace(Trim(SubStr(all, span[1], span[2] - span[1] + 1)), "^[" Chr(0x2022) Chr(0xB7) Chr(0x25CF) "]\s*")
        , x: x1, y: y1, w: x2 - x1, h: y2 - y1, bx: bx1, by: by1, bw: bx2 - bx1, bh: by2 - by1}
}

; What counts as a stop: . ! ? : ; and the ellipsis character, with any
; closing quote or bracket riding along. A regex piece, used both ways below.
StopMark() => "[.!?:;" Chr(0x2026) "][" Chr(34) Chr(0x201D) Chr(0x2019) "'\)\]]?"

; a line that finishes on a stop ends the text there
EndsText(row) => RegExMatch(row.text, StopMark() "$")

; Where the Translate card ends and Summary begins, for a selection or a box:
; they have no pointer to cut sentences around, so it goes by length.
SentenceMaxWords() => 80

; How many sentences Translate takes: 10 (the passage, the default) or 1
; (only the sentence clicked) - Settings > TRANSLATION, [Translation]
; Sentences in Vocab.ini. Read on every lookup, so a change counts at once.
TranslateScope() => (IniRead(VocabIni(), "Translation", "Sentences", 10) = 1) ? 1 : 10

; The sentences to take, as [first character, last character] of all, given
; the character where the pointed-at word starts. The text is cut at every
; stop followed by a space (see StopMark); the one the pointer is on is
; taken, then the next, then the one before, and so on, until TranslateScope
; are taken or none are left - the text itself already ends at a line that
; finishes on a stop, so ten is only a safety limit. A bit of one to three
; words ("Wait." "No.") comes along but does not count. Set to one, only the
; sentence clicked is taken, bits and all: exactly up to its first stop.
; whole := false takes only the sentence the word is in - the example a word
; lookup keeps.
SpanRange(all, at, whole := true) {
    most := whole ? TranslateScope() : 1
    ; the example kept with a word is a whole sentence: there only . ! ? and
    ; the ellipsis cut, or a colon would leave Gemini half a sentence of context
    tail := (whole ? StopMark() : "[.!?" Chr(0x2026) "][" Chr(34) Chr(0x201D) Chr(0x2019) "'\)\]]?") "(\s|$)"
    spans := [], p := 1
    while (p <= StrLen(all)) {
        e := RegExMatch(all, tail, &m, p) ? m.Pos + m.Len - 1 : StrLen(all)
        spans.Push([p, e])
        p := e + 1
    }
    if !spans.Length
        return [1, StrLen(all)]
    k := spans.Length
    for i, sp in spans
        if (at <= sp[2]) {
            k := i
            break
        }
    if (!whole || most = 1)
        return spans[k]
    counts := (i) => CountWords(SubStr(all, spans[i][1], spans[i][2] - spans[i][1] + 1)) > 3
    a := k, b := k, taken := counts(k) ? 1 : 0, nextSide := true
    while (taken < most && (a > 1 || b < spans.Length)) {
        if (nextSide && b < spans.Length)
            b++, taken += counts(b) ? 1 : 0
        else if (!nextSide && a > 1)
            a--, taken += counts(a) ? 1 : 0
        nextSide := !nextSide
    }
    return [spans[a][1], spans[b][2]]
}

CountWords(s) => StrSplit(Trim(s), " ").Length

; Two lines belong together when they sit like consecutive lines of one block:
; a gap no bigger than a line, much the same height, and overlapping sideways.
SameBlock(a, b) {
    gap := b.y1 - a.y2
    return (gap < Max(a.h, b.h) * 1.1 && gap > -a.h * 0.6
        && Abs(a.h - b.h) < Max(a.h, b.h) * 0.45
        && b.x1 < a.x2 && a.x1 < b.x2)
}

;--------------------------------------------------------------------------------
; The card. Same popup, same scrolling - only what is drawn inside differs.
;--------------------------------------------------------------------------------
RenderSentence(g, W, st, owner) {
    lk := st.lk
    ai := (lk && lk.ai.data) ? lk.ai.data : ""
    f := Flow(g, 14, 10, W - 28)
    saved := Store.Find(st.word)
    action := (st.flash != "") ? st.flash : saved ? "saved " Chr(0x2713) : "+ save"

    sx := ModeSwitch(g, f, st, owner)
    g.SetFont("s11 Norm c" CMuted, "Segoe MDL2 Assets")         ; the speaker glyph
    Link(g.Add("Text", "x" sx " y" f.y " w20 BackgroundTrans +0x80", Chr(0xE767))
        , (*) => Speak.Say(st.word))
    acts := [PinAction(owner), {text: action, color: (saved || st.flash != "") ? CMuted : CGreen, w: 84, fn: (*) => owner.Save()}]
    if lk
        acts.Push({text: "look up again", color: CBlue, w: 94, fn: (*) => owner.Again()})
    CardLinks(g, f.x + f.w, f.y + 2, acts)
    f.y += 26

    shown := (ai && Dig(ai, "fixed") != "") ? ai["fixed"] : st.word
    f.Text(shown, CText, "s11 Norm", "", 3)
    if (ai && Dig(ai, "fixed") != "" && Dig(ai, "fixed") != st.word)
        f.Text("tidied up from what the screen said", CDim, "s7 Norm Italic")

    f.Label("IN SIMPLE ENGLISH", CBlue)
    if (!lk || !lk.ai.enabled)
        NoKeyLine(f, lk)
    else if !lk.ai.done
        f.Text(lk.ai.Waiting, CDim, "s9 Norm Italic")
    else if (ai && Dig(ai, "simple") != "")
        f.Text(ai["simple"], CText, "s10 Norm")
    else if KeyTrouble(lk)
        NoKeyLine(f, lk)
    else
        f.Text("Gemini: " lk.ai.note, CDim, "s8 Norm Italic")

    f.Label(Lang.Label())
    if (ai && Dig(ai, "persian") != "")
        f.Tr(ai["persian"], "s12 Norm")
    else if (!lk || !lk.fa.done)
        Ellipsis(f)
    else if (lk.fa.data && lk.fa.data["main"] != "")
        f.Tr(lk.fa.data["main"], "s12 Norm")
    else
        f.Text("no translation found  (" (lk ? Join(lk.fa.tried, ", ") : "") ")", CDim, "s8 Norm Italic")

    if (ai && Dig(ai, "note") != "")
        f.Text(ai["note"], CAmber, "s8 Norm")

    if lk {
        ; Google only while its translation is the one on the card: once
        ; Gemini's translation has replaced it, naming Google would mislead
        src := []
        if (lk.fa.source != "" && !(ai && Dig(ai, "persian") != ""))
            src.Push(lk.fa.source (lk.fa.cached ? " (saved copy)" : ""))
        if (lk.ai.source != "")
            src.Push(lk.ai.source)
        if src.Length {
            f.y += 4
            f.Text(Join(src, "   " Chr(0xB7) "   "), CDim, "s7 Norm")
        }
    }
    return f.y + 8
}

; TRANSLATE | SUMMARY at the top of both cards. The one showing is blue; the
; other is a link that redoes the same text the other way - for when the
; guess by length was wrong. Returns where the next thing on the line can go.
; Inside the code the two stay "sentence" and "paragraph", which is what saved
; records and Vocab.ini already say.
ModeSwitch(g, f, st, owner) {
    x := f.x
    for m in [["sentence", "TRANSLATE"], ["paragraph", "SUMMARY"]] {
        on := (st.mode = m[1])
        g.SetFont("s7 Bold c" (on ? CBlue : CDim), FontUI)
        c := g.Add("Text", "x" x " y" (f.y + 6) " BackgroundTrans +0x80", m[2])
        if !on
            Link(c, ObjBindMethod(owner, "Switch", m[1]))
        c.GetPos(, , &cw)
        x += cw
        if (A_Index = 1) {
            g.SetFont("s7 Norm c" CDim, FontUI)
            c := g.Add("Text", "x" (x + 5) " y" (f.y + 6) " BackgroundTrans +0x80", "|")
            c.GetPos(, , &cw)
            x += cw + 10
        }
    }
    return x + 10
}

; What the switch keeps: every lookup of the text on the card, by mode, so
; switching back shows the answer already there and only a mode not asked yet
; costs a Gemini request. Only the latest text is kept; "look up again" asks
; afresh and replaces it.
class ModeMemo {
    static text := "", lks := Map()

    static Get(word, mode) => (word == this.text && this.lks.Has(mode)) ? this.lks[mode] : ""

    static Put(lk) {
        if !(lk.word == this.text)
            this.text := lk.word, this.lks := Map()
        this.lks[lk.mode] := lk
    }
}

; A saved sentence sits in the same list as the words, marked as one: the
; sentence in place of the word, the plain English as its meaning.
SentenceRecord(st) {
    lk := st.lk
    ai := (lk && lk.ai.data) ? lk.ai.data : ""
    fa := (lk && lk.fa.data) ? lk.fa.data : ""
    src := []
    if lk {
        if (lk.fa.source != "" && !(ai && Dig(ai, "persian") != ""))
            src.Push(lk.fa.source)
        if (lk.ai.source != "")
            src.Push(lk.ai.source)
    }
    return Map("word", (ai && Dig(ai, "fixed") != "") ? ai["fixed"] : st.word
        , "kind", "sentence", "lemma", "", "pos", "sentence", "phonetic", ""
        , "meaning", ai ? Dig(ai, "simple") : ""
        , "persian", (ai && Dig(ai, "persian") != "") ? ai["persian"] : (fa ? fa["main"] : ""), "lang", Lang.Code()
        , "note", ai ? Dig(ai, "note") : "", "ai", ai ? ai : ""
        , "examples", [], "defs", [], "fa", fa ? fa : Map()
        , "added", Now(), "source", Join(src, ", ")
        , "review", Map("box", 1, "due", "", "reviews", 0, "lapses", 0, "history", []))
}
