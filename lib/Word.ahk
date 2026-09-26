;================================================================================
; Word.ahk - the word under the mouse, and the selected text
;================================================================================
#Requires AutoHotkey v2.0

LookupUnderMouse(*) {
    MouseGetPos(&mx, &my)
    if Popup.visible {                  ; never read our own popup back
        Popup.Close()
        Sleep 40
    }
    try hit := WordAtPoint(mx, my)
    catch as e {
        VocabLog("OCR: " e.Message)
        Popup.Message("Could not read the screen: " e.Message, mx, my)
        return
    }
    if !hit {
        Popup.Message("No text under the pointer", mx, my)
        return
    }
    StartLookup(hit.word, hit.context, Popup, hit, true)
}

LookupSelection(*) {
    MouseGetPos(&mx, &my)
    ; or Ctrl+C goes out as Ctrl+Win+C - or with whatever the key was changed to
    for k in ["LWin", "RWin", "Alt", "Shift", "Ctrl"]
        KeyWait(k, "T1")
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    text := ClipWait(0.6) ? A_Clipboard : ""
    A_Clipboard := saved
    saved := ""
    text := Trim(RegExReplace(text, "\s+", " "))
    if (text = "") {
        LookupUnderMouse()
        return
    }
    if (StrLen(text) > 3000)            ; the paragraph lookup's own limit
        text := SubStr(text, 1, 3000)
    ; Any length, sent where it fits: a few words to the dictionary, a
    ; sentence or a short run of them to the sentence card (explained and
    ; translated), anything longer to the paragraph card (summarised) - the
    ; same split the click keys make.
    n := CountWords(text)
    mode := (n <= 4) ? "word" : (n <= SentenceMaxWords()) ? "sentence" : "paragraph"
    if (mode = "word" && (text := CleanWord(text)) = "") {
        Popup.Message("No word in the selection", mx, my)
        return
    }
    StartLookup(text, "", Popup, {x: mx, y: my - 10, w: 1, h: 20}, false, mode)
}

; OCR a band around the pointer and take the word it is on - or nearly on.
; The band is centred on the pointer both ways, and enlarged before reading.
; Which bands, and how much to enlarge each, is the OCR engine's own measured
; sweet spot - Windows' reader's is explained with WinOcr.WordPasses.
WordAtPoint(mx, my) {
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    passes := Ocr.Engine.WordPasses
    for i, pass in passes {
        rx := Max(vx, Min(mx - pass.w // 2, vx + vw - pass.w))
        ry := Max(vy, Min(my - pass.h // 2, vy + vh - pass.h))
        lines := Ocr.Screen(rx, ry, pass.w, pass.h, pass.s)
        ; A word running into the edge of the band is a word cut in half, and
        ; half a word is worse than another try - unless this was the last one.
        edge := (i < passes.Length) ? [Round(pass.w * pass.s), Round(pass.h * pass.s)] : ""
        if (hit := PickWord(lines, (mx - rx) * pass.s, (my - ry) * pass.s, edge)) {
            k := pass.s
            out := {word: hit.word, context: hit.context
                , x: rx + hit.x / k, y: ry + hit.y / k, w: hit.w / k, h: hit.h / k}
            if (hit.ctx && CutByBand(hit.ctx, Round(pass.w * k), Round(pass.h * k)))
                out.context := WholeSentence(out)
            return out
        }
    }
    return ""
}

; The band is narrower than a line of an article, so the sentence a word came
; with can be missing its ends - and Gemini reads the meaning from it. When
; the sentence's lines run into the band's edge, it is read again the way
; Translate reads, from the whole monitor (Sentence.ahk), keeping to the one
; sentence. Only then: a sentence that fits the band costs nothing more.
CutByBand(r, bw, bh) => (r.x <= 3 || r.y <= 3 || r.x + r.w >= bw - 3 || r.y + r.h >= bh - 3)

WholeSentence(hit) {
    try {
        full := SentenceAtPoint(Round(hit.x + hit.w / 2), Round(hit.y + hit.h / 2), false)
        if (full && InStr(full.text, hit.word))
            return full.text
    } catch as e
        VocabLog("OCR (word's sentence): " e.Message)
    return hit.context
}

; edge, when given, is [width, height] of the band being read: words touching
; its rim are skipped, because the band cut them.
PickWord(lines, px, py, edge := "") {
    best := "", bestD := 1e9
    for li, row in lines
        for wi, w in row.words {
            if (edge && (w.x <= 2 || w.y <= 2
                || w.x + w.w >= edge[1] - 2 || w.y + w.h >= edge[2] - 2))
                continue
            dx := (px < w.x) ? w.x - px : (px > w.x + w.w) ? px - w.x - w.w : 0
            dy := (py < w.y) ? w.y - py : (py > w.y + w.h) ? py - w.y - w.h : 0
            d := Sqrt(dx * dx + dy * dy)
            if (d < bestD && d <= Max(w.h * 0.6, 10))
                bestD := d, best := [li, wi]
        }
    if !best
        return ""
    w := lines[best[1]].words[best[2]]
    word := CleanWord(w.text)
    if (word = "")
        return ""
    ; The example kept with the word: the one sentence it sits in, cut at the
    ; full stops. Whole lines dragged in the tail of the sentence before and
    ; whatever sat under it on screen - a chat's "11 minutes ago".
    ctx := BlockAt(lines, w.x + w.w / 2, w.y + w.h / 2, false)
    return {word: word, context: ctx ? ctx.text : "", ctx: ctx, x: w.x, y: w.y, w: w.w, h: w.h}
}

; A word or short phrase as it should be looked up: no quotes, brackets or
; Markdown marks around it ("__delaunay triangulation__"), no footnote stuck
; to its end - "abridged[119]" copied from Wikipedia, or "abridged119" when
; the screen read the small raised number as part of the word - and no "'s".
; A letter-and-number name keeps its digits unless the letters make a real
; word's length: "mp3" and "b12" stay, four letters or more lose them.
CleanWord(t) {
    t := StrReplace(StrReplace(t, Chr(0x2019), "'"), Chr(0x2018), "'")
    t := RegExReplace(t, "(\[\d{1,3}\])+$")
    t := RegExReplace(t, "^[^A-Za-z0-9]+|[^A-Za-z0-9]+$")
    if InStr(t, " ")
        return t
    t := RegExReplace(t, "^([A-Za-z]{4,})\d{1,3}$", "$1")
    return RegExReplace(t, "i)'s$")
}
