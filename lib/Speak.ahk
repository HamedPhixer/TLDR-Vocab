;================================================================================
; Speak.ahk - hear the word
;================================================================================
; Speak.Say("word") and that is all - called for each word looked up when
; Settings > SOUND "Say each word out loud" is on. What it does, in order:
;
;   1. cache\audio-us\<word>.mp3 a word heard once is instant and works offline
;   2. Google's speech endpoint  free, no key, the same family of addresses the
;                                translation already uses. A small mp3,
;                                kept in the cache for next time. American:
;                                plain "en" gets the British voice.
;   3. the Windows voice         SAPI, offline, always there. Flatter than a
;                                recording but never fails. Nothing is saved
;                                from it, so once Google answers again the word
;                                gets a real recording.
;
; ENGLISH ONLY. The same endpoint refuses Persian (every form of the request
; returns "malformed"), and Windows has no Persian voice unless one is
; installed, so translations are never spoken.
;
; Nothing blocks: the download is asynchronous like every other request here,
; and playback goes through MCI, which returns as soon as the sound starts.
; Asking for a second word stops the first.
;================================================================================
#Requires AutoHotkey v2.0

class Speak {
    static Dir := A_ScriptDir "\cache\audio-us"     ; American recordings only
    static job := "", voice := "", ticker := "", coolUntil := 0

    static Say(text) {
        text := Trim(text)
        if (text = "")
            return
        path := Speak.File(text)
        if FileExist(path) {
            Speak.Play(path)
            return
        }
        ; After a failed download - no network, or Google refusing this machine
        ; for a while - go straight to the Windows voice instead of making every
        ; click wait out the timeout again. One try is allowed through after the
        ; cool-off, so it heals by itself when the network comes back.
        if (A_TickCount < Speak.coolUntil) {
            Speak.Offline(text)
            return
        }
        Speak.Fetch(text, path)
    }

    static File(text) {
        name := RegExReplace(StrLower(text), "[^a-z0-9' -]", "_")
        return Speak.Dir "\" SubStr(name, 1, 60) ".mp3"
    }

    static Fetch(text, path) {
        Speak.job := {http: Http("https://translate.googleapis.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en-US&q="
            . Http.Enc(text), {timeout: 5000, raw: true}), path: path, text: text}
        if !Speak.ticker
            Speak.ticker := ObjBindMethod(Speak, "Tick")
        SetTimer(Speak.ticker, 60)
    }

    static Tick() {
        j := Speak.job
        if !j {
            SetTimer(Speak.ticker, 0)
            return
        }
        if !j.http.Poll()
            return
        SetTimer(Speak.ticker, 0)
        Speak.job := ""
        saved := false
        if (j.http.Ok && j.http.raw) {
            try {
                DirCreate(Speak.Dir)
                Http.Write(j.http.raw, j.path)
                saved := FileExist(j.path) && FileGetSize(j.path) > 500
            }
        }
        if saved {
            Speak.coolUntil := 0
            Speak.Play(j.path)
        } else {
            try FileDelete(j.path)          ; never leave half a file behind
            Speak.coolUntil := A_TickCount + 300000         ; five minutes
            VocabLog("audio for " j.text ": " j.http.Why " - using the Windows voice")
            Speak.Offline(j.text)
        }
    }

    ; SVSFlagsAsync | SVSFPurgeBeforeSpeak: returns at once, and a new word
    ; replaces one still being spoken
    static Offline(text) {
        try {
            if !Speak.voice
                Speak.voice := ComObject("SAPI.SpVoice")
            Speak.voice.Speak(text, 0x1 | 0x2)
        } catch as e
            VocabLog("Windows voice: " e.Message)
    }

    static Play(path) {
        Speak.Mci("close VocabSnd")
        if (Speak.Mci('open "' path '" type mpegvideo alias VocabSnd') = 0)
            Speak.Mci("play VocabSnd")
        else
            try FileDelete(path)            ; unplayable: fetch it again next time
    }

    static Stop() {
        Speak.Mci("close VocabSnd")
        if Speak.voice
            try Speak.voice.Speak("", 0x1 | 0x2)
    }

    static Mci(cmd) => DllCall("winmm\mciSendString", "str", cmd, "ptr", 0, "uint", 0, "ptr", 0, "uint")
}
