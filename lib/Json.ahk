;================================================================================
; Json.ahk - a small JSON reader and writer for AutoHotkey v2
;================================================================================
; Json.Parse(text)
;     objects -> Map, arrays -> Array, true/false -> 1/0, null -> "".
;     A null field and a missing one therefore read the same, which is exactly
;     what every caller here wants. Throws on malformed input - the callers
;     treat that as "this source failed, try the next one".
;
; Json.Dump(value, indent := "", ascii := false)
;     Map / Array / plain Object -> JSON text; indent "" gives a single line.
;     ascii := true writes every non-ASCII character as \uXXXX. Request bodies
;     go out that way, so nothing on the wire can be mangled by a code page.
;
; Strings are found with InStr rather than a regex: a dictionary response can
; be a few hundred KB, and InStr jumps straight to the next quote.
;================================================================================
#Requires AutoHotkey v2.0

class Json {
    static Parse(text) {
        pos := 1
        v := Json._Val(&text, &pos)
        Json._Ws(&text, &pos)
        if (pos <= StrLen(text))
            throw Error("JSON: unexpected text at " pos)
        return v
    }

    static _Ws(&t, &p) {
        loop {
            c := SubStr(t, p, 1)
            if (c != " " && c != "`n" && c != "`r" && c != "`t")
                return
            p++
        }
    }

    static _Val(&t, &p) {
        Json._Ws(&t, &p)
        c := SubStr(t, p, 1)
        if (c == "{") {
            obj := Map(), p++
            Json._Ws(&t, &p)
            if (SubStr(t, p, 1) == "}")
                return (p++, obj)
            loop {
                Json._Ws(&t, &p)
                if (SubStr(t, p, 1) != '"')
                    throw Error("JSON: expected a key at " p)
                k := Json._Str(&t, &p)
                Json._Ws(&t, &p)
                if (SubStr(t, p, 1) != ":")
                    throw Error("JSON: expected : at " p)
                p++
                obj[k] := Json._Val(&t, &p)
                Json._Ws(&t, &p)
                c := SubStr(t, p++, 1)
                if (c == "}")
                    return obj
                if (c != ",")
                    throw Error("JSON: expected , or } at " (p - 1))
            }
        }
        if (c == "[") {
            arr := [], p++
            Json._Ws(&t, &p)
            if (SubStr(t, p, 1) == "]")
                return (p++, arr)
            loop {
                arr.Push(Json._Val(&t, &p))
                Json._Ws(&t, &p)
                c := SubStr(t, p++, 1)
                if (c == "]")
                    return arr
                if (c != ",")
                    throw Error("JSON: expected , or ] at " (p - 1))
            }
        }
        if (c == '"')
            return Json._Str(&t, &p)
        if InStr("-0123456789", c) && c != "" {
            s := p
            while InStr("+-.eE0123456789", SubStr(t, p, 1)) && SubStr(t, p, 1) != ""
                p++
            n := SubStr(t, s, p - s)
            return RegExMatch(n, "[.eE]") ? Float(n) : Integer(n)
        }
        if (SubStr(t, p, 4) == "true")
            return (p += 4, 1)
        if (SubStr(t, p, 5) == "false")
            return (p += 5, 0)
        if (SubStr(t, p, 4) == "null")
            return (p += 4, "")
        throw Error("JSON: unexpected '" c "' at " p)
    }

    ; p sits on the opening quote; leaves it just past the closing one
    static _Str(&t, &p) {
        s := p + 1, e := s
        loop {
            e := InStr(t, '"', true, e)
            if !e
                throw Error("JSON: unterminated string")
            b := 0                          ; an odd run of backslashes escapes it
            while (SubStr(t, e - 1 - b, 1) == "\")
                b++
            if !(b & 1)
                break
            e++
        }
        raw := SubStr(t, s, e - s)
        p := e + 1
        return InStr(raw, "\") ? Json._Unescape(raw) : raw
    }

    static _Unescape(s) {
        out := "", i := 1
        while (j := InStr(s, "\", true, i)) {
            out .= SubStr(s, i, j - i)
            c := SubStr(s, j + 1, 1)
            if (c == "u") {
                out .= Chr(Integer("0x" SubStr(s, j + 2, 4)))
                i := j + 6
                continue
            }
            out .= (c == "n") ? "`n" : (c == "t") ? "`t" : (c == "r") ? "`r"
                 : (c == "b") ? Chr(8) : (c == "f") ? Chr(12) : c
            i := j + 2
        }
        return out SubStr(s, i)
    }

    static Dump(v, indent := "", ascii := false, lvl := "") {
        if (v is Map || v is Array || Type(v) = "Object") {
            nl := (indent = "") ? "" : "`n"
            inner := lvl indent
            parts := []
            if (v is Array) {
                for x in v
                    parts.Push(inner Json.Dump(IsSet(x) ? x : "", indent, ascii, inner))
                open := "[", close := "]"
            } else {
                colon := (indent = "") ? ":" : ": "
                for k, x in (v is Map ? v : v.OwnProps())
                    parts.Push(inner Json._Q(String(k), ascii) colon Json.Dump(x, indent, ascii, inner))
                open := "{", close := "}"
            }
            if !parts.Length
                return open close
            body := ""
            for i, s in parts
                body .= (i > 1 ? "," nl : "") s
            return open nl body nl lvl close
        }
        if (v is Integer || v is Float)
            return String(v)
        return Json._Q(String(v), ascii)
    }

    static _Q(s, ascii) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        if RegExMatch(s, "[\x00-\x1F]" (ascii ? "|[^\x00-\x7F]" : "")) {
            out := ""
            loop parse s {
                o := Ord(A_LoopField)
                out .= (o < 0x20 || (ascii && o > 0x7E)) ? Format("\u{:04x}", o) : A_LoopField
            }
            s := out
        }
        return '"' s '"'
    }
}

; Safe nested read: Dig(data, "entries", 1, "senses") is "" as soon as any step
; is missing, instead of throwing. Works across Maps and Arrays.
Dig(v, path*) {
    for k in path {
        if (v is Map) {
            if !v.Has(k)
                return ""
            v := v[k]
        } else if (v is Array) {
            if !(k is Integer) || k < 1 || k > v.Length || !v.Has(k)
                return ""
            v := v[k]
        } else
            return ""
    }
    return v
}
