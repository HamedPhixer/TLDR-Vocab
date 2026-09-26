;================================================================================
; OcrWindows.ahk - WinOcr, the engine Ocr.ahk uses: Windows' built-in OCR
; (Windows.Media.Ocr) - no download, no key
;================================================================================
; What Ocr.ahk asks of an engine (its header has the whole contract):
;   WinOcr.Read(hBitmap)   -> Array of lines, each
;                          {text, words: [{text, x, y, w, h}, ...]}
;                          with boxes in the bitmap's own pixels
;   WinOcr.MaxDim          the largest width or height it reads, in pixels
;   WinOcr.WordPasses, WinOcr.BlockScale, WinOcr.BoxScales(h)
;                          how much to enlarge - measured for this engine
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

class WinOcr {
    static Name := "Windows OCR"
    static engine := 0, decoders := 0, dim := 0, lang := ""

    ; HOW MUCH TO ENLARGE, AND WHY IT MATTERS
    ; Windows' reader has a sweet spot. Enlarging helps small text and ruins
    ; big text: a 100 px subtitle doubled comes out over 200 px tall and reads
    ; as nothing at all, or - worse - as pieces of itself ("plu", "lung",
    ; "e"). So the word lookup's fallbacks zoom OUT before they zoom in:
    ;
    ;   1.5x on a wide band    ordinary text and subtitles, measured good from
    ;                          8 px UI labels up to 100 px subtitles
    ;   1x on a taller band    text bigger still, and a second opinion
    ;   3x on a small band     genuinely tiny print, last because zooming in is
    ;                          what breaks large text
    ;
    ; Measured on rendered text at 8, 12, 14, 37, 66 and 103 px: the first band
    ; alone reads every one of them, from any pointer position on the word.
    ; A band is w x h screen pixels centred on the pointer, read at s.
    static WordPasses := [{w: 800, h: 220, s: 1.5}, {w: 900, h: 300, s: 1}, {w: 480, h: 90, s: 3}]

    ; Translate and Summary read a found block of text again at this, for the
    ; words themselves - what reads ordinary text best (see above)
    static BlockScale := 1.5

    ; A drawn box, by its height: one drawn around a single line is only a
    ; little taller than its text. Tried in order; the first that reads
    ; anything is used.
    static BoxScales(h) => (h < 60) ? [2, 3, 1] : (h < 200) ? [1.5, 1, 2.5] : [1, 1.5]

    static MaxDim => (WinOcr.Init(), WinOcr.dim)

    static Init() {
        if this.engine
            return
        statics := WinOcr._Factory("Windows.Media.Ocr.OcrEngine", "{5BFFA85A-3384-3540-9940-699120D428A8}")
        ComCall(6, statics, "uint*", &maxDim := 0)                      ; get_MaxImageDimension
        this.dim := maxDim
        langs := WinOcr._Factory("Windows.Globalization.Language", "{9B0252AC-0C27-44F8-B792-9793FB66C63E}")
        engine := 0
        for tag in ["en-US", "en-GB", "en"] {
            hs := WinOcr._HStr(tag)
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
        this.decoders := WinOcr._Factory("Windows.Graphics.Imaging.BitmapDecoder", "{438CCB26-BCEF-4E95-BAD6-23A822E58D01}")
    }

    static Read(hBitmap) {
        WinOcr.Init()
        stream := WinOcr._Stream(hBitmap)
        try {
            ComCall(14, this.decoders, "ptr", stream, "ptr*", &op := 0) ; BitmapDecoder.CreateAsync
            decoder := WinOcr._Await(op)
            frame := ComObjQuery(decoder, "{FE287C9A-420C-4963-87AD-691436E08383}")  ; IBitmapFrameWithSoftwareBitmap
            ComCall(6, frame, "ptr*", &op := 0)                         ; GetSoftwareBitmapAsync
            frame := ""
            bmp := WinOcr._Await(op)
            ComCall(6, this.engine, "ptr", bmp, "ptr*", &op := 0)      ; RecognizeAsync
            result := WinOcr._Await(op)
        } finally
            ObjRelease(stream)
        out := []
        ComCall(6, result, "ptr*", &lines := 0)                         ; get_Lines
        ComCall(7, lines, "uint*", &n := 0)                             ; IVectorView.Size
        rect := Buffer(16)
        loop n {
            ComCall(6, lines, "uint", A_Index - 1, "ptr*", &line := 0)  ; GetAt
            ComCall(7, line, "ptr*", &hs := 0)                          ; IOcrLine.get_Text
            ltext := WinOcr._Str(hs)
            ComCall(6, line, "ptr*", &words := 0)                       ; IOcrLine.get_Words
            ComCall(7, words, "uint*", &wn := 0)
            ws := []
            loop wn {
                ComCall(6, words, "uint", A_Index - 1, "ptr*", &word := 0)
                ComCall(6, word, "ptr", rect)                           ; IOcrWord.get_BoundingRect
                ComCall(7, word, "ptr*", &hs := 0)                      ; IOcrWord.get_Text
                ws.Push({text: WinOcr._Str(hs)
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
            , "ptr", WinOcr._Guid("{7BF80980-BF32-101A-8BBB-00AA00300CAB}"), "int", false, "ptr*", &pic := 0, "HRESULT")
        ComCall(15, pic, "ptr", istream, "int", true, "int*", &size := 0)  ; IPicture.SaveAsFile
        DllCall("shcore\CreateRandomAccessStreamOverStream", "ptr", istream, "uint", 0
            , "ptr", WinOcr._Guid("{905A0FE1-BC53-11DF-8C49-001E4FC686DA}"), "ptr*", &ras := 0, "HRESULT")
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
        hs := WinOcr._HStr(cls)
        try DllCall("combase\RoGetActivationFactory", "ptr", hs, "ptr", WinOcr._Guid(iid), "ptr*", &f := 0, "HRESULT")
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
