;================================================================================
; Check.ahk - Check my English: is what I wrote right, and how would a native
; say it?
;================================================================================
; The CHECK card; the code calls it "check". Select something you wrote - a
; chat message, an email, a post - and press Ctrl + Win + `. Gemini says
; whether it is right, gives a better version only when something should
; change, says why in a few short points, says what a reader would understand
; from it as written, and picks one phrase or sentence pattern worth learning,
; which "+ save" keeps in the word list like a word.
;
; ONE WORD selected asks "is this word right here?", which needs the sentence
; it is in. That is read from the text box itself through UI Automation - the
; part of Windows screen readers use - so there are no OCR mistakes, and the
; pointer does not have to be over the word: the box knows where its own
; selection is. Apps that do not take part (games, some odd programs) get the
; screen read under the pointer instead, the way a word lookup reads it.
;
; It never changes your text. "copy" puts the better version on the
; clipboard; pasting it, or fixing it yourself, is up to you.
;
; Explanations are in simple English, not the translation language: reading
; English about English is part of the practice.
;================================================================================
#Requires AutoHotkey v2.0

; about 300 words: a long email, not a document
CheckMaxChars() => 2000

CheckSelection(*) {
    MouseGetPos(&mx, &my)
    if Popup.visible {                  ; never read our own popup back
        Popup.Close()
        Sleep 40
    }
    got := CutAtLine(CheckText(CopySelection()), CheckMaxChars())
    text := got.text
    anchor := {x: mx, y: my - 10, w: 1, h: 20, cut: got.cut}
    if (text = "") {
        Popup.Message("Select what you wrote first, then press the key again", mx, my)
        return
    }
    if (CountWords(text) = 1 && !InStr(text, "`n")) {
        word := CleanWord(text)
        if (word = "") {
            Popup.Message("No word in the selection", mx, my)
            return
        }
        StartLookup(word, SentenceWith(word, mx, my), Popup, anchor, false, "check")
        return
    }
    StartLookup(text, "", Popup, anchor, false, "check")
}

; What was written, tidied without changing it: spaces and tabs run together,
; but the breaks between paragraphs stay - the better version keeps them too,
; so it can be copied back as it was laid out.
CheckText(s) {
    s := StrReplace(StrReplace(s, "`r`n", "`n"), "`r", "`n")
    s := RegExReplace(s, "[ \t" Chr(0xA0) "]+", " ")
    s := RegExReplace(s, " ?\n ?", "`n")
    return Trim(RegExReplace(s, "\n{3,}", "`n`n"), " `n")
}

; The sentence a checked word is in, from the first of these that has it:
;   UI Automation's text   the box's text and where the selection is in it -
;                          browsers, chat apps, Word, Notepad. Exact even when
;                          the word is in the box twice
;   the box itself         an old-style Windows text box (Edit) says where its
;                          selection starts when asked (EM_GETSEL) - just as
;                          exact
;   UI Automation's value  only a box's whole text: the first place the word
;                          is, right unless it is there twice
;   the screen             read under the pointer, like a word lookup
; "" when none has the word. A box that does not take part simply throws
; and the next way is tried, so none of that is logged.
SentenceWith(word, mx, my) {
    for way in [() => Uia.Selection(), EditSelection] {
        try {
            r := way.Call()
            if (r.at && SubStr(r.text, r.at, StrLen(word)) = word)   ; not case-sensitive
                return SentenceAt(r.text, r.at)
            if (at := InStr(r.text, word))
                return SentenceAt(r.text, at)
        }
    }
    try {
        text := Uia.Value()
        if (at := InStr(text, word))
            return SentenceAt(text, at)
    }
    try {
        hit := SentenceAtPoint(mx, my, false)
        if (hit && InStr(hit.text, word))
            return hit.text
    } catch as e
        VocabLog("OCR (checked word's sentence): " e.Message)
    return ""
}

; The one sentence of text that the character at sits in, at most 600
; characters of it
SentenceAt(text, at) {
    r := SpanRange(text, at, false)
    s := Trim(SubStr(text, r[1], r[2] - r[1] + 1))
    return (StrLen(s) > 600) ? "" : s
}

; an old-style text box with the keyboard focus: its text, and where its
; selection starts (the low word of EM_GETSEL's answer)
EditSelection() {
    hwnd := ControlGetFocus("A")
    if !RegExMatch(WinGetClass(hwnd), "i)^(Edit|RichEdit\d*\w*|RICHEDIT\d+W)$")
        throw Error("not a text box")
    sel := SendMessage(0xB0, 0, 0, hwnd)                       ; EM_GETSEL
    return {text: ControlGetText(hwnd), at: (sel & 0xFFFF) + 1}
}

;--------------------------------------------------------------------------------
; UI Automation, only as much as reading the focused text box takes. Raw
; vtables, like OcrWindows.ahk: each ComCall number is a method slot, named
; beside it. Every pointer is held by a ComValue, which releases it when the
; variable goes - also when a call throws halfway.
;--------------------------------------------------------------------------------
class Uia {
    static obj := ""

    static Focused() {
        if !Uia.obj
            Uia.obj := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        ComCall(8, Uia.obj, "ptr*", &p := 0)                    ; GetFocusedElement
        if !p
            throw Error("nothing has the focus")
        return ComValue(13, p)
    }

    ; the paragraph around the focused box's selection, and where in it the
    ; selection starts: {text, at}
    static Selection() => Uia.AroundSelection(Uia.Focused())

    static AroundSelection(el) {
        ComCall(16, el, "int", 10014, "ptr*", &p := 0)          ; GetCurrentPattern(UIA_TextPatternId)
        if !p
            throw Error("no text pattern")
        tp := ComValue(13, p)
        ComCall(5, tp, "ptr*", &p := 0)                         ; GetSelection
        sels := ComValue(13, p)
        ComCall(3, sels, "int*", &n := 0)                       ; IUIAutomationTextRangeArray.Length
        if !n
            throw Error("nothing selected")
        ComCall(4, sels, "int", 0, "ptr*", &p := 0)             ; GetElement
        sel := ComValue(13, p)
        ComCall(3, sel, "ptr*", &p := 0)                        ; Clone
        para := ComValue(13, p)
        ComCall(6, para, "int", 4)                              ; ExpandToEnclosingUnit(TextUnit_Paragraph)
        ComCall(3, para, "ptr*", &p := 0)
        before := ComValue(13, p)
        ; the paragraph's start up to the selection's start
        ComCall(15, before, "int", 1, "ptr", sel, "int", 0)     ; MoveEndpointByRange(End, sel, Start)
        return {text: Uia.Text(para), at: StrLen(Uia.Text(before)) + 1}
    }

    static Text(range) {
        ComCall(12, range, "int", 20000, "ptr*", &bs := 0)      ; GetText
        s := bs ? StrGet(bs) : ""
        DllCall("oleaut32\SysFreeString", "ptr", bs)
        return s
    }

    ; the focused box's whole text, "" when it has none to give
    static Value() {
        el := Uia.Focused()
        v := Buffer(24, 0)
        try ComCall(10, el, "int", 30045, "ptr", v)             ; GetCurrentPropertyValue(UIA_ValueValuePropertyId)
        catch
            return ""
        s := (NumGet(v, 0, "ushort") = 8 && NumGet(v, 8, "ptr")) ? StrGet(NumGet(v, 8, "ptr")) : ""   ; VT_BSTR
        DllCall("oleaut32\VariantClear", "ptr", v)
        return s
    }
}

;--------------------------------------------------------------------------------
; What changed: the better version word by word, each word marked new when it
; is not one of the original's in that place (the longest run the two have in
; common, the way a diff tool finds it). Done here, not by Gemini: asked to
; mark its own changes, a model marks some it did not make and misses others.
; A line break is a word of its own, "`n".
;--------------------------------------------------------------------------------
DiffWords(old, new) {
    a := DiffTokens(old), b := DiffTokens(new)
    n := a.Length, m := b.Length
    ; L[i][j]: how many words a[i..] and b[j..] have in common, in order
    L := []
    loop n + 2 {
        row := []
        row.Length := m + 2
        loop m + 2
            row[A_Index] := 0
        L.Push(row)
    }
    i := n
    while (i >= 1) {
        j := m
        while (j >= 1) {
            L[i][j] := (a[i] == b[j]) ? L[i + 1][j + 1] + 1 : Max(L[i + 1][j], L[i][j + 1])
            j--
        }
        i--
    }
    out := [], i := 1, j := 1
    while (j <= m) {
        if (i <= n && a[i] == b[j])
            out.Push({t: b[j], new: false}), i++, j++
        else if (i <= n && L[i + 1][j] >= L[i][j + 1])
            i++                                 ; a word of the original that went
        else
            out.Push({t: b[j], new: b[j] != "`n"}), j++
    }
    return out
}

DiffTokens(s) {
    out := []
    for w in StrSplit(StrReplace(s, "`n", " `n "), " ")
        if (w != "")
            out.Push(w)
    return out
}

;--------------------------------------------------------------------------------
; The card
;--------------------------------------------------------------------------------
RenderCheck(g, W, st, owner) {
    lk := st.lk
    ai := (lk && lk.ai.data) ? lk.ai.data : ""
    f := Flow(g, 14, 10, W - 28)
    one := (st.context != "" || CountWords(st.word) = 1)

    g.SetFont("s7 Bold c" CBlue, FontUI)
    g.Add("Text", "x" f.x " y" (f.y + 6) " BackgroundTrans +0x80", "CHECK MY ENGLISH")
    CardLinks(g, f.x + f.w, f.y + 2, [PinAction(owner)
        , lk ? {text: "check again", color: CBlue, w: 90, fn: (*) => owner.Again()} : ""])
    f.y += 26

    if one {
        f.Text(st.word, CText, "s13 Bold", "", 2)
        f.Text((st.context != "") ? Chr(0x201C) st.context Chr(0x201D)
            : "no sentence found around it - checked on its own", CMuted, "s9 Norm Italic")
    }

    if (!lk || !lk.ai.enabled || (lk.ai.done && !ai && KeyTrouble(lk)))
        NoKeyLine(f, lk)
    else if !lk.ai.done
        f.Text(lk.ai.Waiting, CDim, "s9 Norm Italic")
    else if !ai
        f.Text("Gemini: " lk.ai.note, CDim, "s8 Norm Italic")
    else
        CheckAnswer(f, st, owner, ai, one)

    if (st.HasProp("cut") && st.cut)
        f.Text("The text was long: only its first part was checked, down to the end of YOU WROTE.", CAmber, "s8 Norm")
    if !one {
        f.Label("YOU WROTE")
        f.Text(st.word, CMuted, "s8 Norm")
    }
    if (lk && lk.ai.source != "") {
        f.y += 4
        f.Text(lk.ai.source, CDim, "s7 Norm")
    }
    return f.y + 8
}

CheckAnswer(f, st, owner, ai, one) {
    g := f.g
    v := ai["verdict"]
    better := ai["better"]
    ; the same text back is no better version - but a capital letter is a change
    if (v = "correct" || RegExReplace(better, "\s+", " ") == RegExReplace(one ? st.context : st.word, "\s+", " "))
        better := ""
    f.y += 4
    f.Text((v = "correct") ? Chr(0x2713) " Correct" : (v = "small") ? "Small fix" : (v = "wrong") ? "Needs a fix" : "Checked"
        , (v = "correct") ? CGreen : (v = "wrong") ? CRed : CAmber, "s11 Bold")

    if (better != "") {
        copied := st.HasProp("copied") ? st.copied : ""
        CheckLabel(f, "BETTER VERSION", (copied != "") ? copied : "copy"
            , (copied != "") ? CMuted : CBlue, (*) => CheckCopy(owner, better))
        f.Runs(DiffWords(one ? st.context : st.word, better), "s10 Norm", CText, CGreen)
    }
    if ai["points"].Length {
        f.Label("WHY")
        for p in ai["points"]
            f.Text(Chr(0x2022) "  " p, CText, "s9 Norm", "", 3)
    }
    if (ai["reader"] != "") {
        f.Label("WHAT A READER UNDERSTANDS")
        f.Text(ai["reader"], CText, "s9 Norm")
    }
    if (ai["pattern"] != "") {
        saved := Store.Find(ai["pattern"])
        CheckLabel(f, "LEARN THIS", (st.flash != "") ? st.flash : saved ? "saved " Chr(0x2713) : "+ save"
            , (saved || st.flash != "") ? CMuted : CGreen, (*) => owner.Save(), CGreen)
        f.Text(ai["pattern"], CText, "s11 Bold", "", 2)
        if (ai["pattern_use"] != "")
            f.Text(ai["pattern_use"], CMuted, "s9 Norm")
        if (ai["pattern_example"] != "")
            f.Text(Chr(0x201C) ai["pattern_example"] Chr(0x201D), CMuted, "s9 Norm Italic")
    }
}

; a section label with one action at its right end
CheckLabel(f, text, act, color, fn, labelColor := "") {
    c := f.Label(text, labelColor)
    c.GetPos(, &y)
    CardLinks(f.g, f.x + f.w, y - 3, [{text: act, color: color, w: 84, fn: fn}])
}

CheckCopy(owner, text) {
    A_Clipboard := text
    owner.st.copied := "copied " Chr(0x2713)
    owner.Render()
}

; A saved pattern sits in the word list like a word: the pattern in place of
; the word, when to use it as its meaning, the example - and the better
; version it came from, when that is a sentence or two - as where it was seen.
PatternRecord(st) {
    ai := st.lk.ai.data
    exs := []
    for t in [ai["pattern_example"], ai["better"]]
        if (t != "" && StrLen(t) <= 300)
            exs.Push(Map("text", t, "seen", Now()))
    return Map("word", ai["pattern"], "kind", "pattern", "lemma", "", "pos", "pattern", "phonetic", ""
        , "meaning", ai["pattern_use"], "persian", "", "lang", Lang.Code(), "note", ""
        , "examples", exs, "defs", [], "fa", Map()
        , "added", Now(), "source", st.lk.ai.source
        , "review", Map("box", 1, "due", "", "reviews", 0, "lapses", 0, "history", []))
}
