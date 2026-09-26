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

;--- the update check ----------------------------------------------------------
for pair in [["1.0.1", "1.0.0"], ["1.10.0", "1.2.0"], ["1.1.0", "1.1.0-beta.2"], ["1.1.0-beta.2", "1.1.0-beta.1"]
        , ["1.1.0-beta.10", "1.1.0-beta.2"], ["2.0.0-beta.1", "1.9.9"], ["1.1.0-rc.1", "1.1.0-beta.3"]]
    Check("update: " pair[1] " is newer than " pair[2], Update.Compare(pair[1], pair[2]) " " Update.Compare(pair[2], pair[1]), "1 -1")
Check("update: the same version", Update.Compare("1.1.0-beta.2", "1.1.0-beta.2"), 0)
rel(tag, pre := false, draft := false) => Map("tag_name", "v" tag, "prerelease", pre, "draft", draft, "html_url", "u/" tag)
list := [rel("1.2.0-beta.1", true), rel("1.1.0"), rel("1.1.0-beta.2", true), rel("1.3.0", false, true), rel("1.0.0")]
Check("update: a beta hears of a newer beta", Update.Newest(list, "1.1.0-beta.2")["version"], "1.2.0-beta.1")
Check("update: a finished version hears only of finished ones", Update.Newest(list, "1.0.0")["version"], "1.1.0")
Check("update: drafts never count, and nothing is newer", Update.Newest(list, "1.2.0-beta.1"), "")
Check("update: up to date", Update.Newest(list, "1.1.0"), "")
list[1]["body"] := "## New`n- **One** thing", list[1]["assets"] := [Map("name", "manifest.json"
    , "browser_download_url", "https://x/manifest.json", "size", 10, "digest", "sha256:ab")]
news := Update.Newest(list, "1.1.0-beta.2")
Check("update: the notes and files come along", news["notes"] " | " news["assets"][1]["name"] " " news["assets"][1]["size"]
    , "## New`n- **One** thing | manifest.json 10")
Check("update: the notes as plain text", Install.NotesText(news["notes"]), "NEW`r`n" Chr(0x2022) " One thing")
Check("update: wrapped note lines joined", Install.NotesText("- one`n  two`n  - three"), Chr(0x2022) " one two`r`n  " Chr(0x2022) " three")

;--- updating: what may be written ---------------------------------------------
for path in ["Vocab.ahk", "lib/Popup.ahk", "lib\Popup.ahk", "AutoHotkey64.exe", "Start TLDR Vocab.bat"]
    CheckTrue("swap: may write " path, Swap.SafeRel(path))
for path in ["", "../Vocab.ahk", "lib/../../x.ahk", "C:\Windows\x.dll", "\\server\x", "/lib/x.ahk", "Vocab.ini"
        , "words.json", "WORDS.JSON", "errors.log", "cache/a.json", "previous version/Vocab.ahk", ".git/config"
        , "words.unreadable-1.json", "lib/x.ahk.", "lib/x:y"]
    CheckTrue("swap: may not write [" path "]", !Swap.SafeRel(path))

; the release's files: only this app's own, for that version
release := Map("version", "1.2.0", "assets", [
    Map("name", "manifest.json", "url", RepoUrl "/releases/download/v1.2.0/manifest.json"),
    Map("name", "a.zip", "url", "https://evil.example/HamedPhixer/TLDR-Vocab/releases/download/v1.2.0/a.zip"),
    Map("name", "b.zip", "url", RepoUrl "/releases/download/v1.1.0/b.zip")])
CheckTrue("install: its own release's file", IsObject(Install.Asset(release, "manifest.json")))
Check("install: not from another address", Install.Asset(release, "a.zip"), "")
Check("install: not from another version", Install.Asset(release, "b.zip"), "")
Check("install: not a file it does not have", Install.Asset(release, "c.zip"), "")

sum := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
entry(path) => Map("path", path, "size", 1, "sha256", sum)
manifest(version := "1.2.0", extra := "") {
    files := [entry("Vocab.ahk"), entry("lib/All.ahk"), entry("lib/Updater.ahk"), entry("lib/Swap.ahk")]
    if (extra != "")
        files.Push(entry(extra))
    return Map("name", AppName, "version", version, "files", files, "portable", [entry("AutoHotkey64.exe")]
        , "zips", Map("plain", Map("size", 5, "sha256", sum), "portable", Map("size", 6, "sha256", sum)))
}
Check("install: a good manifest", Install.CheckManifest(manifest(), "1.2.0", "plain") Install.CheckManifest(manifest(), "1.2.0", "portable"), "")
Check("install: a portable copy gets AutoHotkey too", Install.Files(manifest(), "portable").Length " " Install.Files(manifest(), "plain").Length, "5 4")
CheckHas("install: another version's manifest", Install.CheckManifest(manifest("1.3.0"), "1.2.0", "plain"), "1.3.0")
CheckHas("install: a manifest naming the user's words", Install.CheckManifest(manifest(, "words.json"), "1.2.0", "plain"), "words.json")
CheckHas("install: a manifest reaching outside", Install.CheckManifest(manifest(, "../x.ahk"), "1.2.0", "plain"), "../x.ahk")
m := manifest(), m["zips"].Delete("portable")
CheckHas("install: no check sum for the zip", Install.CheckManifest(m, "1.2.0", "portable"), "portable zip")
m := manifest(), m["files"].RemoveAt(3)
CheckHas("install: a version that could not update itself", Install.CheckManifest(m, "1.2.0", "plain"), "Updater.ahk")

; SHA-256, against the published test values
tmp := A_Temp "\tldr-vocab-test"
try DirDelete(tmp, true)
DirCreate(tmp)
FileAppend("abc", tmp "\abc.txt", "UTF-8-RAW")
FileAppend("", tmp "\empty.txt")
Check("sha256: abc", Sha256File(tmp "\abc.txt"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
Check("sha256: nothing", Sha256File(tmp "\empty.txt"), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
FileAppend("abc", tmp "\bom.txt", "UTF-8")          ; EF BB BF, then abc
Check("sha256: every byte, a BOM too", Sha256File(tmp "\bom.txt"), "1c28dc3f1f804a1ad9c9b4b4cf5e2658d16ad4ed08e3020d04a8d2865018947c")

;--- updating: the swap, for real, in a temp folder ----------------------------
; an installed copy with the user's own files, and a new version beside it
put(path, text) {
    SplitPath(path, , &dir)
    DirCreate(dir)
    try FileDelete(path)
    FileAppend(text, path, "UTF-8-RAW")
}
read(path) => FileExist(path) ? FileRead(path, "UTF-8") : "(none)"
app := tmp "\app", new := tmp "\new"
setup() {
    global app, new
    try DirDelete(app, true)
    try DirDelete(new, true)
    for name, text in Map("Vocab.ahk", "old main", "lib\All.ahk", "old all", "lib\Gone.ahk", "old gone"
            , "Vocab.ini", "my key", "words.json", "my words", "cache\w.json", "my cache", "errors.log", "my log")
        put(app "\" name, text)
    for name, text in Map("Vocab.ahk", "new main", "lib\All.ahk", "new all", "lib\Added.ahk", "new added")
        put(new "\" name, text)
}
files := ["Vocab.ahk", "lib/All.ahk", "lib/Added.ahk"]
setup()
Check("swap: old code the new version dropped", Join(Swap.Leftovers(app, files), ","), "lib\Gone.ahk")
why := Swap.Apply(app, new, files, Swap.Leftovers(app, files), "about")
Check("swap: done", why, "")
Check("swap: the new files", read(app "\Vocab.ahk") "," read(app "\lib\All.ahk") "," read(app "\lib\Added.ahk") "," read(app "\lib\Gone.ahk")
    , "new main,new all,new added,(none)")
Check("swap: the user's files untouched", read(app "\Vocab.ini") "," read(app "\words.json") "," read(app "\cache\w.json") "," read(app "\errors.log")
    , "my key,my words,my cache,my log")
bak := app "\" Swap.BackupName
Check("swap: the old version kept", read(bak "\Vocab.ahk") "," read(bak "\lib\All.ahk") "," read(bak "\lib\Gone.ahk") "," read(bak "\about this folder.txt")
    , "old main,old all,old gone,about")
Check("swap: nothing of the user's in the backup", read(bak "\words.json") read(bak "\Vocab.ini"), "(none)(none)")

; a file that cannot be replaced (held open, as a virus scanner might): all of
; it is undone, and the folder is exactly as before
setup()
held := FileOpen(app "\lib\All.ahk", "r -rwd")
why := Swap.Apply(app, new, files, Swap.Leftovers(app, files))
held.Close()
CheckTrue("swap: a locked file fails the update", why != "", "no failure reported")
Check("swap: ...and everything is as before", read(app "\Vocab.ahk") "," read(app "\lib\All.ahk") "," read(app "\lib\Gone.ahk") "," read(app "\lib\Added.ahk")
    , "old main,old all,old gone,(none)")
Check("swap: ...the user's files too", read(app "\Vocab.ini") "," read(app "\words.json"), "my key,my words")
Check("swap: a list naming the user's words is refused whole", Swap.Apply(app, new, ["Vocab.ahk", "words.json"], [])
    , "the new version names a file it may not write: words.json")
Check("swap: ...before anything changed", read(app "\Vocab.ahk") "," read(app "\words.json"), "old main,my words")
try DirDelete(tmp, true)

; no connection at all (a proxy on a closed port): the check tries twice,
; a few seconds apart, then says so
IniWrite("127.0.0.1:9", VocabIni(), "Network", "Proxy")
try IniDelete(VocabIni(), "General", "LastUpdateCheck")
said := Map()
start := A_TickCount
Update.Check(false, (text, found) => said["text"] := text)
while (!said.Has("text") && A_TickCount - start < 40000)
    Sleep(100)
IniDelete(VocabIni(), "Network", "Proxy")
CheckHas("update: no connection says so", said.Has("text") ? said["text"] : "(no answer)", "Could not reach GitHub")
CheckTrue("update: ...after a second try", A_TickCount - start >= 3000, (A_TickCount - start) " ms")
Check("update: a day GitHub was not reached is not marked checked"
    , IniRead(VocabIni(), "General", "LastUpdateCheck", "(none)"), "(none)")

Check("network error: no double brackets",Http.Short("(0x80072EFD)"), "0x80072EFD")
Check("network error: the text kept", Http.Short("0x80072EE2 - The operation timed out`r`n"), "The operation timed out")

;--- a request that hangs gets a second copy -----------------------------------
; StallServer.ps1 never answers the first connection and answers the second
; at once: the step must take the second copy's answer soon after its hedge
class HedgeTest extends Track {
    Start() {
        this.steps := [{name: "stalling server", url: "http://127.0.0.1:18765/", hedge: 700
            , opts: {timeout: 8000}, parse: (r) => r.text}]
    }
}
IniWrite("none", VocabIni(), "Network", "Proxy")
ready := A_Temp "\vocab-stall-ready.txt"
try FileDelete(ready)
Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' A_ScriptDir '\StallServer.ps1" -Port 18765 -Ready "' ready '"', , "Hide")
start := A_TickCount
while (!FileExist(ready) && A_TickCount - start < 15000)
    Sleep(50)
t := HedgeTest({query: "hedge"})
start := A_TickCount
while (!t.done && A_TickCount - start < 10000) {
    t.Step()
    Sleep(50)
}
IniDelete(VocabIni(), "Network", "Proxy")
Check("hedge: a stuck request is answered by its second copy", t.data, "second")
CheckTrue("hedge: ...soon after the hedge, not at the timeout", A_TickCount - start < 3000, (A_TickCount - start) " ms")
CheckTrue("hedge: ...and it says it asked again", t.again)

;--- OCR: any engine, even one that cannot take the size asked for --------------
; A stand-in engine that reads at most 100 px and "finds" one word at a fixed
; place in whatever bitmap it gets: the boxes must come back in the frame
; that was asked for (200 x 50 enlarged 2x), not the one it read (100 x 25).
class TinyOcr {
    static Name := "test engine", MaxDim := 100, got := ""
    static Read(hbm) {
        bm := Buffer(32, 0)
        DllCall("GetObject", "ptr", hbm, "int", bm.Size, "ptr", bm)
        TinyOcr.got := NumGet(bm, 4, "int") "x" NumGet(bm, 8, "int")
        return [{text: "word", words: [{text: "word", x: 10, y: 5, w: 20, h: 10}]}]
    }
}
real := Ocr.Engine
Ocr.Engine := TinyOcr
w := Ocr.Screen(0, 0, 200, 50, 2)[1].words[1]
Ocr.Engine := real
Check("ocr: the engine gets no more than it takes", TinyOcr.got, "100x25")
Check("ocr: ...and the boxes come back in the frame asked for"
    , Round(w.x) "," Round(w.y) "," Round(w.w) "," Round(w.h), "40,20,80,40")
CheckTrue("ocr: Windows' engine is the one in use", Ocr.Engine.Name = "Windows OCR" && Ocr.MaxScale(800, 220) >= 1.5)

;--- Gemini: what happens after a failed request (no network: answers are faked)
IniWrite("test-key", VocabIni(), "Gemini", "ApiKey")
try FileDelete(AiTrack.StateFile)
AiTrack.chain := ["model-a", "model-b"], AiTrack.good := ""
AiTrack.loaded := true, AiTrack.listed := FormatTime(, "yyyyMMdd")    ; no list request
Fail(err, status := 0) => {err: err, status: status, text: "", Ok: false, Why: (err != "") ? err : "HTTP " status}
t := AiTrack({word: "bank", context: "", mode: "word"})
first := t.steps[1]
Check("gemini: starts with the first model", first.model, "model-a")
t.Got(first, Fail("0x80072EFD"), "")
Check("gemini: no connection - the same model once more", t.steps[1].model, "model-a")
CheckTrue("gemini: ...a moment later", t.steps[1].after > A_TickCount, "no pause")
CheckTrue("gemini: ...and the card says so", InStr(t.Waiting, "asked again"), t.Waiting)
t.Got(t.steps[1], Fail("0x80072EFD"), "")
Check("gemini: no connection twice - the next model", t.steps[1].model, "model-b")
CheckHas("gemini: ...and the card says so", t.Waiting, "model-a: no connection, trying model-b")
t.Got(t.steps[1], Fail("", 429), "")
CheckTrue("gemini: quota used up on the last model - done", t.done && t.note = "free quota used up for now", t.note)
CheckTrue("gemini: ...and that model rests for a minute", AiTrack.resting.Has("model-b"))
AiTrack.resting := Map()
t := AiTrack({word: "bank", context: "", mode: "word"})
t.Got(t.steps[1], Fail("", 503), "")
Check("gemini: an overloaded model rests too", Join(AiTrack.Models(), ","), "model-b,model-a")
AiTrack.resting["model-b"] := DateAdd(A_NowUTC, -1, "Seconds")
AiTrack.resting["model-a"] := DateAdd(A_NowUTC, -1, "Seconds")
Check("gemini: ...and is first again after its rest", Join(AiTrack.Models(), ","), "model-a,model-b")
AiTrack.resting := Map()
t := AiTrack({word: "bank", context: "", mode: "word"})
t.t0 := A_TickCount - 28000
t.Got(t.steps[1], Fail("", 503), "")
CheckTrue("gemini: out of time - stops and says so", t.done && InStr(t.note, "look up again"), t.note)
CheckHas("gemini: 2.5 models think a little", t.GenStep("gemini-2.5-flash").opts.body, '"thinkingBudget":512')
CheckHas("gemini: 3.x models think low", t.GenStep("gemini-3-flash").opts.body, '"thinkingLevel":"low"')

; how long a model rests: the 429 says which quota ran out
Check("gemini: quota day - summer, afternoon in California", AiTrack.NextQuotaDay("20260926200000"), "20260927070000")
Check("gemini: quota day - a second before it starts", AiTrack.NextQuotaDay("20260927065959"), "20260927070000")
Check("gemini: quota day - winter", AiTrack.NextQuotaDay("20260115100000"), "20260116080000")
Check("gemini: quota day - the night summer time ends", AiTrack.NextQuotaDay("20261101080000"), "20261102080000")
Check("gemini: quota day - the night summer time starts", AiTrack.NextQuotaDay("20260308060000"), "20260308080000")
Check("gemini: quota day - the day after", AiTrack.NextQuotaDay("20260308120000"), "20260309070000")
Quota(id, delay) => Fail("", 429).DefineProp("text", {value: '{"error": {"code": 429, "details": ['
    . '{"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [{"quotaId": "' id '"}]},'
    . '{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "' delay '"}]}}'})
day := Quota("GenerateRequestsPerDayPerProjectPerModel-FreeTier", "0s")
Check("gemini: out of the day's quota - rests until the quota day", AiTrack.RestUntil(day), AiTrack.NextQuotaDay())
secs := DateDiff(AiTrack.RestUntil(Quota("GenerateRequestsPerMinutePerProjectPerModel-FreeTier", "34s")), A_NowUTC, "Seconds")
CheckTrue("gemini: out of the minute's - as long as it says", secs >= 33 && secs <= 35, secs " s")
secs := DateDiff(AiTrack.RestUntil(Fail("", 503)), A_NowUTC, "Seconds")
CheckTrue("gemini: overloaded - a minute", secs >= 59 && secs <= 61, secs " s")

; the waiting line: nothing extra when all is normal; what happened when not
Check("gemini: model names, short", AiTrack.Short("gemini-3.8-flash") "|" AiTrack.Short("gemini-3.5-flash-lite")
    . "|" AiTrack.Short("gemini-flash-latest"), "3.8 Flash|3.5 Flash-Lite|Flash (latest)")
AiTrack.resting := Map()
t := AiTrack({word: "bank", context: "", mode: "word"})
Check("gemini: waiting, all normal", t.Waiting, "asking Gemini" Chr(0x2026))
back := AiTrack.LocalTime(AiTrack.NextQuotaDay())
CheckTrue("gemini: out of the day's quota - the card redraws", t.Got(t.steps[1], day, ""))
CheckHas("gemini: ...and says why the next model", t.Waiting
    , "model-a is out of today's free requests (until " back "), trying model-b")
t := AiTrack({word: "bank", context: "", mode: "word"})
CheckHas("gemini: the next lookup says why it skips one", t.Waiting
    , "model-b - model-a is out of today's free requests (until " back ")")
t.Got(t.steps[1], Fail("", 503), "")
CheckTrue("gemini: the last model left is busy - it says so", t.done && t.note = "model-b is busy for a minute", t.note)

; everything resting: only the first is asked, then it stops and says until when
AiTrack.resting := Map("model-a", AiTrack.NextQuotaDay(), "model-b", AiTrack.NextQuotaDay())
t := AiTrack({word: "bank", context: "", mode: "word"})
t.Got(t.steps[1], day, "")
CheckTrue("gemini: all out of quota - one try, not every model", t.done, "went on to " (t.steps.Length ? t.steps[1].model : "?"))
CheckHas("gemini: ...and says until when", t.note, "free quota used up until " AiTrack.LocalTime(AiTrack.NextQuotaDay()))

; kept across a restart: today's list and the rests; yesterday's list is not
AiTrack.SaveState()
AiTrack.chain := "", AiTrack.listed := "", AiTrack.resting := Map(), AiTrack.loaded := false
AiTrack.LoadState()
Check("gemini: a restart keeps today's list", Join(AiTrack.chain, ","), "model-a,model-b")
CheckTrue("gemini: ...and the rests", AiTrack.IsResting("model-a") && AiTrack.IsResting("model-b"))
FileDelete(AiTrack.StateFile)
FileAppend('{"models": ["old"], "listed": "' FormatTime(DateAdd(A_Now, -1, "Days"), "yyyyMMdd") '", "resting": {}}'
    , AiTrack.StateFile, "UTF-8-RAW")
AiTrack.chain := "", AiTrack.listed := "", AiTrack.loaded := false
AiTrack.LoadState()
Check("gemini: ...but yesterday's list is asked for again", AiTrack.chain, "")
try FileDelete(AiTrack.StateFile)
IniDelete(VocabIni(), "Gemini", "ApiKey")
AiTrack.chain := "", AiTrack.resting := Map(), AiTrack.listed := ""

;--- words.json: backups, and a file that cannot be read ------------------------
tmp := A_Temp "\vocab-store-test"
try DirDelete(tmp, true)
DirCreate(tmp)
Store.Path := tmp "\words.json", Store.BackupDir := tmp "\backups", Store.backedUp := ""
WordsFile(names*) {
    words := []
    for n in names
        words.Push(Map("word", n))
    return Json.Dump(Map("version", 1, "words", words))
}
FileAppend(WordsFile("apple", "bank"), Store.Path, "UTF-8-RAW")
Store.Load()
Check("store: reads the words", Store.words.Length, 2)
today := tmp "\backups\words-" FormatTime(, "yyyy-MM-dd") ".json"
Store.words.Push(Map("word", "cider"))
Store.Save()
Check("store: the day's first save backs up the file as it was", Store.Read(today).Length, 2)
Check("store: ...and saves the new one", Store.Read(Store.Path).Length, 3)
Store.words.Push(Map("word", "dune"))
Store.Save()
Check("store: later saves that day leave the backup alone", Store.Read(today).Length, 2)

; kept: the newest 10, and the oldest of each of the last 6 months
FileDelete(today)
days := ["2025-11-03", "2026-01-20", "2026-02-02", "2026-02-15", "2026-03-01", "2026-04-09", "2026-04-30"
    , "2026-05-05", "2026-06-10"]
loop 14
    days.Push(Format("2026-08-{:02}", A_Index * 2))
for d in days
    FileAppend(WordsFile("x"), tmp "\backups\words-" d ".json", "UTF-8-RAW")
Store.Prune()
Check("store: prune keeps 10 days and 6 months", Join(Store.Backups(), " ")
    , "words-2026-02-02.json words-2026-03-01.json words-2026-04-09.json words-2026-05-05.json words-2026-06-10.json"
    . " words-2026-08-02.json words-2026-08-10.json words-2026-08-12.json words-2026-08-14.json words-2026-08-16.json"
    . " words-2026-08-18.json words-2026-08-20.json words-2026-08-22.json words-2026-08-24.json words-2026-08-26.json"
    . " words-2026-08-28.json")

; an unreadable words.json is set aside and the newest backup that reads is loaded
FileAppend("not json", tmp "\backups\words-2026-08-30.json", "UTF-8-RAW")
FileAppend(WordsFile("from", "the", "backup"), tmp "\backups\words-2026-08-29.json", "UTF-8-RAW")
FileDelete(Store.Path)
FileAppend('{"version": 1, "words": [{"word": "cut off', Store.Path, "UTF-8-RAW")
Store.words := [], Store.backedUp := ""
Store.Load()
Check("store: unreadable - the newest good backup is loaded", Store.words.Length "," Store.words[1]["word"], "3,from")
Check("store: ...and written back as words.json", Store.Read(Store.Path) ? Store.Read(Store.Path).Length : 0, 3)
set := 0
loop files tmp "\words.unreadable-*.json"
    set++
Check("store: ...and the broken file kept aside", set, 1)
Store.Path := A_ScriptDir "\words.json", Store.BackupDir := A_ScriptDir "\backups", Store.words := []
try DirDelete(tmp, true)

;--- small helpers -------------------------------------------------------------
Check("clean word: quotes and comma", CleanWord(Chr(0x201C) "Hello," Chr(0x201D)), "Hello")
Check("clean word: possessive", CleanWord("harbour's"), "harbour")
Check("clean word: a footnote read as digits", CleanWord("abridged119"), "abridged")
Check("clean word: a footnote in brackets", CleanWord("abridged[119]"), "abridged")
Check("clean word: a short name keeps its digits", CleanWord("mp3") "," CleanWord("B12"), "mp3,B12")
Check("clean word: a phrase loses Markdown marks", CleanWord("__delaunay triangulation__"), "delaunay triangulation")
Check("clean word: a phrase keeps its inner punctuation", CleanWord("(de Casteljau's algorithm)"), "de Casteljau's algorithm")
Check("clean word: nothing but punctuation", CleanWord("..."), "")
CheckTrue("Gemini fix: a real correction", UsableFix("teaching", "eachin"))
CheckTrue("Gemini fix: same word is ignored", !UsableFix("Teaching", "teaching"))
CheckTrue("Gemini fix: a sentence is ignored", !UsableFix("this is not a word at all", "word"))

Done()
