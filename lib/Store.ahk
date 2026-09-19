;================================================================================
; Store.ahk - your dictionary, words.json
;================================================================================
#Requires AutoHotkey v2.0

class Store {
    static Path := A_ScriptDir "\words.json", words := []

    static Load() {
        if !FileExist(Store.Path)
            return
        try {
            w := Dig(Json.Parse(FileRead(Store.Path, "UTF-8")), "words")
            if (w is Array) {
                Store.words := w
                return
            }
        }
        ; Unreadable: move it aside, so the next save cannot overwrite it
        bad := A_ScriptDir "\words.unreadable-" FormatTime(, "yyyyMMdd-HHmmss") ".json"
        try FileMove(Store.Path, bad)
        TrayTip("words.json could not be read, so it was set aside as`n" bad, AppName, 2)
    }

    static Save() {
        try WriteFileAtomic(Store.Path, Json.Dump(Map("version", 1, "words", Store.words), "  "))
        catch as e {
            VocabLog("saving words.json failed: " e.Message)
            TrayTip("Could not save words.json:`n" e.Message, AppName, 3)
        }
    }

    static Find(word) {
        q := Lookup.Norm(word)
        for i, w in Store.words
            if (Lookup.Norm(w["word"]) == q)
                return i
        return 0
    }

    ; Saving a word you already have keeps its date and review history, takes
    ; the newly chosen meaning, and adds the new sentence to the ones before.
    static Upsert(rec) {
        i := Store.Find(rec["word"])
        if !i {
            Store.words.Push(rec)
            Store.Save()
            return "saved"
        }
        old := Store.words[i]
        for k in ["meaning", "persian", "pos", "note", "lemma", "phonetic", "defs", "fa", "ai", "source"]
            if (rec.Has(k) && (IsObject(rec[k]) || rec[k] != ""))
                old[k] := rec[k]
        if !(Dig(old, "examples") is Array)
            old["examples"] := []
        for ex in rec["examples"] {
            have := false
            for e in old["examples"]
                if (Dig(e, "text") = ex["text"])
                    have := true
            if !have
                old["examples"].Push(ex)
        }
        Store.Save()
        return "updated"
    }

    static Remove(i) {
        Store.words.RemoveAt(i)
        Store.Save()
    }
}

; Saved words with no pronunciation - kept before Datamuse filled that gap -
; get one in the background, one request at a time, a few seconds after
; start. The word as saved is tried first, then its dictionary form.
class PronFill {
    static queue := [], job := "", ticker := "", changed := false

    static Start() {
        for rec in Store.words {
            if (Dig(rec, "phonetic") != "")
                continue
            steps := []
            for w in [rec["word"], Dig(rec, "lemma")]
                if (step := DefTrack.PronStep(Lookup.Norm(w)))
                    steps.Push(step)
            if steps.Length
                PronFill.queue.Push({rec: rec, steps: steps})
        }
        if !PronFill.queue.Length
            return
        PronFill.ticker := ObjBindMethod(PronFill, "Tick")
        SetTimer(PronFill.ticker, 100)
    }

    static Tick() {
        if !PronFill.job {
            if !PronFill.queue.Length {
                SetTimer(PronFill.ticker, 0)
                if PronFill.changed {
                    Store.Save()
                    Dict.Refresh()
                }
                return
            }
            s := PronFill.queue[1].steps[1]
            PronFill.job := Http(s.url, s.opts)
        }
        if !PronFill.job.Poll()
            return
        r := PronFill.job, item := PronFill.queue[1], s := item.steps.RemoveAt(1)
        PronFill.job := ""
        ipa := ""
        if r.Ok
            try ipa := s.parse.Call(r)
        if (ipa != "")
            item.rec["phonetic"] := ipa, PronFill.changed := true
        if (ipa != "" || !item.steps.Length)
            PronFill.queue.RemoveAt(1)
    }
}

Now() => FormatTime(, "yyyy-MM-dd HH:mm")

; What "+ save" writes. The meaning is whichever one carries the green dot.
; Gemini's answer is kept whole under "ai", and every definition under "defs",
; so the saved entry can switch between them later without the network.
BuildRecord(st) {
    if (st.HasProp("mode") && st.mode = "sentence")
        return SentenceRecord(st)
    lk := st.lk
    ai := lk.ai.data, def := lk.def.data, fa := lk.fa.data
    meaning := "", persian := "", pos := ""
    ch := Chosen(st)
    if (ch = "ai" && ai) {
        meaning := ai["meaning"], persian := ai["persian"], pos := ai["pos"]
    } else if (def && RegExMatch(ch, "^g(\d+)\.(\d+)$", &m)) {
        grp := Dig(def, "groups", Integer(m[1]))
        s := Dig(grp, "senses", Integer(m[2]))
        if s {
            meaning := s["d"], pos := grp["pos"]
            persian := (s["fa"] != "") ? s["fa"] : FaForPos(fa, pos)
        }
    }
    if (persian = "" && fa)
        persian := fa["main"]
    if (persian = "" && ai)
        persian := ai["persian"]
    if (meaning = "" && ai)
        meaning := ai["meaning"]
    if (meaning = "" && def)
        meaning := Dig(def, "groups", 1, "senses", 1, "d")
    lemma := (ai && ai["lemma"] != "") ? ai["lemma"] : def ? Dig(def, "lemma") : ""
    examples := []
    ex := (ai && ai["example"] != "") ? ai["example"] : st.context
    if (ex != "")
        examples.Push(Map("text", ex, "seen", Now()))
    src := []
    for t in [lk.def, lk.fa, lk.ai]
        if (t.source != "")
            src.Push(t.source)
    groups := []
    if def
        for gi, grp in def["groups"] {
            if (gi > 10)
                break
            keep := []
            for si, s in grp["senses"]
                if (si <= 30)
                    keep.Push(s)
            groups.Push(Map("pos", grp["pos"], "of", Dig(grp, "of"), "senses", keep))
        }
    return Map("word", st.word, "lemma", lemma, "pos", pos, "phonetic", def ? Dig(def, "phonetic") : ""
        , "meaning", meaning, "persian", persian, "note", ai ? ai["note"] : ""
        , "ai", ai ? ai : ""
        , "examples", examples, "defs", groups, "fa", fa ? fa : Map()
        , "added", Now(), "source", Join(src, ", ")
        , "review", Map("box", 1, "due", "", "reviews", 0, "lapses", 0, "history", []))
}

; Google's Persian for the part of speech of the chosen definition: saving
; "bank" the river edge should not save the word for the money place.
FaForPos(fa, pos) {
    groups := Dig(fa, "groups")
    if !(groups is Array)
        return ""
    for grp in groups
        if (grp["pos"] = pos)
            return Join(grp["terms"], Chr(0x060C) " ", 3)
    return ""
}

; The meaning the green dot is on, in a lookup
Chosen(st) {
    if st.userChose
        return st.choice
    lk := st.lk
    if (lk && lk.ai.data)
        return "ai"
    if (lk && lk.def.data) {
        ; "running" opens with "present participle and gerund of run" - true,
        ; but not a meaning worth saving. The lemma's own entries come right
        ; after it (see MergeLemma), so the dot starts on the first of those.
        d := lk.def.data, lem := Dig(d, "lemma")
        if (lem != "" && RegExMatch(Dig(d, "groups", 1, "senses", 1, "d"), "i)\bof\s+\Q" lem "\E\s*[.;]?$"))
            for gi, grp in d["groups"]
                if (Dig(grp, "of") != "")
                    return "g" gi ".1"
        return "g1.1"
    }
    return ""
}

; Gemini answers a word, a sentence and a paragraph with different keys.
AiText(ai) {
    if !(ai is Map)
        return ""
    for k in ["meaning", "simple", "summary"]
        if (Dig(ai, k) != "")
            return ai[k]
    return ""
}

; Words saved before "ai" was kept separately have only their meaning. If that
; meaning is not one of the stored definitions it came from Gemini, so it is
; given its own "ai" block here - otherwise clicking a definition would throw
; it away with no way back.
EnsureAi(rec) {
    if (Dig(rec, "ai") is Map || Dig(rec, "meaning") = "")
        return
    for grp in (Dig(rec, "defs") || [])
        for s in grp["senses"]
            if (s["d"] == rec["meaning"])
                return
    rec["ai"] := Map("meaning", rec["meaning"], "persian", Dig(rec, "persian"), "pos", Dig(rec, "pos")
        , "note", Dig(rec, "note"), "lemma", Dig(rec, "lemma"), "example", "")
}

