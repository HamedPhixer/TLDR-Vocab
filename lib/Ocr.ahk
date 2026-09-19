;================================================================================
; Ocr.ahk - Windows' built-in OCR (Windows.Media.Ocr), no download, no key
;================================================================================
; Ocr.Screen(x, y, w, h, scale)    screen rectangle -> Array of lines (below),
;                                  in one call - what the app uses
; Ocr.Capture(x, y, w, h, scale)   screen rectangle -> HBITMAP, enlarged by
;                                  `scale`. Small text reads far better at 2-3x.
;                                  The caller deletes the bitmap.
; Ocr.Read(hBitmap)                -> Array of lines, each
;                                  {text, words: [{text, x, y, w, h}, ...]}
;                                  with boxes in the bitmap's own pixels.
;
; The engine is asked for English by name. TryCreateFromUserProfileLanguages
; would take the FIRST language in the Windows list, and if that were Persian
; it would read English text as garbage. English OCR ships with every English
; Windows; the user-profile engine is only the fallback.
;
; This talks WinRT through raw vtables. The numbers passed to ComCall are
; method slots; each is labelled with the method it calls.
;
; Async calls are waited out by polling IAsyncInfo.Status - a few tens of ms
; for a subtitle-sized region, so it is not worth a callback.
;================================================================================
#Requires AutoHotkey v2.0

class Ocr {
    static engine := 0, decoders := 0, maxDim := 0, lang := ""

    static Init() {
        if this.engine
            return
        statics := Ocr._Factory("Windows.Media.Ocr.OcrEngine", "{5BFFA85A-3384-3540-9940-699120D428A8}")
        ComCall(6, statics, "uint*", &maxDim := 0)                      ; get_MaxImageDimension
        this.maxDim := maxDim
        langs := Ocr._Factory("Windows.Globalization.Language", "{9B0252AC-0C27-44F8-B792-9793FB66C63E}")
        engine := 0
        for tag in ["en-US", "en-GB", "en"] {
            hs := Ocr._HStr(tag)
            try {
                ComCall(6, langs, "ptr", hs, "ptr*", &lang := 0)        ; CreateLanguage
                ComCall(9, statics, "ptr", lang, "ptr*", &engine)       ; TryCreateFromLanguage
                ObjRelease(lang)
            }
            DllCall("combase\WindowsDeleteString", "ptr", hs)
            if engine {
                this.lang := tag
                break
            }
        }
        if !engine {
            ComCall(10, statics, "ptr*", &engine)                       ; TryCreateFromUserProfileLanguages
            this.lang := "user profile"
        }
        if !engine
            throw Error("Windows has no OCR language installed")
        this.engine := engine
        this.decoders := Ocr._Factory("Windows.Graphics.Imaging.BitmapDecoder", "{438CCB26-BCEF-4E95-BAD6-23A822E58D01}")
    }

    ; What the rest of the app calls: read a screen rectangle, enlarged by
    ; scale, and hand back its lines. Word boxes are in the enlarged pixels.
    static Screen(x, y, w, h, scale := 1) {
        hbm := Ocr.Capture(x, y, w, h, scale)
        try return Ocr.Read(hbm)
        finally DllCall("DeleteObject", "ptr", hbm)
    }

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

    static Read(hBitmap) {
        Ocr.Init()
        stream := Ocr._Stream(hBitmap)
        try {
            ComCall(14, this.decoders, "ptr", stream, "ptr*", &op := 0) ; BitmapDecoder.CreateAsync
            decoder := Ocr._Await(op)
            frame := ComObjQuery(decoder, "{FE287C9A-420C-4963-87AD-691436E08383}")  ; IBitmapFrameWithSoftwareBitmap
            ComCall(6, frame, "ptr*", &op := 0)                         ; GetSoftwareBitmapAsync
            frame := ""
            bmp := Ocr._Await(op)
            ComCall(6, this.engine, "ptr", bmp, "ptr*", &op := 0)      ; RecognizeAsync
            result := Ocr._Await(op)
        } finally
            ObjRelease(stream)
        out := []
        ComCall(6, result, "ptr*", &lines := 0)                         ; get_Lines
        ComCall(7, lines, "uint*", &n := 0)                             ; IVectorView.Size
        rect := Buffer(16)
        loop n {
            ComCall(6, lines, "uint", A_Index - 1, "ptr*", &line := 0)  ; GetAt
            ComCall(7, line, "ptr*", &hs := 0)                          ; IOcrLine.get_Text
            ltext := Ocr._Str(hs)
            ComCall(6, line, "ptr*", &words := 0)                       ; IOcrLine.get_Words
            ComCall(7, words, "uint*", &wn := 0)
            ws := []
            loop wn {
                ComCall(6, words, "uint", A_Index - 1, "ptr*", &word := 0)
                ComCall(6, word, "ptr", rect)                           ; IOcrWord.get_BoundingRect
                ComCall(7, word, "ptr*", &hs := 0)                      ; IOcrWord.get_Text
                ws.Push({text: Ocr._Str(hs)
                    , x: NumGet(rect, 0, "float"), y: NumGet(rect, 4, "float")
                    , w: NumGet(rect, 8, "float"), h: NumGet(rect, 12, "float")})
                ObjRelease(word)
            }
            ObjRelease(words), ObjRelease(line)
            out.Push({text: ltext, words: ws})
        }
        ObjRelease(lines), ObjRelease(result), ObjRelease(bmp), ObjRelease(decoder)
        return out
    }

    ; HBITMAP -> BMP bytes in memory -> IRandomAccessStream for BitmapDecoder
    static _Stream(hBitmap) {
        DllCall("ole32\CreateStreamOnHGlobal", "ptr", 0, "int", true, "ptr*", &istream := 0, "HRESULT")
        pd := Buffer(8 + 2 * A_PtrSize, 0)                              ; PICTDESC
        NumPut("uint", pd.Size, pd, 0), NumPut("uint", 1, pd, 4)        ; PICTYPE_BITMAP
        NumPut("ptr", hBitmap, pd, 8)
        DllCall("oleaut32\OleCreatePictureIndirect", "ptr", pd
            , "ptr", Ocr._Guid("{7BF80980-BF32-101A-8BBB-00AA00300CAB}"), "int", false, "ptr*", &pic := 0, "HRESULT")
        ComCall(15, pic, "ptr", istream, "int", true, "int*", &size := 0)  ; IPicture.SaveAsFile
        DllCall("shcore\CreateRandomAccessStreamOverStream", "ptr", istream, "uint", 0
            , "ptr", Ocr._Guid("{905A0FE1-BC53-11DF-8C49-001E4FC686DA}"), "ptr*", &ras := 0, "HRESULT")
        ObjRelease(pic), ObjRelease(istream)
        return ras
    }

    ; Waits out an IAsyncOperation, releases it, returns its result
    static _Await(op) {
        info := ComObjQuery(op, "{00000036-0000-0000-C000-000000000046}")   ; IAsyncInfo
        t0 := A_TickCount
        loop {
            ComCall(7, info, "uint*", &status := 0)                     ; get_Status
            if status
                break
            if (A_TickCount - t0 > 5000)
                throw Error("OCR timed out")
            Sleep 5
        }
        if (status != 1) {                                              ; 1 = Completed
            ComCall(8, info, "int*", &hr := 0)                          ; get_ErrorCode
            throw Error(Format("OCR failed (status {}, 0x{:08X})", status, hr & 0xFFFFFFFF))
        }
        info := ""
        ComCall(8, op, "ptr*", &res := 0)                               ; GetResults
        ObjRelease(op)
        return res
    }

    static _Factory(cls, iid) {
        hs := Ocr._HStr(cls)
        try DllCall("combase\RoGetActivationFactory", "ptr", hs, "ptr", Ocr._Guid(iid), "ptr*", &f := 0, "HRESULT")
        finally DllCall("combase\WindowsDeleteString", "ptr", hs)
        return f
    }

    static _HStr(s) {
        DllCall("combase\WindowsCreateString", "wstr", s, "uint", StrLen(s), "ptr*", &hs := 0, "HRESULT")
        return hs
    }

    static _Str(hs) {
        p := DllCall("combase\WindowsGetStringRawBuffer", "ptr", hs, "uint*", &len := 0, "ptr")
        s := StrGet(p, len, "UTF-16")
        DllCall("combase\WindowsDeleteString", "ptr", hs)
        return s
    }

    static _Guid(s) {
        buf := Buffer(16)
        DllCall("ole32\CLSIDFromString", "wstr", s, "ptr", buf, "HRESULT")
        return buf
    }
}
