;================================================================================
; All.ahk - every part of Vocab, in the order they load
;================================================================================
; Vocab.ahk includes this, and so do the tests in tests\ - one list, so the
; two can never disagree about what the app is made of.
;
;   Json       reading and writing JSON
;   Config     what is set in the script: version, icon, colours, sizes
;   Language   the language translations go into
;   Lookup     the sources: dictionaries, translators, Gemini, and the cache
;   Ocr        Windows' OCR, and reading a piece of the screen
;   Lines      turning OCR output into lines of text on a page
;   Speak      hearing the word
;   App        the ini, the icon, the tray, starting a lookup
;   Word       the word under the mouse, and the selected text
;   Store      your dictionary, words.json
;   Cards      drawing a lookup or a saved word
;   Popup      the lookup popup
;   WordList   the dictionary window
;   Sentence   the Translate card
;   Paragraph  the Summary card
;   Box        drawing a box to read
;   Keys       the keys, and recording new ones
;   Settings   the settings window
;================================================================================
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Config.ahk
#Include %A_LineFile%\..\Language.ahk
#Include %A_LineFile%\..\Lookup.ahk
#Include %A_LineFile%\..\Ocr.ahk
#Include %A_LineFile%\..\Lines.ahk
#Include %A_LineFile%\..\Speak.ahk
#Include %A_LineFile%\..\App.ahk
#Include %A_LineFile%\..\Word.ahk
#Include %A_LineFile%\..\Store.ahk
#Include %A_LineFile%\..\Cards.ahk
#Include %A_LineFile%\..\Popup.ahk
#Include %A_LineFile%\..\WordList.ahk
#Include %A_LineFile%\..\Sentence.ahk
#Include %A_LineFile%\..\Paragraph.ahk
#Include %A_LineFile%\..\Box.ahk
#Include %A_LineFile%\..\Keys.ahk
#Include %A_LineFile%\..\Settings.ahk
