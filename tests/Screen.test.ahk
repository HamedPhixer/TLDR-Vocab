;================================================================================
; Screen.test.ahk - real text on a real screen, read back by the real code
;================================================================================
; Draws a window of test text for a few seconds (top-left of the main screen)
; and points Translate, Summary, the word lookup and the box at it - the same
; functions the keys call, handed a position instead of the mouse. Nothing is
; clicked and the mouse is not moved. Uses Windows' OCR, so it needs a desktop:
; it cannot run on GitHub's servers, only on a PC.
;
; The cases are the ones Translate was tuned on: a chat-like run of lines, a
; sentence wrapped onto a second line, a line ending "Now:" above a bullet,
; dialogue in pieces, a long paragraph, and small print.
;================================================================================
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Harness.ahk

OX := 20, OY := 60
g := Gui("-Caption +AlwaysOnTop -DPIScale")
g.BackColor := "FFFFFF"
g.SetFont("s12", "Segoe UI")
; A: lines that each end on purpose
g.Add("Text", "x30 y20 w640", "this is the example dont mind it :)")
g.Add("Text", "x30 y42 w640", "bluh bluh bluh bluh bluh bluh. bluh bluh bluh bluh bluh bluh bluh. bluh bluh bluh.")
g.Add("Text", "x30 y64 w640", "bleh bleh bleh bleh. bleh bleh.bleh. bleh .")
; F: one sentence wrapped onto a second line, wider lines around it
g.Add("Text", "x30 y110 w1000", "Where it can still guess wrong, and what the app does about it when a line of text runs all the way across.")
g.Add("Text", "x30 y132 w760", "Several chat messages that are all about the same length (each running to the edge) get read as one wrapped paragraph.")
g.Add("Text", "x30 y176 w1000", "Chats written all in lowercase can join a message to the next one, which is the other case worth knowing about.")
; G: dialogue in pieces, and a long paragraph
g.Add("Text", "x30 y230 w1200", "Wait. No. Not that one. The other door, the red one.")
p := ""
loop 7
    p .= "This long paragraph goes on and on, sentence " A_Index " of seven, so it is well over any limit. "
g.Add("Text", "x30 y280 w1250", p)
; H: a line ending with a colon, and a bullet under it
g.Add("Text", "x700 y20 w640", "OCR does give each line separately; it wasn't a limitation. Now:")
g.Add("Text", "x720 y46 w620", Chr(0x2022) "  Full stop, space, word on the same line: a sentence boundary inside the text. It counts these and takes up to 3 sentences.")
; S: small print in two paragraphs, and a sentence with a colon
g.SetFont("s8", "Segoe UI")
g.Add("Text", "x30 y380 w700", "Small print, the kind a game note or a settings page uses. It goes on for a few lines so that "
    . "the block has something to it: the harbour, the boats, the gulls, and a quay where nobody says a word.")
g.Add("Text", "x30 y430 w700", "A second paragraph after a blank line, still small, which the summary should take as part of the same note.")
g.SetFont("s12", "Segoe UI")
g.Add("Text", "x800 y400 w500", "The guard nodded: he had seen the letter before. Nobody else knew; not even the captain.")
g.Show("x" OX " y" OY " w1360 h480 NoActivate")
Sleep 500

ReadAt(x, y) => SentenceAtPoint(OX + x, OY + y)
TextOf(hit) => hit ? hit.text : "(nothing)"

Check("translate: a line on its own", TextOf(ReadAt(60, 74)), "bleh bleh bleh bleh. bleh bleh.bleh. bleh .")
wrapped := "Several chat messages that are all about the same length (each running to the edge) get read as one wrapped paragraph."
Check("translate: wrapped sentence, first line", TextOf(ReadAt(200, 142)), wrapped)
Check("translate: wrapped sentence, second line", TextOf(ReadAt(20, 164)), wrapped)
Check("translate: dialogue in pieces", TextOf(ReadAt(50, 240)), "Wait. No. Not that one. The other door, the red one.")
Check("translate: the line ending with a colon", TextOf(ReadAt(800, 30)), "OCR does give each line separately; it wasn't a limitation. Now:")
Check("translate: the bullet under it, no bullet dot"
    , TextOf(ReadAt(1000, 78)), "Full stop, space, word on the same line: a sentence boundary inside the text. It counts these and takes up to 3 sentences.")
CheckHas("translate: long paragraph, all seven sentences", TextOf(ReadAt(400, 312)), "sentence 2 of seven", "sentence 7 of seven")

t0 := A_TickCount
hit := ParagraphAtPoint(OX + 200, OY + 390)
ms := A_TickCount - t0
CheckHas("summary: small print, both paragraphs", TextOf(hit), "Small print, the kind", "quay where nobody says a word", "A second paragraph")
CheckTrue("summary: under a second", ms < 1000, ms " ms")

t0 := A_TickCount
w := WordAtPoint(OX + 905, OY + 410)
ms := A_TickCount - t0
Check("word: the word", w ? w.word : "", "nodded")
Check("word: its example sentence", w ? w.context : "", "The guard nodded: he had seen the letter before.")
CheckTrue("word: under half a second", ms < 500, ms " ms")

CheckHas("box: reads what is inside", Box.TextIn(OX + 795, OY + 395, 510, 60), "The guard nodded", "not even the captain")

g.Destroy()

; pinning: a real card, pinned, then a second one beside it (no lookup is
; attached, so nothing goes to the network - the cards just show their dots)
first := Popup
Popup.Begin("harbour", "", {x: 300, y: 200, w: 60, h: 20})
Popup.Pin()
CheckTrue("pin: the pinned card stays", first.isPinned && first.visible && PopupCard.pinned.Length = 1)
CheckTrue("pin: the next lookup gets a new card", !(Popup == first))
Popup.Begin("quay", "", {x: 900, y: 200, w: 60, h: 20})
CheckTrue("pin: both on screen", DllCall("IsWindowVisible", "ptr", first.g.Hwnd) && DllCall("IsWindowVisible", "ptr", Popup.g.Hwnd))
WinMove(500, 500, , , first.g.Hwnd)
first.Render()
WinGetPos(&px, &py, , , first.g.Hwnd)
CheckTrue("pin: a pinned card stays where it was put", px = 500 && py = 500, px "," py)
Popup.ClickAway()                           ; the mouse is not over the live card
CheckTrue("pin: a click away closes only the live card", !Popup.visible && first.visible)
first.Close()
CheckTrue("pin: its x closes it for good", !PopupCard.pinned.Length && !first.g)

; Settings: a window that scrolls, and can be made shorter
for a in Keys.List                      ; the key rows need keys; the defaults, not registered
    Keys.cur[a.id] := a.def
Settings.Show()
WinMove(40, 40, , , Settings.g.Hwnd)
WinGetClientPos(, , , &ch, Settings.g.Hwnd)
full := Settings.pane.contentH
Settings.g.Move(, , , 400)
Sleep 200
CheckTrue("settings: can be made shorter than its content", Settings.pane.h < full && Settings.pane.h < ch, Settings.pane.h " of " full)
WinGetPos(&sx, &sy, &sw, &sh, Settings.g.Hwnd)
CheckTrue("settings: the wheel finds its pane", ScrollPane.At(sx + sw // 2, sy + sh // 2) == Settings.pane)
Settings.pane.ScrollBy(200)
CheckTrue("settings: it scrolls", Settings.pane.scroll = 200, Settings.pane.scroll)
Settings.pane.ScrollBy(100000)
CheckTrue("settings: not past the end", Settings.pane.scroll = full - Settings.pane.h)
Settings.Close()

Done()
