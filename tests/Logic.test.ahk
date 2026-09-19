;================================================================================
; Logic.test.ahk - the rules, with no screen and no network
;================================================================================
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Harness.ahk

;--- keys: what is refused, what is only warned about ---------------------------
for a in Keys.List                      ; the defaults, without registering them
    Keys.cur[a.id] := a.def
refused := Map("a", "a letter on its own", "+a", "Shift + a letter", "#vk4C", "Win + L"
    , "!Tab", "Alt + Tab", "!F4", "Alt + F4", "^!Delete", "Ctrl + Alt + Del"
    , "^vk43", "Ctrl + C", "^+Escape", "Ctrl + Shift + Esc", "Space", "Space alone"
    , "LButton", "a plain click", "+#LButton", "another action's key")
for hk, why in refused
    CheckTrue("key refused: " why, Keys.Check(hk, "Word").err != "", hk " was accepted")
for hk in ["#F8", "#MButton", "^!vkBE", "F9", "XButton1", "#vk45"]
    CheckTrue("key accepted: " hk, Keys.Check(hk, "Word").err = "", Keys.Check(hk, "Word").err)
Check("key: Win + F8 has no warning", Keys.Check("#F8", "Word").warn, "")
CheckTrue("key: F9 alone warns", Keys.Check("F9", "Word").warn != "")
CheckTrue("key: own key is not a conflict", Keys.Check("#LButton", "Word").err = "")

Check("label: Shift + Win + Click", Keys.Label("+#LButton"), "Shift + Win + Click")
Check("label: Win + backtick", Keys.Label("#vkC0"), "Win + ``")
Check("label: tight", Keys.Label("^!vkBE", true), "Ctrl+Alt+.")
Check("label: mouse back", Keys.Label("XButton1"), "Mouse back")
Check("label: off", Keys.Label(""), "none")
Check("keyname: letter by position", Keys.KeyName(0x41, 0x1E), "vk41")
Check("keyname: Home", Keys.KeyName(0x24, 0x147), "Home")
Check("keyname: NumpadHome", Keys.KeyName(0x24, 0x47), "NumpadHome")
Check("same key written two ways", Keys.Parse("#``").same, Keys.Parse("#vkC0").same)
tip := Keys.TrayText()
CheckTrue("tray tip fits", StrLen(tip) <= 127, StrLen(tip) " characters")
CheckHas("tray tip has every default key", tip, "word`n", "translate", "summary", "selection", "box", "word list")

;--- sentences: what Translate takes -------------------------------------------
SpanOf(all, near, whole := true) {
    r := SpanRange(all, InStr(all, near, true), whole)
    return Trim(SubStr(all, r[1], r[2] - r[1] + 1))
}
dialog := "Wait. No. Not that one. The other door, the red one."
Check("span: dialogue in pieces comes whole", SpanOf(dialog, "No."), dialog)
clauses := ""                           ; eleven pieces, cut only by colons
loop 11
    clauses .= "clause " A_Index " has some words: "
got := SpanOf(clauses, "clause 6 ")
CheckTrue("span: colons split Translate's sentences", !InStr(got, "clause 1 has") && InStr(got, "clause 11 has"), got)
Check("span: word example keeps the colon", SpanOf("The guard nodded: he had seen it. Nobody knew.", "nodded", false)
    , "The guard nodded: he had seen it.")
long := ""
loop 14
    long .= "Sentence number " A_Index " is here with some words. "
got := SpanOf(long, "number 7 ")
CheckTrue("span: at most ten sentences", StrSplit(got, ".").Length - 1 = 10, got)
CheckHas("span: around the pointer", got, "number 7 ", "number 6 ", "number 8 ")
Check("span: word example cuts at an ellipsis, not a semicolon"
    , SpanOf("He waited" Chr(0x2026) " Then he left; nobody saw.", "left", false), "Then he left; nobody saw.")
CheckTrue("span: 10:30 does not split", SpanOf("We meet at 10:30 today. Bring it.", "today") = "We meet at 10:30 today. Bring it.")

IniWrite(1, VocabIni(), "Translation", "Sentences")    ; the tests' own Vocab.ini
Check("span: set to one sentence, only the one clicked", SpanOf(dialog, "the red"), "The other door, the red one.")
Check("span: set to one sentence, even a short one", SpanOf(dialog, "No."), "No.")
IniDelete(VocabIni(), "Translation", "Sentences")
Check("span: back to the passage", SpanOf(dialog, "No."), dialog)

RowOf(t) => ({text: t})
CheckTrue("line ends: colon", EndsText(RowOf("It was not a limitation. Now:")))
CheckTrue("line ends: quote after stop", EndsText(RowOf("he said." Chr(34))))
CheckTrue("line runs on: no stop", !EndsText(RowOf("get read as one wrapped")))
CheckTrue("line runs on: stop mid-line only", !EndsText(RowOf("bleh bleh.bleh")))

;--- lines ---------------------------------------------------------------------
r3 := [{text: "one", y1: 0, y2: 20, h: 20}, {text: "two", y1: 24, y2: 44, h: 20}, {text: "three", y1: 80, y2: 100, h: 20}]
Check("lines: paragraph gap becomes a new line", JoinRows(r3), "one two`nthree")

;--- the popup stays on the screen ---------------------------------------------
wa := WorkAreaAt(100, 100)
cases := [["big block", {x: wa[1] + 20, y: wa[2] + 20, w: wa[3] - wa[1] - 40, h: wa[4] - wa[2] - 40}, "over"]
    , ["block near bottom", {x: wa[1] + 100, y: wa[4] - 200, w: 900, h: 150}, "above"]
    , ["tall narrow on left", {x: wa[1] + 10, y: wa[2] + 10, w: 500, h: wa[4] - wa[2] - 20}, "right"]
    , ["word mid-screen", {x: wa[1] + 800, y: wa[2] + 400, w: 60, h: 20}, "below"]
    , ["word at bottom", {x: wa[1] + 800, y: wa[4] - 25, w: 60, h: 20}, "above"]]
for c in cases {
    Popup.anchor := c[2]
    Popup.Plan(520)
    h := Min(PopMaxH, Popup.capH), y := Popup.PlaceY(h)
    CheckTrue("popup inside the screen: " c[1]
        , Popup.px >= wa[1] && Popup.px + 520 <= wa[3] && y >= wa[2] && y + h <= wa[4]
        , "x " Popup.px " y " y " h " h)
    ; which side it picks depends on the room there is; the expected sides are
    ; for a normal desktop, not a build server's small virtual screen
    if (wa[3] - wa[1] >= 1400 && wa[4] - wa[2] >= 900)
        Check("popup side: " c[1], Popup.side, c[3])
}

;--- the translation language ----------------------------------------------------
Check("language: default is Persian", Lang.Find("").code, "fa")
Check("language: unknown falls back to Persian", Lang.Find("xx").code, "fa")
CheckTrue("language: Persian is right-to-left", Lang.Rtl("fa"))
CheckTrue("language: Spanish is not", !Lang.Rtl("es"))
Check("language: Persian comma", Lang.Sep("fa"), Chr(0x060C) " ")
Check("language: plain comma", Lang.Sep("de"), ", ")
Check("language: label", Lang.Label("es"), "SPANISH")
saved := Lang.current
Lang.current := Lang.Find("zh-CN")
Check("language: Lingva's own code", Lang.Lingva(), "zh")
Check("language: its own cache", Lang.CacheKind(), "fa.zh-CN")
fake := {mode: "word", word: "bank", context: "The boat reached the bank."}
CheckHas("language: the word prompt names it", AiTrack.Prompt(fake), "Chinese (Simplified) speaker", '"translation"')
fake.mode := "sentence"
CheckHas("language: the sentence prompt names it", AiTrack.Prompt(fake), "Chinese (Simplified) speaker", "translation: a natural Chinese (Simplified)")
CheckTrue("language: old senses are not shown in a new language", !Lang.SensesMatch(Map("groups", [])))
Lang.current := Lang.Find("fa")
CheckTrue("language: old senses are Persian", Lang.SensesMatch(Map("groups", [])))
Check("language: the old cache name stays", Lang.CacheKind(), "fa")
Lang.current := saved
answer := '{"simple": "It is red.", "translation": "Es rojo.", "fixed": "", "note": ""}'
part := Map("text", answer)
reply := {text: Json.Dump(Map("candidates", [Map("content", Map("parts", [part]))]))}
got := AiTrack.Answer("sentence", reply)
Check("language: Gemini's translation is filed as before", got ? got["persian"] : "", "Es rojo.")

;--- pinning -------------------------------------------------------------------
Check("pin: none on the word list", PinAction(Dict), "")
CheckTrue("pin: a popup has one", IsObject(PinAction(Popup)))

;--- small helpers -------------------------------------------------------------
Check("clean word: quotes and comma", CleanWord(Chr(0x201C) "Hello," Chr(0x201D)), "Hello")
Check("clean word: possessive", CleanWord("harbour's"), "harbour")
CheckTrue("Gemini fix: a real correction", UsableFix("teaching", "eachin"))
CheckTrue("Gemini fix: same word is ignored", !UsableFix("Teaching", "teaching"))
CheckTrue("Gemini fix: a sentence is ignored", !UsableFix("this is not a word at all", "word"))

Done()
