;================================================================================
; Lookup.ahk - where definitions and translations come from
;================================================================================
; Every lookup runs three tracks side by side. Each works down its own list of
; free sources and stops at the first one that answers:
;
;   definitions   freedictionaryapi.com -> Wiktionary -> Datamuse
;                 (+ Datamuse for an American pronunciation when none came)
;   translation   Google (dictionary client) -> Google (gtx) -> Lingva -> MyMemory,
;                 into the language chosen in Settings (see Language.ahk)
;   in context    Gemini, only when a key is set (see GeminiKey below)
;
; A timeout, an HTTP error, a garbled reply and "no such word" all mean the
; same thing: move on to the next source. Every one of those has been seen for
; real - Google's gtx client has refused requests as automated - which is why
; the lists are as long as they are (docs\decisions.md has the history).
;
; An inflected word ("running") that a dictionary only knows as "present
; participle of run" gets its lemma looked up too, and both are shown. If no
; source knows the word at all, plain de-inflections are tried (studies ->
; study, stopped -> stop) before giving up.
;
; The first two tracks are cached per word under cache\, so a word met twice
; costs nothing the second time and still resolves offline. Gemini's answer
; depends on the sentence, so it is never cached.
;
; Nothing blocks. Requests go out asynchronously and one 50 ms timer polls all
; of them, so the popup is on screen before the first answer arrives.
;================================================================================
#Requires AutoHotkey v2.0

VocabIni() => A_ScriptDir "\Vocab.ini"

; The key lives in Vocab.ini rather than in this file, so the script can be
; shared without it; the settings window writes it there. GEMINI_API_KEY in
; the environment works too. Both are read on every lookup, so a new key takes
; effect without a reload.
GeminiKey() {
    k := Trim(IniRead(VocabIni(), "Gemini", "ApiKey", ""))
    return (k != "") ? k : Trim(EnvGet("GEMINI_API_KEY"))
}
GeminiModel() => Trim(IniRead(VocabIni(), "Gemini", "Model", ""))

; Errors that would otherwise vanish inside a timer end up here - never in a
; dialog, which would steal focus from whatever you were reading.
VocabLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", A_ScriptDir "\errors.log", "UTF-8")
}

; Run at start: past 200 KB, errors.log keeps only its newest 100 KB, from the
; start of a line. Nothing reads the log but people, and nobody reads that much.
TrimLog() {
    f := A_ScriptDir "\errors.log"
    try {
        if (FileGetSize(f) <= 200000)
            return
        t := SubStr(FileRead(f, "UTF-8"), -100000)
        WriteFileAtomic(f, SubStr(t, InStr(t, "`n") + 1))
    }
}

HasVal(arr, v) {
    for x in arr
        if (x = v)
            return true
    return false
}

Join(arr, sep, most := 0) {
    out := ""
    for i, x in arr {
        if (most && i > most)
            break
        out .= (i > 1 ? sep : "") x
    }
    return out
}

WriteFileAtomic(path, text) {
    tmp := path ".tmp"
    try FileDelete(tmp)
    FileAppend(text, tmp, "UTF-8-RAW")
    FileMove(tmp, path, 1)
}

;--------------------------------------------------------------------------------
; One asynchronous HTTP request. Poll() until it returns true.
;--------------------------------------------------------------------------------
class Http {
    static UA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) VocabLookup/1.0"

    __New(url, opts := "") {
        this.url := url, this.status := 0, this.text := "", this.err := "", this.done := false
        this.req := "", this.raw := ""
        o := IsObject(opts) ? opts : {}
        this.wantRaw := o.HasProp("raw") && o.raw        ; audio: keep the bytes
        timeout := o.HasProp("timeout") ? o.timeout : 8000
        this.deadline := A_TickCount + timeout
        try {
            r := ComObject("WinHttp.WinHttpRequest.5.1")
            r.Open(o.HasProp("method") ? o.method : "GET", url, true)
            if (px := Http.Proxy())
                r.SetProxy(2, px[1], px[2])             ; HTTPREQUEST_PROXYSETTING_PROXY
            r.SetTimeouts(timeout, timeout, timeout, timeout)
            r.Option[0] := Http.UA
            if o.HasProp("headers")
                for k, v in o.headers
                    r.SetRequestHeader(k, v)
            if o.HasProp("body")
                r.Send(o.body)
            else
                r.Send()
            this.req := r
        } catch as e {
            this.err := Http.Short(e.Message), this.done := true
        }
    }

    Poll() {
        if this.done
            return true
        try {
            if !this.req.WaitForResponse(0) {
                if (A_TickCount < this.deadline)
                    return false
                try this.req.Abort()
                this.err := "timed out"
            } else {
                this.status := this.req.Status
                body := this.req.ResponseBody
                if this.wantRaw
                    this.raw := body
                else
                    this.text := Http.Utf8(body)
            }
        } catch as e
            this.err := Http.Short(e.Message)
        this.req := ""
        return this.done := true
    }

    ; [Network] Proxy in Vocab.ini:
    ;   auto (or empty)   follow the Windows proxy setting - the one a VPN app
    ;                     such as v2rayN turns on in "system proxy" mode.
    ;                     WinHttp ignores that setting by itself, so without
    ;                     this every request would go direct and fail wherever
    ;                     direct access is blocked
    ;   127.0.0.1:10809   always use this proxy
    ;   none              always go direct
    ; Read per request, so switching the VPN's mode takes effect at once.
    static Proxy() {
        cfg := Trim(IniRead(VocabIni(), "Network", "Proxy", "auto"))
        if (cfg = "none" || cfg = "direct")
            return ""
        if (cfg != "" && cfg != "auto")
            return [cfg, "<local>"]
        key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        try {
            if RegRead(key, "ProxyEnable", 0) {
                s := RegRead(key, "ProxyServer", "")
                if (s != "")
                    return [s, RegRead(key, "ProxyOverride", "<local>")]
            }
        }
        return ""
    }

    Ok  => (this.err = "" && this.status >= 200 && this.status < 300)
    Why => (this.err != "") ? this.err : "HTTP " this.status

    ; ResponseText trusts the server's charset header; the raw bytes as UTF-8
    ; are right for every source here, headers or not.
    static Utf8(body) {
        if !IsObject(body)
            return ""
        n := body.MaxIndex() + 1
        if (n <= 0)
            return ""
        return StrGet(NumGet(ComObjValue(body), 8 + A_PtrSize, "ptr"), n, "UTF-8")
    }

    ; The bytes exactly as they arrived - for audio, where decoding as text
    ; would ruin them
    static Write(body, path) {
        n := body.MaxIndex() + 1
        out := FileOpen(path, "w")
        if !out
            throw Error("cannot write " path)
        out.RawWrite(NumGet(ComObjValue(body), 8 + A_PtrSize, "ptr"), n)
        out.Close()
    }

    static Enc(s) {
        buf := Buffer(StrPut(s, "UTF-8"))
        StrPut(s, buf, "UTF-8")
        out := ""
        loop buf.Size - 1 {
            b := NumGet(buf, A_Index - 1, "uchar")
            out .= ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E) ? Chr(b) : Format("%{:02X}", b)
        }
        return out
    }

    static Short(msg) {
        msg := Trim(StrSplit(msg, "`n")[1], " `t`r")
        msg := RegExReplace(msg, "^0x[0-9A-Fa-f]+ - ")
        msg := RegExReplace(msg, "^\((.*)\)$", "$1")        ; a bare "(0x80072EFD)", so callers' own brackets do not double
        return (StrLen(msg) > 60) ? SubStr(msg, 1, 57) "..." : msg
    }
}

;--------------------------------------------------------------------------------
; cache\<word>.json holds {"def": ..., "fa": ...} for that word
;--------------------------------------------------------------------------------
class Cache {
    static Dir := A_ScriptDir "\cache"

    static File(q) {
        if (q = "" || StrLen(q) > 60 || RegExMatch(q, "(\S+\s+){4}"))   ; sentences are not worth keeping
            return ""
        return Cache.Dir "\" RegExReplace(q, "[^a-z0-9' -]", "_") ".json"
    }

    static Get(q, kind) {
        f := Cache.File(q)
        if (f = "" || !FileExist(f))
            return ""
        try return Dig(Json.Parse(FileRead(f, "UTF-8")), kind)
        return ""
    }

    static Put(q, kind, data) {
        f := Cache.File(q)
        if (f = "")
            return
        m := ""
        try m := Json.Parse(FileRead(f, "UTF-8"))
        if !(m is Map)
            m := Map()
        m[kind] := data
        try {
            DirCreate(Cache.Dir)
            WriteFileAtomic(f, Json.Dump(m, " "))
        } catch as e
            VocabLog("cache write failed for " q ": " e.Message)
    }
}

;--------------------------------------------------------------------------------
; A lookup: one word, the sentence it came from, three tracks
;--------------------------------------------------------------------------------
class Lookup {
    static active := [], ticker := ""

    __New(word, context, onUpdate, mode := "word") {
        this.word := word
        this.query := Lookup.Norm(word)
        this.context := context
        this.mode := mode               ; "word", or "sentence" - see Sentence.ahk
        this.onUpdate := onUpdate
        this.cancelled := false
        this.fresh := true          ; one update on the first tick, for cached answers
        this.def := DefTrack(this)
        this.fa  := FaTrack(this)
        this.ai  := AiTrack(this)
        Lookup.active.Push(this)
        if !Lookup.ticker
            Lookup.ticker := ObjBindMethod(Lookup, "Tick")
        SetTimer(Lookup.ticker, 50)
    }

    Done => (this.def.done && this.fa.done && this.ai.done)
    Cancel() => this.cancelled := true

    static Norm(w) => Trim(RegExReplace(StrLower(StrReplace(w, Chr(0x2019), "'")), "\s+", " "))

    static Tick() {
        i := Lookup.active.Length
        while (i >= 1) {
            l := Lookup.active[i]
            if !l.cancelled {
                changed := l.def.Step() | l.fa.Step() | l.ai.Step()
                if (changed || l.fresh) {
                    l.fresh := false
                    try l.onUpdate.Call(l)
                    catch as e
                        VocabLog("update failed: " e.Message " (" e.What " line " e.Line ")")
                }
            }
            if (l.cancelled || l.Done)
                Lookup.active.RemoveAt(i)
            i--
        }
        if !Lookup.active.Length
            SetTimer(Lookup.ticker, 0)
    }
}

;--------------------------------------------------------------------------------
; A track works through a queue of steps, one request at a time. Each step is
; {name, url, parse, opts?}; parse gets the finished Http and returns the
; answer, or "" for "this source had nothing".
;--------------------------------------------------------------------------------
class Track {
    __New(lk) {
        this.lk := lk, this.done := false, this.data := "", this.source := ""
        this.tried := [], this.note := "", this.steps := [], this.req := "", this.cur := ""
        this.cached := false, this.cacheKind := "", this.enabled := true
        this.Start()
    }

    Start() {
    }

    FromCache(kind) {
        this.cacheKind := kind
        c := Cache.Get(this.lk.query, kind)
        if !(c is Map)
            return false
        this.data := c, this.source := Dig(c, "source"), this.cached := true, this.done := true
        return true
    }

    ; true when there is something new to draw
    Step() {
        if this.done
            return false
        if !this.req {
            if !this.steps.Length
                return this.Finish()
            this.cur := this.steps.RemoveAt(1)
            ; Every step carries an address. One that somehow does not is
            ; logged - with what it did hold - and skipped, never a dialog
            ; (see "Open questions" in docs\decisions.md).
            if !(IsObject(this.cur) && this.cur.HasProp("url")) {
                held := []
                if IsObject(this.cur)
                    for k in this.cur.OwnProps()
                        held.Push(k)
                VocabLog(Type(this) " skipped a step with no address {" Join(held, ", ") "} ("
                    . Type(this.cur) (this.HasProp("phase") ? ", phase " this.phase : "") ") for " this.lk.query)
                this.cur := ""
                return false
            }
            this.req := Http(this.cur.url, this.cur.HasProp("opts") ? this.cur.opts : "")
        }
        if !this.req.Poll()
            return false
        r := this.req, s := this.cur
        this.req := ""
        result := ""
        if r.Ok {
            try result := s.parse.Call(r)
            catch as e
                r.err := "unreadable reply"
        }
        this.tried.Push(s.name (result ? "" : " - " ((r.Ok && r.err = "") ? "no entry" : r.Why)))
        return this.Got(s, r, result)
    }

    Got(s, r, result) {
        if !result
            return false
        this.Take(s, result)
        return this.Finish()
    }

    Take(s, result) {
        if (result is Map)
            result["source"] := s.name
        this.data := result, this.source := s.name, this.steps := []
    }

    Finish() {
        this.done := true
        if (this.data && !this.cached && this.cacheKind != "")
            Cache.Put(this.lk.query, this.cacheKind, this.data)
        return true
    }
}

;--------------------------------------------------------------------------------
; Definitions. Every source is reduced to the same shape:
;   {phonetic, lemma, groups: [{pos, of?, senses: [{d, ex, fa, low}]}]}
; One group per dictionary entry, not per part of speech: "bank" the money
; place and "bank" the river edge are separate entries, and keeping them apart
; is what lets the popup show one line of EACH instead of burying the river
; under nine financial senses.
;--------------------------------------------------------------------------------
class DefTrack extends Track {
    Start() {
        if (this.lk.mode != "word") {           ; a dictionary has no entry for a sentence
            this.enabled := false, this.done := true
            return
        }
        this.phase := "word"
        if this.FromCache("def") {
            if this.NeedsPron()             ; kept before pronunciations were filled in
                this.phase := "pron", this.steps := [DefTrack.PronStep(this.lk.query)]
                    , this.done := false, this.cached := false
            return
        }
        this.steps := DefTrack.Sources(this.lk.query)
    }

    ; No source gave a pronunciation: ask Datamuse before finishing. Asked once
    ; per word - the cache remembers - so a word it does not know costs nothing
    ; the next time.
    NeedsPron() => (this.phase != "pron" && this.data && Dig(this.data, "phonetic") = ""
        && !Dig(this.data, "pronTried") && DefTrack.PronStep(this.lk.query))

    Finish() {
        if this.NeedsPron() {
            this.phase := "pron", this.steps := [DefTrack.PronStep(this.lk.query)]
            return true                 ; draw the definitions while it loads
        }
        return super.Finish()
    }

    static Sources(q, shortList := false) {
        e := Http.Enc(q)
        list := [
            {name: "freedictionaryapi.com", url: "https://freedictionaryapi.com/api/v1/entries/en/" e "?translations=true"
                , parse: ObjBindMethod(DefTrack, "FreeDict", q)},
            {name: "Wiktionary", url: "https://en.wiktionary.org/api/rest_v1/page/definition/" StrReplace(e, "%20", "_")
                , parse: ObjBindMethod(DefTrack, "Wiktionary", q)},
            {name: "Datamuse", url: "https://api.datamuse.com/words?sp=" e "&md=dp&max=1"
                , parse: ObjBindMethod(DefTrack, "Datamuse", q)}
        ]
        return shortList ? [list[1], list[2]] : list
    }

    Got(s, r, result) {
        if (this.phase = "pron") {
            this.data["pronTried"] := 1
            if result
                this.data["phonetic"] := result
            this.steps := []
            return super.Finish()
        }
        if (this.phase = "lemma") {
            if (!result && this.steps.Length)
                return false
            if result
                this.MergeLemma(result)
            this.steps := []
            return this.Finish()
        }
        if !result {
            if (!this.steps.Length && this.phase = "word") {
                this.phase := "stem"
                for cand in DefTrack.Stems(this.lk.query)
                    for src in DefTrack.Sources(cand, true) {
                        src.cand := cand
                        this.steps.Push(src)
                    }
            }
            return false
        }
        if (this.phase = "stem")
            result["lemma"] := s.cand
        result["faLang"] := Lang.Code()     ; what the senses' translations are in
        this.Take(s, result)
        target := Dig(result, "lemmaOf")
        if (this.phase = "word" && target != "" && target != this.lk.query) {
            result["lemma"] := target
            this.phase := "lemma"
            this.steps := DefTrack.Sources(target, true)
            return true                 ; draw what we have while the lemma loads
        }
        return this.Finish()
    }

    ; The lemma's entries go straight after the "form of" line that pointed at
    ; them, so "running" reads: form of run -> what run means -> running's own
    ; adjective and noun senses.
    MergeLemma(res) {
        groups := this.data["groups"]
        at := 1
        for i, grp in groups
            for s in grp["senses"]
                if RegExMatch(s["d"], "i)\bof\s+\Q" this.data["lemma"] "\E\s*$") {
                    at := i
                    break 2
                }
        for n, grp in res["groups"] {
            if (n > 3)
                break
            grp["of"] := this.data["lemma"]
            groups.InsertAt(at + n, grp)
        }
        if (this.data["phonetic"] = "")
            this.data["phonetic"] := res["phonetic"]
    }

    static Stems(q) {
        out := []
        add(w) {
            if (w != q && StrLen(w) > 2 && !HasVal(out, w))
                out.Push(w)
        }
        if RegExMatch(q, "i)^[a-z]+$") {
            if RegExMatch(q, "ie[sd]$")
                add(SubStr(q, 1, -3) "y")
            if RegExMatch(q, "([b-df-hj-np-tv-z])\1(ed|ing)$", &m)
                add(SubStr(q, 1, -StrLen(m[2]) - 1))
            if RegExMatch(q, "(ches|shes|sses|xes|zes|oes)$")
                add(SubStr(q, 1, -2))
            if RegExMatch(q, "[^s]s$")
                add(SubStr(q, 1, -1))
            if RegExMatch(q, "ed$")
                add(SubStr(q, 1, -2)), add(SubStr(q, 1, -1))
            if RegExMatch(q, "ing$")
                add(SubStr(q, 1, -3)), add(SubStr(q, 1, -3) "e")
            if RegExMatch(q, "ly$")
                add(SubStr(q, 1, -2))
            if RegExMatch(q, "(er|est)$", &m)
                add(SubStr(q, 1, -StrLen(m[1])))
        }
        while (out.Length > 3)
            out.Pop()
        return out
    }

    static FreeDict(q, r) {
        d := Json.Parse(r.text)
        out := DefTrack.Blank()
        for e in (Dig(d, "entries") || []) {
            if (Dig(e, "language", "code") != "en")
                continue
            if (out["phonetic"] = "")
                for p in (Dig(e, "pronunciations") || [])
                    if (Dig(p, "type") = "ipa" && SubStr(Dig(p, "text"), 1, 1) = "/") {
                        out["phonetic"] := Dig(p, "text")
                        break
                    }
            senses := []
            for s in (Dig(e, "senses") || []) {
                txt := DefTrack.Tidy(Dig(s, "definition"))
                if (txt = "")
                    continue
                tags := Dig(s, "tags") || []
                if (out["lemmaOf"] = "" && HasVal(tags, "form of"))
                    out["lemmaOf"] := DefTrack.FormOf(txt)
                fa := []
                for tr in (Dig(s, "translations") || [])
                    if (Dig(tr, "language", "code") = Lang.Dict()) {
                        w := DefTrack.NoHarakat(Dig(tr, "word"))
                        if (w != "" && !HasVal(fa, w))
                            fa.Push(w)
                    }
                ex := ""
                for x in (Dig(s, "examples") || [])
                    if ((ex := DefTrack.Plain(x)) != "")
                        break
                senses.Push(Map("d", txt, "ex", ex, "fa", Join(fa, Lang.Sep(), 3), "low", DefTrack.IsLow(tags, txt)))
            }
            if senses.Length
                out["groups"].Push(Map("pos", StrLower(Dig(e, "partOfSpeech")), "senses", DefTrack.LowLast(senses)))
        }
        return DefTrack.Finalize(out)
    }

    static Wiktionary(q, r) {
        d := Json.Parse(r.text)
        out := DefTrack.Blank()
        for e in (Dig(d, "en") || []) {
            senses := []
            for s in (Dig(e, "definitions") || []) {
                html := Dig(s, "definition")
                if (p := RegExMatch(html, "<(ol|ul|dl)\b"))    ; nested sub-senses: keep the headline
                    html := SubStr(html, 1, p - 1)
                txt := DefTrack.Tidy(DefTrack.Plain(html))
                if (txt = "")
                    continue
                if (out["lemmaOf"] = "" && InStr(html, "form-of-definition"))
                    out["lemmaOf"] := DefTrack.FormOf(txt)
                ex := ""
                for x in (Dig(s, "examples") || [])
                    if ((ex := DefTrack.Plain(x)) != "")
                        break
                senses.Push(Map("d", txt, "ex", ex, "fa", "", "low", DefTrack.IsLow([], txt)))
            }
            if senses.Length
                out["groups"].Push(Map("pos", StrLower(Dig(e, "partOfSpeech")), "senses", DefTrack.LowLast(senses)))
        }
        return DefTrack.Finalize(out)
    }

    static Datamuse(q, r) {
        arr := Json.Parse(r.text)
        if !(arr is Array) || !arr.Length || StrLower(Dig(arr, 1, "word")) != q
            return ""
        names := Map("n", "noun", "v", "verb", "adj", "adjective", "adv", "adverb", "u", "")
        byPos := Map(), posOrder := []
        for entry in (Dig(arr, 1, "defs") || []) {
            parts := StrSplit(entry, "`t", , 2)
            pos := names.Has(parts[1]) ? names[parts[1]] : parts[1]
            txt := DefTrack.Tidy(parts.Length > 1 ? parts[2] : parts[1])
            if (txt = "")
                continue
            if !byPos.Has(pos)
                byPos[pos] := [], posOrder.Push(pos)
            byPos[pos].Push(Map("d", txt, "ex", "", "fa", "", "low", DefTrack.IsLow([], txt)))
        }
        out := DefTrack.Blank()
        for pos in posOrder
            out["groups"].Push(Map("pos", pos, "senses", DefTrack.LowLast(byPos[pos])))
        return DefTrack.Finalize(out)
    }

    ; Datamuse's pronunciations come from the CMU dictionary: American, written
    ; as phoneme codes (P ER0 T ER0 B EY1 SH AH0 N) that Ipa() turns into the
    ; usual symbols. Single words only: a phrase comes back as one run of sounds
    ; with no word breaks, and a hyphenated word comes back as a different word.
    static PronStep(q) {
        if !RegExMatch(q, "^[a-z][a-z']*$")
            return ""
        return {name: "Datamuse (pronunciation)", url: "https://api.datamuse.com/words?sp=" Http.Enc(q) "&md=r&max=1"
            , parse: ObjBindMethod(DefTrack, "DatamusePron", q), opts: {timeout: 5000}}
    }

    static DatamusePron(q, r) {
        arr := Json.Parse(r.text)
        if !(arr is Array) || !arr.Length || StrLower(Dig(arr, 1, "word")) != q
            return ""
        for tag in (Dig(arr, 1, "tags") || [])
            if (SubStr(tag, 1, 5) = "pron:")
                return DefTrack.Ipa(SubStr(tag, 6))
        return ""
    }

    ; The stress mark goes where dictionaries put it, at the start of the
    ; stressed syllable - before the consonants that open it, so in
    ; pertur-BA-tion it comes before the b, not after it. Those consonants are
    ; the longest run that can begin an English word (im-PLODE: "pl" can, "mpl"
    ; cannot). A word of one syllable gets no mark.
    static Ipa(arpa) {
        static sym := Map("AA", Chr(0x251), "AE", Chr(0xE6), "AH", Chr(0x28C), "AO", Chr(0x254)
            , "AW", "a" Chr(0x28A), "AY", "a" Chr(0x26A), "EH", Chr(0x25B), "ER", Chr(0x25D)
            , "EY", "e" Chr(0x26A), "IH", Chr(0x26A), "IY", "i", "OW", "o" Chr(0x28A)
            , "OY", Chr(0x254) Chr(0x26A), "UH", Chr(0x28A), "UW", "u"
            , "B", "b", "CH", "t" Chr(0x283), "D", "d", "DH", Chr(0xF0), "F", "f", "G", Chr(0x261)
            , "HH", "h", "JH", "d" Chr(0x292), "K", "k", "L", "l", "M", "m", "N", "n", "NG", Chr(0x14B)
            , "P", "p", "R", Chr(0x279), "S", "s", "SH", Chr(0x283), "T", "t", "TH", Chr(0x3B8)
            , "V", "v", "W", "w", "Y", "j", "Z", "z", "ZH", Chr(0x292))
        static onsets := "|P R|B R|T R|D R|K R|G R|F R|TH R|SH R|P L|B L|K L|G L|F L|S L|T W|D W|K W|G W|S W|TH W"
            . "|P Y|B Y|K Y|G Y|F Y|V Y|M Y|HH Y|S P|S T|S K|S M|S N|S F|S P R|S T R|S K R|S P L|S K W|S K Y|S P Y|"
        toks := StrSplit(Trim(arpa), " ")
        vowels := 0
        for t in toks
            vowels += RegExMatch(t, "\d$") ? 1 : 0
        out := [], codes := [], lastV := 0
        for t in toks {
            if !RegExMatch(t, "^([A-Z]+)(\d?)$", &m) || !sym.Has(m[1])
                return ""
            if (m[2] = "") {
                out.Push(sym[m[1]]), codes.Push(m[1])
                continue
            }
            if (vowels > 1 && m[2] != "0") {
                n := out.Length - lastV
                k := lastV ? Min(n, 3) : n
                while (lastV && k > 1) {
                    run := ""
                    loop k
                        run .= (A_Index > 1 ? " " : "") codes[out.Length - k + A_Index]
                    if InStr(onsets, "|" run "|")
                        break
                    k--
                }
                if (k = 1 && codes[out.Length] = "NG")
                    k := 0
                at := out.Length - k + 1
                out.InsertAt(at, Chr(m[2] = "1" ? 0x2C8 : 0x2CC)), codes.InsertAt(at, "")
            }
            v := (m[1] = "AH" && m[2] = "0") ? Chr(0x259) : (m[1] = "ER" && m[2] = "0") ? Chr(0x25A) : sym[m[1]]
            out.Push(v), codes.Push("")
            lastV := out.Length
        }
        return out.Length ? "/" Join(out, "") "/" : ""
    }

    static Blank() => Map("groups", [], "phonetic", "", "lemma", "", "lemmaOf", "")

    ; Entries made only of obsolete / archaic senses go last
    static Finalize(out) {
        if !out["groups"].Length
            return ""
        live := [], dead := []
        for grp in out["groups"] {
            allLow := true
            for s in grp["senses"]
                if !s["low"] {
                    allLow := false
                    break
                }
            (allLow ? dead : live).Push(grp)
        }
        for grp in dead
            live.Push(grp)
        out["groups"] := live
        return out
    }

    static LowLast(senses) {
        hi := [], lo := []
        for s in senses
            (s["low"] ? lo : hi).Push(s)
        for s in lo
            hi.Push(s)
        return hi
    }

    static IsLow(tags, txt) {
        hay := Join(tags, " ") " " SubStr(txt, 1, 60)
        return RegExMatch(hay, "i)\b(obsolete|archaic|rare|dated|dialect(al)?|historical|nonstandard|eye dialect)\b") ? 1 : 0
    }

    ; "present participle and gerund of run" -> "run"
    static FormOf(txt) {
        return RegExMatch(txt, "i)\bof\s+([a-z][a-z'\- ]*?)\s*[.;]?$", &m) ? StrLower(m[1]) : ""
    }

    ; Drops the grammar labels a learner does not need from the leading
    ; bracket - "(countable, slang)" becomes "(slang)", "(transitive)" goes.
    static Tidy(t) {
        t := Trim(RegExReplace(t, "\s+", " "))
        if RegExMatch(t, "^\(([^()]*)\)\s*(.*)$", &m) {
            keep := []
            for tag in StrSplit(m[1], ",", " ")
                if !RegExMatch(tag, "i)^(countable|uncountable|transitive|intransitive|ambitransitive|ergative|not comparable|comparable|usually plural|in the plural|plural only|singular only|reflexive|copulative|stative)$")
                    keep.Push(tag)
            t := (keep.Length ? "(" Join(keep, ", ") ") " : "") m[2]
        }
        return t
    }

    static Plain(h) {
        if (h is Map)
            h := Dig(h, "text")
        if (Type(h) != "String")
            return ""
        h := RegExReplace(h, "<[^>]*>")
        while RegExMatch(h, "&#(x?)([0-9a-fA-F]+);", &m)
            h := StrReplace(h, m[0], Chr(m[1] ? Integer("0x" m[2]) : Integer(m[2])))
        for pair in [["&lt;", "<"], ["&gt;", ">"], ["&quot;", '"'], ["&nbsp;", " "], ["&amp;", "&"]]
            h := StrReplace(h, pair[1], pair[2])
        return Trim(RegExReplace(h, "\s+", " "))
    }

    ; Wiktionary writes Persian with its vowel marks; everyday Persian does not
    static NoHarakat(w) => RegExReplace(w, "[\x{064B}-\x{065F}\x{0670}]")
}

;--------------------------------------------------------------------------------
; The translation: {main, groups: [{pos, terms: [...]}]}
; Google's dictionary block is the useful part for a word with several
; meanings - bank: noun -> bank / shore / edge / ... - and FaForPos() in
; Store.ahk uses it to pick the translation that matches the chosen sense.
;--------------------------------------------------------------------------------
class FaTrack extends Track {
    Start() {
        if this.FromCache(Lang.CacheKind())
            return
        ; a word is looked up in lower case, but a sentence or a paragraph is
        ; translated as written - and only as much of it as a URL will carry
        q := (this.lk.mode = "word") ? this.lk.query : SubStr(this.lk.word, 1, 1200)
        e := Http.Enc(q)
        base := "https://translate.googleapis.com/translate_a/single?sl=en&tl=" Lang.Code() "&dt=t&dt=bd&q=" e "&client="
        this.steps := [
            {name: "Google", url: base "dict-chrome-ex", parse: ObjBindMethod(FaTrack, "Google", q)},
            {name: "Google (gtx)", url: base "gtx", parse: ObjBindMethod(FaTrack, "Google", q)},
            {name: "Lingva", url: "https://lingva.ml/api/v1/en/" Lang.Lingva() "/" e, parse: ObjBindMethod(FaTrack, "Lingva", q)},
            {name: "MyMemory", url: "https://api.mymemory.translated.net/get?langpair=en%7C" Lang.Code() "&q=" e
                , parse: ObjBindMethod(FaTrack, "MyMemory", q)}
        ]
    }

    static Google(q, r) {
        d := Json.Parse(r.text)            ; the "automated queries" page is HTML and throws here
        main := ""
        for seg in (Dig(d, 1) || [])
            main .= Dig(seg, 1)
        main := Trim(main)
        groups := []
        for grp in (Dig(d, 2) || []) {
            terms := []
            for t in (Dig(grp, 2) || [])
                if (terms.Length < 6)
                    terms.Push(t)
            if terms.Length
                groups.Push(Map("pos", Dig(grp, 1), "terms", terms))
        }
        if (!groups.Length && (main = "" || main = q))
            return ""
        return Map("main", main, "groups", groups)
    }

    static Lingva(q, r) {
        t := Trim(Dig(Json.Parse(r.text), "translation"))
        return (t = "" || t = q) ? "" : Map("main", t, "groups", [])
    }

    static MyMemory(q, r) {
        d := Json.Parse(r.text)
        t := Trim(Dig(d, "responseData", "translatedText"))
        if (Dig(d, "responseStatus") != 200 || t = "" || t = q || InStr(t, "MYMEMORY"))
            return ""
        return Map("main", RTrim(t, ". "), "groups", [])
    }
}

;--------------------------------------------------------------------------------
; Gemini: {lemma, pos, meaning, persian, note, example}, for THIS sentence -
; "persian" being the translation, in whichever language is chosen
;
; Model choice is automatic unless Vocab.ini names one: the first lookup asks
; the API which models the key can use and lines up the three newest Flash,
; then the two newest Flash-Lite, then Google's flash-latest aliases as a last
; guess. Each model has its own free quota, so running out on one (HTTP 429)
; simply moves to the next, and the one that answered goes first from then on. If the list cannot be fetched - no network for a moment - the
; guess serves that one lookup and the list is asked for again next time;
; kept, it would pin every later lookup to the guess until a restart.
;
; Thinking is turned down - it is a lookup, not a puzzle, and thinking costs
; seconds. 2.5 models take thinkingBudget, 3.x take thinkingLevel; if a model
; rejects either, the request is repeated without it.
;--------------------------------------------------------------------------------
class AiTrack extends Track {
    static chain := "", good := "", keyBad := ""
    static Api := "https://generativelanguage.googleapis.com/v1beta/"
    ; the -latest aliases follow whatever Flash is current, so they never go
    ; out of date the way named models do (docs\decisions.md)
    static Guess := ["gemini-flash-latest", "gemini-flash-lite-latest"]

    Start() {
        this.key := GeminiKey()
        this.noThink := false
        if (this.key = "") {
            this.enabled := false, this.done := true, this.note := "no key"
            return
        }
        if (AiTrack.keyBad = this.key) {
            this.done := true, this.note := "key rejected - check it in Settings"
            return
        }
        this.models := AiTrack.Models()
        this.steps := this.models.Length ? [this.GenStep(this.models[1])] : [this.ListStep()]
    }

    static Models() {
        chain := AiTrack.chain ? AiTrack.chain.Clone() : []
        m := GeminiModel()
        if (m != "") {
            if !chain.Length
                chain := AiTrack.Guess.Clone()
            chain.InsertAt(1, m)
        }
        if (AiTrack.good != "" && chain.Length)
            chain.InsertAt(1, AiTrack.good)
        out := []
        for x in chain
            if !HasVal(out, x)
                out.Push(x)
        return out
    }

    ListStep() {
        return {name: "Gemini models", kind: "list", url: AiTrack.Api "models?pageSize=1000"
            , opts: {timeout: 6000, headers: Map("x-goog-api-key", this.key)}
            , parse: ObjBindMethod(AiTrack, "PickModels")}
    }

    GenStep(model) {
        think := ""
        if !this.noThink {
            if RegExMatch(model, "^gemini-2\.5-flash")
                think := Map("thinkingBudget", 0)
            else if RegExMatch(model, "^gemini-([3-9]|flash)")      ; flash-latest is a 3.x
                think := Map("thinkingLevel", "low")
        }
        cfg := Map("responseMimeType", "application/json", "temperature", 0.2)
        if IsObject(think)
            cfg["thinkingConfig"] := think
        body := Json.Dump(Map("contents", [Map("role", "user", "parts", [Map("text", AiTrack.Prompt(this.lk))])]
            , "generationConfig", cfg), "", true)
        return {name: "Gemini", kind: "gen", model: model, think: IsObject(think)
            , url: AiTrack.Api "models/" model ":generateContent"
            , opts: {method: "POST", body: body, timeout: 15000
                , headers: Map("x-goog-api-key", this.key, "Content-Type", "application/json")}
            , parse: ObjBindMethod(AiTrack, "Answer", this.lk.mode)}
    }

    Got(s, r, result) {
        msg := r.Ok ? "" : AiTrack.ErrMsg(r)
        if AiTrack.IsKeyError(r, msg) {
            AiTrack.keyBad := this.key
            this.note := "key rejected - check it in Settings"
            return this.Finish()
        }
        if InStr(msg, "location is not supported") {
            this.note := "Gemini is not offered in your region"
            return this.Finish()
        }
        if (s.kind = "list") {
            if result
                AiTrack.chain := result
            this.models := AiTrack.Models()
            if !this.models.Length
                this.models := AiTrack.Guess.Clone()
            this.steps := [this.GenStep(this.models[1])]
            return false
        }
        if result {
            AiTrack.good := s.model
            this.Take(s, result)
            this.source := "Gemini " RegExReplace(s.model, "^gemini-")
            return this.Finish()
        }
        if (r.status = 400 && s.think && !this.noThink) {
            this.noThink := true
            this.steps := [this.GenStep(s.model)]
            return false
        }
        if (r.status = 429 || r.status = 404 || r.status = 403 || r.status >= 500 || r.err != "") {
            for i, m in this.models
                if (m = s.model && i < this.models.Length) {
                    this.steps := [this.GenStep(this.models[i + 1])]
                    return false
                }
        }
        this.note := (r.status = 429) ? "free quota used up for now"
                   : r.Ok ? "no usable answer"
                   : (msg != "") ? Http.Short(msg) : r.Why
        return this.Finish()
    }

    ; A whole sentence, for someone reading a game or a blog: what it says in
    ; plain English, and a translation that reads naturally rather than
    ; word by word.
    static SentencePrompt(lk) {
        return "You help a native " Lang.PromptName() " speaker who is learning English.`n`n"
            . "This text - one sentence, or a few short ones that belong together, like a line"
            . " of dialogue - was read off their screen, so it may contain small recognition"
            . " errors or be cut short at either end:`n"
            . Chr(34) lk.word Chr(34) "`n`n"
            . "Reply with JSON only, with exactly these keys:`n"
            . '{"fixed": "", "simple": "", "translation": "", "note": ""}' "`n`n"
            . "fixed: the text with obvious recognition errors repaired; empty if it"
            . " already reads correctly`n"
            . "simple: what it means, in simple English, one or two short sentences`n"
            . "translation: a natural " Lang.PromptName() " translation - how a native speaker would say it,"
            . " not word for word`n"
            . "note: an idiom, a joke, slang or a reference worth a few words of explanation;"
            . " otherwise empty"
    }

    ; A note, a blog paragraph, a page of patch notes: what does it actually
    ; say. Short, and in both languages.
    static ParagraphPrompt(lk) {
        return "You help a native " Lang.PromptName() " speaker who is learning English.`n`n"
            . "This text was read off their screen, so it may contain recognition errors, and"
            . " lines belonging to other things on screen may have crept in:`n"
            . Chr(34) lk.word Chr(34) "`n`n"
            . "Reply with JSON only, with exactly these keys:`n"
            . '{"summary": "", "translation": "", "note": ""}' "`n`n"
            . "summary: what this text says, in simple English, two or three short sentences."
            . " Ignore anything that clearly belongs to something else on the screen`n"
            . "translation: the same summary in natural " Lang.PromptName() "`n"
            . "note: a name, a term or a reference worth a few words; otherwise empty"
    }

    static IsKeyError(r, msg) {
        return (r.status = 400 || r.status = 401 || r.status = 403)
            && (InStr(msg, "API key") || InStr(msg, "API_KEY"))
    }

    static ErrMsg(r) {
        try return Dig(Json.Parse(r.text), "error", "message")
        return ""
    }

    static PickModels(r) {
        flash := [], lite := []
        for m in (Dig(Json.Parse(r.text), "models") || []) {
            name := StrReplace(Dig(m, "name"), "models/")
            if !HasVal(Dig(m, "supportedGenerationMethods") || [], "generateContent")
                continue
            if RegExMatch(name, "^gemini-(\d+(?:\.\d+)?)-flash$", &v)
                AiTrack.Insert(flash, Float(v[1]), name)
            else if RegExMatch(name, "^gemini-(\d+(?:\.\d+)?)-flash-lite$", &v)
                AiTrack.Insert(lite, Float(v[1]), name)
        }
        chain := []
        for i, x in flash
            if (i <= 3)
                chain.Push(x[2])
        for i, x in lite
            if (i <= 2)
                chain.Push(x[2])
        for x in AiTrack.Guess
            if !HasVal(chain, x)
                chain.Push(x)
        return chain
    }

    static Insert(list, ver, name) {         ; newest first
        for i, x in list
            if (ver > x[1]) {
                list.InsertAt(i, [ver, name])
                return
            }
        list.Push([ver, name])
    }

    static Answer(mode, r) {
        d := Json.Parse(r.text)
        txt := ""
        for p in (Dig(d, "candidates", 1, "content", "parts") || [])
            if !Dig(p, "thought")
                txt .= Dig(p, "text")
        a := InStr(txt, "{"), b := InStr(txt, "}", , -1)
        if (!a || b < a)
            return ""
        j := Json.Parse(SubStr(txt, a, b - a + 1))
        if !(j is Map)
            return ""
        out := Map()
        keys := (mode = "sentence") ? ["fixed", "simple", "translation", "note"]
             : (mode = "paragraph") ? ["summary", "translation", "note"]
             : ["lemma", "pos", "meaning", "translation", "note", "example", "corrected"]
        for k in keys {
            v := Dig(j, k)
            out[k] := Trim((v is Array) ? Join(v, Lang.Sep()) : IsObject(v) ? "" : String(v))
        }
        out["persian"] := out.Delete("translation")         ; its name everywhere else - see Language.ahk
        if (mode = "sentence")
            return (out["simple"] = "" && out["persian"] = "") ? "" : out
        if (mode = "paragraph")
            return (out["summary"] = "" && out["persian"] = "") ? "" : out
        return (out["meaning"] = "") ? "" : out
    }

    static Prompt(lk) {
        if (lk.mode = "sentence")
            return AiTrack.SentencePrompt(lk)
        if (lk.mode = "paragraph")
            return AiTrack.ParagraphPrompt(lk)
        ctx := Trim(lk.context)
        p := "You help a native " Lang.PromptName() " speaker who is learning English understand words they meet on screen.`n`n"
        p .= 'Word or phrase: "' lk.word '"`n'
        if (ctx != "")
            p .= 'Where they saw it (screen text read by OCR, may contain recognition errors): "' ctx '"`n'
        else
            p .= "No sentence is available, so explain its most common meaning.`n"
        p .= "`nReply with JSON only, with exactly these keys:`n"
            . '{"corrected": "", "lemma": "", "pos": "", "meaning": "", "translation": "", "note": "", "example": ""}' "`n`n"
            . "corrected: the word itself is read off the screen and can come back damaged - a"
            . " letter lost to a highlight box, or two words run together. If it is clearly a"
            . " misreading of a word in the sentence, put the correct word here and answer"
            . " about THAT word; otherwise leave it empty`n"
            . "lemma: the dictionary form of the word, or the phrasal verb or idiom it belongs to here`n"
            . "pos: its part of speech here`n"
            . "meaning: the meaning" ((ctx != "") ? " used in THIS sentence" : "") ", in simple English, at most 20 words`n"
            . "translation: the natural " Lang.PromptName() " equivalent of that meaning, 1 to 4 words, written in " Lang.Cur().name "`n"
            . "note: if it is part of an idiom, a phrasal verb or slang here, say so in a few words; otherwise empty`n"
            . "example: " ((ctx != "") ? "the sentence with obvious OCR errors fixed, or empty if it is not a real sentence"
                                       : "one short natural example sentence")
        return p
    }
}
