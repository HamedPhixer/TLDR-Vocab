;================================================================================
; Install.ahk - updating to a new version, with one click
;================================================================================
; When Update.ahk finds a newer version, its notice (or Settings > "check
; now") opens a small window: what is new, and "update now" - or the
; download page, for anyone who would rather unzip it by hand.
;
; "update now", step by step. Nothing in the app's folder changes until
; step 7, and a failure anywhere before that only leaves a message.
;   1. the release's manifest.json: name, version, and the size and SHA-256
;      of both zips and of every file in them (build.ps1 writes it)
;   2. the zip this copy needs - portable if AutoHotkey64.exe is next to
;      Vocab.ahk, plain if not - into the temp folder
;   3. its size and SHA-256 checked against the manifest, and against the
;      digest GitHub itself keeps for the file
;   4. unpacked (Windows' own tar), in the temp folder
;   5. every file checked against the manifest again, one by one
;   6. the new Vocab.ahk loaded by AutoHotkey's syntax check, with the
;      AutoHotkey that will run it - a version that needs a newer AutoHotkey
;      stops here
;   7. Updater.ahk starts from a copy in the temp folder, TLDR Vocab closes,
;      and the helper swaps the files (Swap.ahk: backup first, undo on any
;      failure), starts the new version and waits for it to say it started
;      (Install.Started) - or puts the old one back.
;
; What it never does: touch Vocab.ini, words.json, cache\ or errors.log; ask
; for administrator; download from anywhere but this app's own GitHub
; releases (Install.Allowed); go back to an older version; update without
; being asked. A folder that is a git repository is left to git.
;
; What it trusts: GitHub, over HTTPS. The files are checked to be exactly the
; ones published, not that the person who published them is who they say -
; that would need a paid code-signing certificate (docs\decisions.md).
;================================================================================
#Requires AutoHotkey v2.0

class Install {
    static Root := A_Temp "\TLDR-Vocab-update"
    static Allowed := RepoUrl "/releases/download/"
    static g := "", notes := "", status := "", goLink := "", rel := "", busy := false
    static req := "", poller := "", step := "", dir := "", manAsset := "", zipAsset := "", kind := "", manifest := ""

    static Marker => Install.Root "\started.txt"
    static Portable() => FileExist(A_ScriptDir "\AutoHotkey64.exe") != ""

    ; Why this copy cannot update itself, or "" when it can
    static Blocker() {
        if FileExist(A_ScriptDir "\.git")
            return "This copy is a git repository - update it with git instead."
        probe := A_ScriptDir "\update-check.tmp"
        try {
            FileAppend("", probe)
            FileDelete(probe)
        } catch
            return "Windows does not let " AppName " change its own folder (" A_ScriptDir ")."
        return ""
    }

    ; the window: what is new, and the three ways on
    static Offer(rel) {
        if !IsObject(rel)
            return
        if (Install.busy && Install.g) {
            WinActivate(Install.g.Hwnd)
            return
        }
        Install.rel := rel
        if Install.g
            Install.Drop()
        g := Gui("-MaximizeBox -MinimizeBox -DPIScale", AppName " update")
        g.BackColor := CBg
        g.MarginX := 22, g.MarginY := 16
        g.SetFont("s12 Bold c" CText, FontUI)
        g.Add("Text", "x22 y16 w456 BackgroundTrans", AppName " " rel["version"] " is out")
        g.SetFont("s9 Norm c" CMuted, FontUI)
        g.Add("Text", "x22 y+2 w456 BackgroundTrans", "You have " VocabVersion ". What is new:")
        g.SetFont("s9 Norm c" CText, FontUI)
        Install.notes := g.Add("Edit", "x22 y+8 w456 h190 ReadOnly -E0x200 VScroll Background" CCard
            , Install.NotesText(rel.Has("notes") ? rel["notes"] : ""))
        g.SetFont("s8 Norm c" CDim, FontUI)
        g.Add("Text", "x22 y+10 w456 BackgroundTrans"
            , "Your words, settings and saved lookups are not touched. The version you have now is kept in the "
            . Chr(0x201C) Swap.BackupName Chr(0x201D) " folder, in case you want it back.")
        Install.status := g.Add("Text", "x22 y+10 w456 h34 BackgroundTrans", "")
        g.SetFont("s10 Bold c" CGreen, FontUI)
        Install.goLink := Link(g.Add("Text", "x22 y+4 BackgroundTrans", "Update now"), (*) => Install.Start())
        g.SetFont("s10 Norm c" CBlue, FontUI)
        Link(g.Add("Text", "x+28 yp BackgroundTrans", "Download page"), (*) => Run(rel["url"]))
        g.SetFont("s10 Norm c" CMuted, FontUI)
        Link(g.Add("Text", "x+28 yp BackgroundTrans", "Not now"), (*) => Install.Close())
        g.OnEvent("Close", (*) => Install.Close())
        g.OnEvent("Escape", (*) => Install.Close())
        Install.g := g
        DwmAttr(g.Hwnd, 20, 1)
        SetWindowIcon(g.Hwnd)
        g.Show("w500")
        SendMessage(0xB1, 0, 0, Install.notes)                  ; EM_SETSEL: no text selected
        if ((why := Install.Blocker()) != "") {
            Install.goLink.Visible := false
            Install.Say(why " The download page has the new version to unzip over this folder.", CAmber)
        }
    }

    static Close() {
        Install.Stop()
        Install.Drop()
    }

    static Drop() {
        if Install.g
            DropGui(Install.g)
        Install.g := ""
    }

    static Say(text, color := "") {
        if !Install.g
            return
        Install.status.SetFont("c" (color != "" ? color : CMuted))
        Install.status.Text := text
    }

    ; GitHub's notes are Markdown; the window shows them as plain text
    static NotesText(md) {
        t := StrReplace(StrReplace(md, "`r"), "**")
        t := RegExReplace(t, "\n[ \t]+(?![-*\s])", " ")         ; a wrapped line joins the one before
        t := RegExReplace(t, "m)^#+\s*(.*)$", "$U1")
        t := RegExReplace(t, "m)^(\s*)[-*] ", "$1" Chr(0x2022) " ")
        t := RegExReplace(t, "\[([^\]]+)\]\([^)]+\)", "$1")
        t := StrReplace(t, "``")
        t := Trim(t, "`n ")
        return StrReplace((t != "") ? t : "(no notes)", "`n", "`r`n")
    }

    ;--- the steps ------------------------------------------------------------

    static Start() {
        if Install.busy
            return
        if ((why := Install.Blocker()) != "")
            return Install.Say(why, CAmber)
        rel := Install.rel, v := rel["version"]
        if (Update.Compare(v, VocabVersion) <= 0)
            return Install.Say("That is not newer than " VocabVersion ".", CAmber)
        Install.kind := Install.Portable() ? "portable" : "plain"
        zipName := "TLDR-Vocab-" v (Install.kind = "portable" ? "-portable" : "") ".zip"
        Install.manAsset := Install.Asset(rel, "manifest.json")
        Install.zipAsset := Install.Asset(rel, zipName)
        if (!Install.manAsset || !Install.zipAsset)
            return Install.Fail("This version cannot be installed from here - please use the download page.")
        Install.busy := true
        Install.goLink.Visible := false
        Install.dir := Install.Root "\" v
        try {
            if DirExist(Install.dir)
                DirDelete(Install.dir, true)
            DirCreate(Install.dir)
        } catch as e
            return Install.Fail("Could not make a folder for the download (" e.Message ").")
        Install.Say("Downloading" Chr(0x2026))
        Install.Get(Install.manAsset["url"], "manifest", {timeout: 20000})
    }

    ; the release's file named name, as Map(url, size, digest) - only from
    ; this app's own releases, for this version
    static Asset(rel, name) {
        if !rel.Has("assets")
            return ""
        for a in rel["assets"]
            if (a["name"] = name) {
                want := Install.Allowed "v" rel["version"] "/" name
                return (a["url"] == want) ? a : ""
            }
        return ""
    }

    static Get(url, step, opts) {
        Install.step := step
        Install.req := Http(url, opts)
        if !Install.poller
            Install.poller := ObjBindMethod(Install, "Poll")
        SetTimer(Install.poller, 150)
    }

    static Stop() {
        if Install.poller
            SetTimer(Install.poller, 0)
        if (Install.req && Install.req.req)
            try Install.req.req.Abort()
        Install.req := "", Install.busy := false
    }

    static Poll() {
        if !Install.busy
            return SetTimer(Install.poller, 0)
        if !Install.req.Poll()
            return
        SetTimer(Install.poller, 0)
        r := Install.req, Install.req := ""
        if !r.Ok
            return Install.Fail("The download failed (" r.Why "). Nothing was changed.")
        try {
            if (Install.step = "manifest") {
                Install.manifest := Json.Parse(LTrim(r.text, Chr(0xFEFF)))
                if ((why := Install.CheckManifest(Install.manifest, Install.rel["version"], Install.kind)) != "")
                    return Install.Fail("The new version's file list is not right (" why "). Nothing was changed.")
                Install.Get(Install.zipAsset["url"], "zip", {raw: true, timeout: 300000})
            } else if (Install.step = "zip") {
                path := Install.dir "\update.zip"
                Http.Write(r.raw, path)
                Install.Finish(path)
            }
        } catch as e
            Install.Fail("Something went wrong (" e.Message "). Nothing was changed.")
    }


    ; steps 3 to 7
    static Finish(zipPath) {
        m := Install.manifest, want := m["zips"][Install.kind]
        Install.Say("Checking the download" Chr(0x2026))
        size := FileGetSize(zipPath), hash := Sha256File(zipPath)
        digest := Install.zipAsset.Has("digest") ? RegExReplace(Install.zipAsset["digest"], "i)^sha256:") : ""
        if (size != want["size"] || hash != want["sha256"] || (digest != "" && StrLower(digest) != hash))
            return Install.Fail("The download is not the file that was published (its check sum differs). Nothing was changed.")

        ; RunWait below lets the window's clicks through: "Not now" there
        ; clears busy, and the update stops at the next step
        Install.Say("Unpacking" Chr(0x2026))
        out := Install.dir "\new"
        ok := Install.Unzip(zipPath, out)
        if !Install.busy
            return
        if !ok
            return Install.Fail("The download could not be unpacked. Nothing was changed.")
        src := out "\TLDR Vocab"
        files := Install.Files(m, Install.kind)
        for f in files {
            p := src "\" StrReplace(f["path"], "/", "\")
            if (!FileExist(p) || FileGetSize(p) != f["size"] || Sha256File(p) != f["sha256"])
                return Install.Fail("An unpacked file is not what was published (" f["path"] "). Nothing was changed.")
        }

        Install.Say("Checking that the new version loads" Chr(0x2026))
        ahk := (Install.kind = "portable") ? src "\AutoHotkey64.exe" : A_AhkPath
        code := RunWait('"' ahk '" /Validate /ErrorStdOut "' src '\Vocab.ahk"', src, "Hide")
        if !Install.busy
            return
        if (code != 0)
            return Install.Fail("The new version does not load with this AutoHotkey (" A_AhkVersion
                . ") - it may need a newer one. Nothing was changed.")

        Install.Say("Closing and updating" Chr(0x2026))
        Install.g.Opt("+Disabled")                              ; past the point of "Not now"
        try Install.HandOver(src, files)
        catch as e {
            Install.g.Opt("-Disabled")
            return Install.Fail("Could not start the update (" e.Message "). Nothing was changed.")
        }
        ExitApp
    }

    ; the helper, its AutoHotkey and the plan into the temp folder, then start it
    static HandOver(src, files) {
        help := Install.dir "\helper"
        DirCreate(help)
        ; the UI Access edition only runs from Program Files; its plain twin
        ; sits beside it
        exe := A_AhkPath
        if (InStr(exe, "_UIA") && FileExist(StrReplace(exe, "_UIA")))
            exe := StrReplace(exe, "_UIA")
        FileCopy(exe, help "\AutoHotkey64.exe", 1)
        SplitPath(A_LineFile, , &lib)
        FileCopy(lib "\Updater.ahk", help "\Updater.ahk", 1)
        FileCopy(lib "\Swap.ahk", help "\Swap.ahk", 1)
        rels := []
        for f in files
            rels.Push(f["path"])
        plan := "app=" A_ScriptDir "`nsource=" src "`nrun=" A_AhkPath "`npid=" ProcessExist()
            . "`nfrom=" VocabVersion "`nto=" Install.rel["version"] "`npage=" Install.rel["url"]
            . "`nmarker=" Install.Marker "`nname=" AppName "`n"
        for rel in rels
            plan .= "file=" rel "`n"
        for rel in Swap.Leftovers(A_ScriptDir, rels)
            plan .= "remove=" rel "`n"
        try FileDelete(Install.dir "\plan.txt")
        FileAppend(plan, Install.dir "\plan.txt", "UTF-8")
        Run('"' help '\AutoHotkey64.exe" "' help '\Updater.ahk" "' Install.dir '\plan.txt"', help)
    }

    static Unzip(zip, out) {
        try DirCreate(out)
        try RunWait('tar.exe -xf "' zip '" -C "' out '"', out, "Hide")
        if FileExist(out "\TLDR Vocab\Vocab.ahk")
            return true
        try {                                   ; no tar (older Windows 10): the Explorer way
            sh := ComObject("Shell.Application")
            sh.NameSpace(out).CopyHere(sh.NameSpace(zip).Items(), 4 | 16 | 1024)
        }
        return FileExist(out "\TLDR Vocab\Vocab.ahk") != ""
    }

    static Fail(text) {
        Install.Stop()
        VocabLog("Update: " text)
        Install.Say(text, CRed)
        if Install.g
            Install.goLink.Visible := false
    }

    ;--- checks, kept apart so the tests can reach them -----------------------

    ; "" when the manifest is one this can install from, else what is wrong
    static CheckManifest(m, version, kind) {
        if !(m is Map)
            return "not a list"
        if (Dig(m, "name") != AppName)
            return "another app's"
        if (Dig(m, "version") != version)
            return "it is for " Dig(m, "version") ", not " version
        z := Dig(m, "zips", kind)
        if (!(z is Map) || !IsInteger(Dig(z, "size")) || !RegExMatch(Dig(z, "sha256"), "^[0-9a-f]{64}$"))
            return "no check sum for the " kind " zip"
        files := Install.Files(m, kind)
        if !files.Length
            return "no files"
        seen := Map()
        seen.CaseSense := false
        for f in files {
            p := Dig(f, "path")
            if (!Swap.SafeRel(p) || !IsInteger(Dig(f, "size")) || !RegExMatch(Dig(f, "sha256"), "^[0-9a-f]{64}$"))
                return "a file it may not write, or without a check sum: " p
            seen[StrReplace(p, "\", "/")] := true
        }
        for need in ["Vocab.ahk", "lib/All.ahk", "lib/Updater.ahk", "lib/Swap.ahk"]
            if !seen.Has(need)
                return "no " need
        if (kind = "portable" && !seen.Has("AutoHotkey64.exe"))
            return "no AutoHotkey64.exe"
        return ""
    }

    ; the files this copy gets: the app, plus AutoHotkey and its starter for
    ; a portable copy
    static Files(m, kind) {
        out := []
        for key in (kind = "portable") ? ["files", "portable"] : ["files"]
            if (Dig(m, key) is Array)
                for f in m[key]
                    out.Push(f)
        return out
    }

    ;--- after an update ------------------------------------------------------

    ; At start. Started with --updated-from=<old> by the helper: say so to
    ; the helper (the marker file) and to the user. The temp folder is
    ; cleared a few minutes later, when the helper is long gone.
    static Started() {
        for a in A_Args
            if RegExMatch(a, "^--updated-from=(.+)$", &m) {
                try FileAppend(VocabVersion, Install.Marker, "UTF-8")
                Notice(AppName " is now " VocabVersion " (was " m[1] "). Click to see what is new."
                    , AppName ": updated", () => Run(RepoUrl "/releases/tag/v" VocabVersion))
            }
        SetTimer(() => Install.Cleanup(), -180000)
    }

    static Cleanup() {
        if (DirExist(Install.Root) && !Install.busy)
            try DirDelete(Install.Root, true)
    }
}

; SHA-256 of a file, as 64 lowercase hex digits - Windows' own CNG
Sha256File(path) {
    f := FileOpen(path, "r")
    if !f
        throw Error("cannot read " path)
    f.Pos := 0                          ; FileOpen steps past a text file's BOM; the hash needs every byte
    data := Buffer(Max(f.Length, 1)), n := f.RawRead(data, f.Length)
    f.Close()
    alg := 0, h := 0, out := Buffer(32)
    if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &alg, "wstr", "SHA256", "ptr", 0, "uint", 0, "uint")
        throw Error("SHA-256 is not available")
    try {
        if DllCall("bcrypt\BCryptCreateHash", "ptr", alg, "ptr*", &h, "ptr", 0, "uint", 0, "ptr", 0, "uint", 0, "uint", 0, "uint")
            throw Error("SHA-256 failed")
        ok := !DllCall("bcrypt\BCryptHashData", "ptr", h, "ptr", data, "uint", n, "uint", 0, "uint")
            && !DllCall("bcrypt\BCryptFinishHash", "ptr", h, "ptr", out, "uint", 32, "uint", 0, "uint")
        DllCall("bcrypt\BCryptDestroyHash", "ptr", h)
        if !ok
            throw Error("SHA-256 failed")
    } finally
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", alg, "uint", 0)
    hex := ""
    loop 32
        hex .= Format("{:02x}", NumGet(out, A_Index - 1, "uchar"))
    return hex
}
