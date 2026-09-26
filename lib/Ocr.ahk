;================================================================================
; Ocr.ahk - reading a piece of the screen, whichever engine does the reading
;================================================================================
; Everything in the app that reads the screen goes through here:
;
;   Ocr.Screen(x, y, w, h, scale)  a screen rectangle, enlarged by scale ->
;                                  Array of lines, each
;                                  {text, words: [{text, x, y, w, h}, ...]}
;                                  with boxes in the pixels of the rectangle
;                                  AS ENLARGED BY scale - always, even when
;                                  the engine could not take it that big
;   Ocr.MaxScale(w, h)             the most a w x h rectangle can be enlarged
;   Ocr.Engine                     the engine, for its measured settings:
;                                  WordPasses, BlockScale, BoxScales(h)
;   Ocr.Capture / Ocr.Read         the two halves of Screen, for tools\OcrDebug
;
; THE ENGINE is a class, named in Ocr.Engine below. Today that is WinOcr
; (OcrWindows.ahk), Windows' own. Another - Tesseract, PaddleOCR/RapidOCR, a
; cloud reader - is one more file with a class that has:
;
;   Name            what to call it in the log and in Settings
;   MaxDim          the largest width or height it reads, in pixels; 0 = any
;   Read(hBitmap)   -> lines as above, boxes in the bitmap's own pixels.
;                   English. [] when there is no text; throws an Error when it
;                   cannot read at all (the caller shows the message). It may
;                   take a while - a process, a request - but must wait with
;                   Sleep, never a busy loop, so the app's timers keep running.
;                   One that wants a file writes the bitmap out itself.
;                   One that only gives line boxes must still give word boxes
;                   (the line split by character count is good enough): the
;                   word under the pointer and Lines.ahk's page layout both
;                   work on words.
;   WordPasses      the bands the word lookup reads, in order: [{w, h, s}] -
;                   a w x h screen band around the pointer, enlarged by s
;   BlockScale      how much to enlarge a found block of text for Translate
;                   and Summary
;   BoxScales(h)    the scales to try on a drawn box h pixels tall, in order
;
; How much to enlarge belongs to the engine, not the app: each reader has its
; own sweet spot, and WinOcr's was measured (see its WordPasses). A new engine
; needs its own measuring - tests\Screen.test.ahk and tools\OcrDebug.ahk are
; the way to do it. Nothing else in the app knows which engine it is.
;================================================================================
#Requires AutoHotkey v2.0

class Ocr {
    static Engine := WinOcr

    ; What the rest of the app calls: read a screen rectangle, enlarged by
    ; scale, and hand back its lines.
    static Screen(x, y, w, h, scale := 1) {
        s := Min(scale, Ocr.MaxScale(w, h))
        hbm := Ocr.Capture(x, y, w, h, s)
        try lines := Ocr.Engine.Read(hbm)
        finally DllCall("DeleteObject", "ptr", hbm)
        if (s != scale)             ; read smaller than asked: boxes back to the size asked for
            Ocr.Rescale(lines, scale / s)
        return lines
    }

    static MaxScale(w, h) {
        m := Ocr.Engine.MaxDim
        return m ? m / Max(w, h, 1) : 1000
    }

    static Read(hBitmap) => Ocr.Engine.Read(hBitmap)

    ; screen rectangle -> HBITMAP, enlarged by scale. The caller deletes it.
    static Capture(x, y, w, h, scale := 1) {
        sw := Round(w * scale), sh := Round(h * scale)
        sdc := DllCall("GetDC", "ptr", 0, "ptr")
        mdc := DllCall("CreateCompatibleDC", "ptr", sdc, "ptr")
        hbm := DllCall("CreateCompatibleBitmap", "ptr", sdc, "int", sw, "int", sh, "ptr")
        old := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
        DllCall("SetStretchBltMode", "ptr", mdc, "int", 4)             ; HALFTONE - smooth, not blocky
        DllCall("SetBrushOrgEx", "ptr", mdc, "int", 0, "int", 0, "ptr", 0)
        DllCall("StretchBlt", "ptr", mdc, "int", 0, "int", 0, "int", sw, "int", sh
            , "ptr", sdc, "int", x, "int", y, "int", w, "int", h, "uint", 0x00CC0020)
        DllCall("SelectObject", "ptr", mdc, "ptr", old)
        DllCall("DeleteDC", "ptr", mdc)
        DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
        return hbm
    }

    static Rescale(lines, k) {
        for line in lines
            for w in line.words
                w.x *= k, w.y *= k, w.w *= k, w.h *= k
    }
}
