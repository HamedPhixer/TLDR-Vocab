;================================================================================
; Language.ahk - the language translations go into
;================================================================================
; What you read is always English; what it is translated into is a setting
; (Settings > TRANSLATION, kept in Vocab.ini as [Translation] Language=fa).
; Everything that depends on it asks here, so no other file names a language:
;   the translators     Lang.Code(), and Lingva's own code where it differs
;   Gemini's prompts    Lang.PromptName()
;   the cards           Lang.Label() for the heading, Lang.Rtl() for the
;                       right-to-left layout, Lang.Sep() between terms
;   the cache           Lang.CacheKind(): one cache entry per language
;
; Inside the code and in words.json the translation kept the names it had
; when Persian was the only language: "persian" for the text, "fa" for its
; details. Renaming them would break every saved word for nothing, so they
; stay, and mean "the translation". Each saved word also notes its language
; in "lang"; one saved before there was a choice is Persian.
;================================================================================
#Requires AutoHotkey v2.0

class Lang {
    ; code: Google and MyMemory's code. lingva: Lingva's, when different.
    ; dict: the code freedictionaryapi.com files translations under, when
    ; different. prompt: how Gemini is told the language, when not just name.
    static List := [
        {code: "fa", name: "Persian", prompt: "Persian (Farsi)", rtl: true},
        {code: "ar", name: "Arabic", rtl: true},
        {code: "ur", name: "Urdu", rtl: true},
        {code: "tr", name: "Turkish"},
        {code: "es", name: "Spanish"},
        {code: "fr", name: "French"},
        {code: "de", name: "German"},
        {code: "it", name: "Italian"},
        {code: "pt", name: "Portuguese"},
        {code: "nl", name: "Dutch"},
        {code: "pl", name: "Polish"},
        {code: "ru", name: "Russian"},
        {code: "uk", name: "Ukrainian"},
        {code: "hi", name: "Hindi"},
        {code: "id", name: "Indonesian"},
        {code: "vi", name: "Vietnamese"},
        {code: "zh-CN", lingva: "zh", dict: "cmn", name: "Chinese", prompt: "Chinese (Simplified)"},
        {code: "ja", name: "Japanese"},
        {code: "ko", name: "Korean"}
    ]
    static current := ""

    static Find(code) {
        for l in Lang.List
            if (l.code = code)
                return l
        return Lang.List[1]                 ; unknown or empty: Persian, as it always was
    }

    ; the chosen language, read from Vocab.ini once and kept
    static Cur() {
        if !Lang.current
            Lang.current := Lang.Find(Trim(IniRead(VocabIni(), "Translation", "Language", "fa")))
        return Lang.current
    }

    static Set(code) {
        Lang.current := Lang.Find(code)
        IniWrite(Lang.current.code, VocabIni(), "Translation", "Language")
    }

    static Code()   => Lang.Cur().code
    static Lingva() => Lang.Cur().HasProp("lingva") ? Lang.Cur().lingva : Lang.Cur().code
    static Dict()   => Lang.Cur().HasProp("dict") ? Lang.Cur().dict : Lang.Cur().code
    static PromptName() => Lang.Cur().HasProp("prompt") ? Lang.Cur().prompt : Lang.Cur().name
    static Label(code := "") => StrUpper(((code != "") ? Lang.Find(code) : Lang.Cur()).name)
    static Rtl(code := "") => ((code != "") ? Lang.Find(code) : Lang.Cur()).HasProp("rtl")

    ; what goes between two terms: the Arabic comma for the languages that
    ; use it, a plain one for the rest
    static Sep(code := "") => InStr(" fa ar ur ", " " ((code != "") ? code : Lang.Code()) " ") ? Chr(0x060C) " " : ", "

    ; Persian keeps the cache name it always had, so words looked up before
    ; there was a choice are still found
    static CacheKind() => (Lang.Code() = "fa") ? "fa" : "fa." Lang.Code()

    ; Definitions are cached once for every language, but the short
    ; translation some senses carry is in the language of that day (kept as
    ; "faLang"; none means Persian). It is only shown in that same language.
    static SensesMatch(def) => (def is Map) && ((Dig(def, "faLang") != "") ? def["faLang"] : "fa") = Lang.Code()
    static SenseTr(def, s) => Lang.SensesMatch(def) ? Dig(s, "fa") : ""
}
