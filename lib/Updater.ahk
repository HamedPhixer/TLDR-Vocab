;================================================================================
; Updater.ahk - the helper that swaps the files while TLDR Vocab is closed
;================================================================================
; Not part of the app (All.ahk does not include it): Install.ahk copies it,
; with Swap.ahk and the AutoHotkey that runs it, into the temp folder and
; starts it there with the plan it wrote - so nothing it runs from is in the
; folder being updated, and nothing in that folder is in use.
;
;   1. waits for TLDR Vocab to close (it closes itself right after starting this)
;   2. Swap.Apply: backs up and replaces the files, or undoes it all
;   3. starts TLDR Vocab again - the new version - and waits for it to say it
;      started (Install.Started writes the marker file). If it quits instead,
;      or has not said so within a minute and a half, it is closed, the old
;      files go back, and the old version starts instead.
;   4. on any failure, a message says what happened and where the new
;      version can be downloaded by hand
;
; Every step goes into update.log next to the plan, and the outcome into the
; app's errors.log.
;================================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Include %A_LineFile%\..\Swap.ahk

global U_Plan := "", U_Log := ""

U_Main()

U_Main() {
    global U_Plan, U_Log
    if (A_Args.Length < 1 || !FileExist(A_Args[1]))
        ExitApp 2
    SplitPath(A_Args[1], , &dir)
    U_Log := dir "\update.log"
    U_Plan := p := U_Read(A_Args[1])
    U_Say("plan: " p.from " -> " p.to ", " p.files.Length " files, " p.remove.Length " to remove, app " p.app)

    wait := U_Window("Updating " p.name " to " p.to Chr(0x2026))
    if (p.pid && ProcessWaitClose(p.pid, 30)) {        ; its PID back = still running

        U_Say(p.name " did not close")
        wait.Destroy()
        U_Fail(p, p.name " did not close, so nothing was changed.", false)
    }

    about := p.name " " p.from " - the version before the update to " p.to
        . " on " FormatTime(, "yyyy-MM-dd HH:mm") ".`r`n`r`nTo go back to it: close " p.name
        . ", copy everything in this folder over the " p.name " folder, and start it again.`r`n"
    why := Swap.Apply(p.app, p.source, p.files, p.remove, about)
    if (why != "") {
        U_Say("swap failed: " why)
        wait.Destroy()
        U_Fail(p, "The new files could not be put in place (" why "), so " p.name " " p.from " was kept.", true)
    }
    U_Say("files replaced")

    try FileDelete(p.marker)
    try Run(U_Cmd(p, "--updated-from=" p.from), p.app)
    catch as e {
        U_Say("could not start the new version: " e.Message)
        U_Back(p, wait, "could not be started (" e.Message ")")
    }
    ; (when it will restart itself as administrator and this helper is not,
    ; that copy cannot be seen from here - then only the marker counts)
    blind := !A_IsAdmin && IniRead(p.app "\Vocab.ini", "General", "RunAsAdmin", 0) = 1
    gone := 0
    loop 90 {
        if FileExist(p.marker) {
            U_Say("the new version started")
            U_AppLog("Updated from " p.from " to " p.to)
            wait.Destroy()
            ExitApp 0
        }
        ; not running at all for a few seconds (not just restarting itself as
        ; administrator): it quit, and will not say it started
        gone := (!blind && A_Index > 5 && !U_AppPids(p).Length) ? gone + 1 : 0
        if (gone >= 3)
            break
        Sleep(1000)
    }
    U_Say("the new version did not start")
    U_Back(p, wait, "did not start")
}

; the new version failed to start: close whatever of it is running, put the
; old files back, start the old version
U_Back(p, wait, how) {
    U_CloseApp(p)
    moved := []                                 ; the old code files it had set aside
    for rel in p.remove
        if FileExist(p.app "\" Swap.BackupName "\" StrReplace(rel, "/", "\"))
            moved.Push(StrReplace(rel, "/", "\"))
    left := Swap.Undo(p.app, p.app "\" Swap.BackupName, U_Done(p), moved)
    U_Say("rolled back" (left != "" ? ", except: " left : ""))
    wait.Destroy()
    U_Fail(p, "The new version " how ", so " p.name " " p.from " was put back"
        . (left != "" ? " - except " left ", which the " Swap.BackupName " folder still has" : "") ".", true)
}

; what Swap.Undo needs to put the old files back: every file of the new
; version, and whether an old one was there (it is in the backup if so)
U_Done(p) {
    out := []
    for rel in p.files {
        rel := StrReplace(rel, "/", "\")
        out.Push({rel: rel, had: FileExist(p.app "\" Swap.BackupName "\" rel) != ""})
    }
    return out
}

U_Fail(p, text, restart) {
    U_AppLog("Update to " p.to " failed: " text)
    if restart
        try Run(U_Cmd(p, ""), p.app)
    MsgBox(text "`n`nYour words and settings were not touched. The new version can be downloaded by hand:`n"
        . p.page "`n`n(Details: " U_Log ")", p.name " update", "Icon! 0x40000")
    ExitApp 1
}

U_Cmd(p, arg) => '"' p.run '" "' p.app '\Vocab.ahk"' (arg != "" ? " " arg : "")

U_CloseApp(p) {
    for pid in U_AppPids(p)
        ProcessClose(pid)
    Sleep(1000)
}

; every AutoHotkey running this app's Vocab.ahk. The command line of one
; running as administrator can only be read by a helper that is too - which
; this one is, whenever the app was.
U_AppPids(p) {
    script := p.app "\Vocab.ahk", out := []
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'")
            if (proc.CommandLine != "" && InStr(proc.CommandLine, '"' script '"'))
                out.Push(proc.ProcessId)
    }
    return out
}

U_Read(path) {
    p := {files: [], remove: [], pid: 0, name: "TLDR Vocab"}
    loop read path, "UTF-8" {
        if !RegExMatch(A_LoopReadLine, "^(\w+)=(.*)$", &m)
            continue
        if (m[1] = "file")
            p.files.Push(m[2])
        else if (m[1] = "remove")
            p.remove.Push(m[2])
        else
            p.%m[1]% := m[2]
    }
    for need in ["app", "source", "run", "from", "to", "page", "marker"]
        if !p.HasProp(need) || p.%need% = ""
            ExitApp 3
    return p
}

U_Window(text) {
    g := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", "Updating")
    g.BackColor := "181B24"
    g.SetFont("s10 cEBEEF5", "Segoe UI")
    g.Add("Text", "x20 y16 w320", text)
    g.SetFont("s8 c8C94AA")
    g.Add("Text", "x20 y+6 w320", "It starts again by itself in a moment.")
    g.Show("w360 h76 NoActivate")
    return g
}

U_Say(msg) {
    global U_Log
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", U_Log, "UTF-8")
}

U_AppLog(msg) {
    global U_Plan
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", U_Plan.app "\errors.log", "UTF-8")
}
