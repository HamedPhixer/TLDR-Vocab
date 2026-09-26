;================================================================================
; Swap.ahk - putting a new version's files in place, or none of them
;================================================================================
; Used by Updater.ahk, the small helper that runs while TLDR Vocab itself is
; closed (Install.ahk explains the whole update). It needs nothing else from
; lib\, so the helper can run from a copy of itself in the temp folder.
;
; Swap.Apply(app, source, files, remove)
;   files   the new version's files, as paths relative to its folder
;           ("lib/Popup.ahk"). Each is copied from source over app - after the
;           file it replaces has been copied into app\previous version\.
;   remove  old code files the new version no longer has (only lib\*.ahk);
;           they are moved into previous version\ too.
;   If any step fails, everything done so far is undone - the old files come
;   back from previous version\, new ones are deleted - and the reason is
;   returned. "" = done.
;
; What is never touched, whatever a list says: Vocab.ini, words.json, backups\,
; cache\, errors.log - your settings, your words, what was looked up - and anything
; outside the app's folder. Swap.SafeRel turns such a path down, and the whole
; update with it.
;
; previous version\ holds the version before the latest update, with a note
; saying which one it was; each update replaces it. Copying its files back
; over the folder is the way back.
;================================================================================
#Requires AutoHotkey v2.0

class Swap {
    static BackupName := "previous version"

    ; true for a path that may be written: relative, inside the folder, and not
    ; one of the user's own files
    static SafeRel(rel) {
        rel := StrReplace(rel, "/", "\")
        if (rel = "" || RegExMatch(rel, "[:*?`"<>|]") || RegExMatch(rel, "^[\\.]"))
            return false
        for part in StrSplit(rel, "\")
            if (part = "" || part = "." || part = ".." || RegExMatch(part, "[. ]$"))
                return false
        first := StrSplit(rel, "\")[1]
        for mine in ["Vocab.ini", "words.json", "errors.log", "cache", "backups", Swap.BackupName, ".git"]
            if (first = mine)
                return false
        return !RegExMatch(rel, "i)^words\.unreadable-")
    }

    static Apply(app, source, files, remove, about := "") {
        bak := app "\" Swap.BackupName
        for rel in files
            if !Swap.SafeRel(rel)
                return "the new version names a file it may not write: " rel
        for rel in remove
            if (!Swap.SafeRel(rel) || !RegExMatch(StrReplace(rel, "/", "\"), "i)^lib\\[^\\]+\.ahk$"))
                return "the new version would remove a file it may not: " rel
        for rel in files
            if !FileExist(source "\" rel)
                return "the download is missing " rel

        try {
            if DirExist(bak)
                DirDelete(bak, true)
            DirCreate(bak)
        } catch as e
            return "could not make the " Swap.BackupName " folder (" e.Message ")"

        ; (a for-loop's own variable is not seen inside a () => closure, so
        ; each path is copied into rel first)
        done := [], moved := []
        try {
            for item in remove {
                rel := StrReplace(item, "/", "\")
                if !FileExist(app "\" rel)
                    continue
                Swap.Parent(bak "\" rel)
                Swap.Retry(() => FileMove(app "\" rel, bak "\" rel, 1))
                moved.Push(rel)
            }
            for item in files {
                rel := StrReplace(item, "/", "\")
                target := app "\" rel
                had := FileExist(target) != ""
                if had {
                    Swap.Parent(bak "\" rel)
                    Swap.Retry(() => FileCopy(target, bak "\" rel, 1))
                }
                done.Push({rel: rel, had: had})     ; from here on, undo knows about it
                Swap.Parent(target)
                Swap.Retry(() => FileCopy(source "\" rel, target, 1))
                if (FileGetSize(target) != FileGetSize(source "\" rel))
                    throw Error("the copy of " rel " came out a different size")
            }
        } catch as e {
            left := Swap.Undo(app, bak, done, moved)
            why := (e.Message != "") ? e.Message : "a file could not be replaced"
            return why ((left != "") ? " - and putting the old files back failed too (" left
                . "); they are all in the " Swap.BackupName " folder" : "")
        }
        try FileAppend(about, bak "\about this folder.txt", "UTF-8")
        return ""
    }

    ; back to how it was: old files copied back, new ones deleted, removed ones
    ; moved back. Returns what could not be undone, or "".
    static Undo(app, bak, done, moved) {
        left := []
        i := done.Length
        while (i >= 1) {
            d := done[i--]
            try {
                if d.had
                    Swap.Retry(() => FileCopy(bak "\" d.rel, app "\" d.rel, 1))
                else if FileExist(app "\" d.rel)
                    Swap.Retry(() => FileDelete(app "\" d.rel))
            } catch
                left.Push(d.rel)
        }
        for item in moved {
            rel := item
            try Swap.Retry(() => FileMove(bak "\" rel, app "\" rel, 1))
            catch
                left.Push(rel)
        }
        out := ""
        for rel in left
            out .= (out = "" ? "" : ", ") rel
        return out
    }

    ; the new version's lib\*.ahk list against what the folder has: the old
    ; code files it no longer has
    static Leftovers(app, files) {
        keep := Map()
        keep.CaseSense := false
        for rel in files
            keep[StrReplace(rel, "/", "\")] := true
        out := []
        loop files app "\lib\*.ahk"
            if !keep.Has("lib\" A_LoopFileName)
                out.Push("lib\" A_LoopFileName)
        return out
    }

    static Parent(path) {
        SplitPath(path, , &dir)
        if !DirExist(dir)
            DirCreate(dir)
    }

    ; a virus scanner or OneDrive can hold a file for a moment
    static Retry(fn, tries := 6) {
        loop tries {
            try {
                fn()
                return
            } catch as e {
                if (A_Index = tries)
                    throw e
                Sleep(500)
            }
        }
    }
}
