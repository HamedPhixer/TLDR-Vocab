;================================================================================
; Update.ahk - is there a newer version?
;================================================================================
; Once a day, a few seconds after start, the releases on GitHub are asked for
; (one small request to its public API, no account, through the same proxy
; setting as every lookup). If one is newer than VocabVersion, a tray notice
; says so, and clicking it opens that release's page to download it. Nothing
; is downloaded or changed here - updating is still unzipping the new version
; over the old folder.
;
; Which releases count: a test version (a version with a dash, 1.1.0-beta.2)
; only for someone already running one. Everyone else hears about finished
; versions only - the same rule GitHub's "latest release" link follows.
;
; Settings > GENERAL switches the daily check off ([General] CheckUpdates=0)
; and has "check now"; so does the tray menu. A check by hand always answers,
; "up to date" included; the daily one only speaks when there is news, and
; says nothing at all when GitHub cannot be reached.
;================================================================================
#Requires AutoHotkey v2.0

class Update {
    static req := "", poller := "", manual := false, onDone := ""

    ; at start: once a day, unless switched off
    static Daily() {
        ini := VocabIni()
        if (IniRead(ini, "General", "CheckUpdates", 1) != 1)
            return
        today := FormatTime(, "yyyyMMdd")
        if (IniRead(ini, "General", "LastUpdateCheck", "") = today)
            return
        try IniWrite(today, ini, "General", "LastUpdateCheck")
        Update.Check(false)
    }

    ; manual: asked for by hand - always answers. onDone(text, found) gets the
    ; answer as well, for the settings window's own line.
    static Check(manual := true, onDone := "") {
        if Update.req                           ; one check at a time
            return
        Update.manual := manual, Update.onDone := onDone
        Update.req := Http("https://api.github.com/repos/" RegExReplace(RepoUrl, "^https://github\.com/") "/releases?per_page=20"
            , {timeout: 10000, headers: Map("Accept", "application/vnd.github+json")})
        if !Update.poller
            Update.poller := ObjBindMethod(Update, "Poll")
        SetTimer(Update.poller, 200)
    }

    static Poll() {
        if !Update.req.Poll()
            return
        SetTimer(Update.poller, 0)
        r := Update.req, Update.req := ""
        news := ""
        if r.Ok
            try news := Update.Newest(Json.Parse(r.text), VocabVersion)
        if (!r.Ok || news = "") {
            ok := r.Ok && news = ""
            text := ok ? "You have the newest version, " VocabVersion "."
                       : "Could not reach GitHub (" r.Why ")."
            if !ok
                VocabLog("Update check: " r.Why)
            if Update.manual
                Notice(text, AppName)
            Update.Tell(text, false)
            return
        }
        v := news["version"], url := news["url"]
        Notice(AppName " " v " is out - you have " VocabVersion ". Click to open the download page."
            , AppName ": a new version", () => Run(url))
        Update.Tell(AppName " " v " is out.", true, url)
    }

    static Tell(text, found, url := "") {
        if Update.onDone
            Update.onDone.Call(text, found, url)
    }

    ; The newest release in list (GitHub's answer) that is newer than mine, as
    ; Map(version, url), or "" when there is none. Drafts never count; test
    ; versions count only when mine is one.
    static Newest(list, mine) {
        pre := InStr(mine, "-") > 0
        best := ""
        for rel in list {
            if Dig(rel, "draft")
                continue
            v := RegExReplace(Dig(rel, "tag_name"), "^v")
            if (v = "" || (Dig(rel, "prerelease") && !pre))
                continue
            if (Update.Compare(v, mine) > 0 && (!best || Update.Compare(v, best["version"]) > 0))
                best := Map("version", v, "url", Dig(rel, "html_url"))
        }
        return best
    }

    ; -1, 0 or 1, the way versions are ordered: 1.2.0 before 1.10.0, and a test
    ; version before the finished one it leads to - 1.1.0-beta.2 < 1.1.0 - with
    ; test versions in order by their number: beta.2 < beta.10.
    static Compare(a, b) {
        pa := StrSplit(a, "-", , 2), pb := StrSplit(b, "-", , 2)
        na := StrSplit(pa[1], "."), nb := StrSplit(pb[1], ".")
        loop Max(na.Length, nb.Length) {
            x := (A_Index <= na.Length && IsInteger(na[A_Index])) ? Integer(na[A_Index]) : 0
            y := (A_Index <= nb.Length && IsInteger(nb[A_Index])) ? Integer(nb[A_Index]) : 0
            if (x != y)
                return (x > y) ? 1 : -1
        }
        ta := (pa.Length > 1) ? pa[2] : "", tb := (pb.Length > 1) ? pb[2] : ""
        if (ta = tb)
            return 0
        if (ta = "" || tb = "")                 ; the finished version comes after its tests
            return (ta = "") ? 1 : -1
        xa := StrSplit(ta, "."), xb := StrSplit(tb, ".")
        loop Max(xa.Length, xb.Length) {
            if (A_Index > xa.Length)
                return -1
            if (A_Index > xb.Length)
                return 1
            s := xa[A_Index], t := xb[A_Index]
            if (IsInteger(s) && IsInteger(t)) {
                if (Integer(s) != Integer(t))
                    return (Integer(s) > Integer(t)) ? 1 : -1
            } else if (s != t)
                return (StrCompare(s, t) > 0) ? 1 : -1
        }
        return 0
    }
}
