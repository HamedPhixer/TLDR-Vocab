#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#Include %A_LineFile%\..\..\lib\Ocr.ahk
;================================================================================
; OcrDebug.ahk - what Vocab actually sees when you press its hotkey
;================================================================================
; Point at the word that misreads and press  Ctrl + Alt + D.
; It captures exactly what Vocab captures - the same two passes - and writes
; into this script's folder:
;   shot-<n>-pass1.bmp   the 800x160 strip around the pointer, enlarged 2x
;   shot-<n>-pass2.bmp   the tighter 480x90 strip at 3x, which Vocab only uses
;                        when the first pass finds nothing
;   ocrdebug.txt         every word each pass found, with its box, and which
;                        word would have been picked
; Nothing is changed in Vocab, and nothing is sent anywhere.
; Ctrl + Alt + Q quits.
;================================================================================
Shots := 0
LogFile := A_ScriptDir "\ocrdebug.txt"
CoordMode("Mouse", "Screen")
TrayTip("Point at the word and press Ctrl+Alt+D", "OcrDebug", 1)

^!d:: Capture()
^!q:: ExitApp

Capture() {
    global Shots
    Shots += 1
    MouseGetPos(&mx, &my)
    Put("=========== shot " Shots "   pointer at " mx "," my "   " FormatTime(, "HH:mm:ss"))
    for i, pass in [{w: 800, h: 160, s: 2}, {w: 480, h: 90, s: 3}] {
        rx := mx - pass.w // 2, ry := my - pass.h // 2
        hbm := Ocr.Capture(rx, ry, pass.w, pass.h, pass.s)
        SaveBmp(hbm, A_ScriptDir "\shot-" Shots "-pass" i ".bmp")
        lines := Ocr.Read(hbm)
        DllCall("DeleteObject", "ptr", hbm)
        px := (mx - rx) * pass.s, py := (my - ry) * pass.s
        Put("  pass " i ": " pass.w "x" pass.h " at " pass.s "x   pointer inside the strip at " px "," py)
        best := "", bestD := 1e9, cut := ""
        for row in lines {
            Put("    line [" row.text "]")
            for w in row.words {
                edge := (w.x <= 2 || w.x + w.w >= pass.w * pass.s - 2) ? "  <-- TOUCHES THE EDGE, may be cut" : ""
                Put("       " w.text "  at " Round(w.x) "," Round(w.y) "  " Round(w.w) "x" Round(w.h) edge)
                dx := (px < w.x) ? w.x - px : (px > w.x + w.w) ? px - w.x - w.w : 0
                dy := (py < w.y) ? w.y - py : (py > w.y + w.h) ? py - w.y - w.h : 0
                d := Sqrt(dx * dx + dy * dy)
                if (d < bestD && d <= Max(w.h * 0.6, 10))
                    bestD := d, best := w.text, cut := edge
            }
        }
        Put("    -> would pick: [" (best = "" ? "NOTHING, so Vocab falls through to the next pass" : best) "]"
            . (cut ? "   and that word touches the edge" : ""))
    }
    TrayTip("Saved shot " Shots, "OcrDebug", 1)
}

Put(msg) => FileAppend(msg "`n", LogFile, "UTF-8")

; The same IPicture trick Ocr.ahk uses to hand a bitmap to Windows, but
; written to a file so the strip can be looked at afterwards.
SaveBmp(hBitmap, path) {
    DllCall("ole32\CreateStreamOnHGlobal", "ptr", 0, "int", true, "ptr*", &stream := 0, "HRESULT")
    pd := Buffer(8 + 2 * A_PtrSize, 0)
    NumPut("uint", pd.Size, pd, 0), NumPut("uint", 1, pd, 4)
    NumPut("ptr", hBitmap, pd, 8)
    iid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", "{7BF80980-BF32-101A-8BBB-00AA00300CAB}", "ptr", iid, "HRESULT")
    DllCall("oleaut32\OleCreatePictureIndirect", "ptr", pd, "ptr", iid, "int", false, "ptr*", &pic := 0, "HRESULT")
    ComCall(15, pic, "ptr", stream, "int", true, "int*", &size := 0)     ; IPicture.SaveAsFile
    DllCall("ole32\GetHGlobalFromStream", "ptr", stream, "ptr*", &hg := 0, "HRESULT")
    ptr := DllCall("GlobalLock", "ptr", hg, "ptr")
    try FileDelete(path)
    f := FileOpen(path, "w")
    f.RawWrite(ptr, size)
    f.Close()
    DllCall("GlobalUnlock", "ptr", hg)
    ObjRelease(pic), ObjRelease(stream)
}
