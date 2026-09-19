;================================================================================
; Lines.ahk - OCR output as lines of text on a page
;================================================================================
; Windows' OCR hands back lines of words, in its own order. Translate, Summary
; and the box all start the same way - these rows, sorted down the page - and
; then each decides for itself which of them belong together.
;
;   PageRows(lines)                  the lines as rows: text, words, rectangle,
;                                sorted top to bottom
;   ColumnRows(rows, here)       only the rows in the same column as row here
;   JoinRows(rows, first, last)  their text, with a new line at a paragraph gap
;   MonitorRectAt(x, y)          the monitor a point is on, as [x, y, w, h]
;================================================================================
#Requires AutoHotkey v2.0

; Each row's text is rebuilt from its words, so an offset counted in words and
; one counted in characters agree - Translate cuts sentences around the word
; the pointer is on, and needs both. Lines with no words are dropped.
PageRows(lines) {
    rows := []
    for row in lines {
        if !row.words.Length
            continue
        x1 := 1e9, y1 := 1e9, x2 := -1e9, y2 := -1e9
        parts := []
        for w in row.words {
            x1 := Min(x1, w.x), y1 := Min(y1, w.y), x2 := Max(x2, w.x + w.w), y2 := Max(y2, w.y + w.h)
            parts.Push(w.text)
        }
        rows.Push({text: Join(parts, " "), words: row.words, x1: x1, y1: y1, x2: x2, y2: y2, h: y2 - y1})
    }
    SortRows(rows)
    return rows
}

; Windows hands the lines back in its own order, which is not always down the
; page - and walking "the next line" from the pointer only means anything on
; lines sorted by where they sit.
SortRows(rows) {
    i := 2
    while (i <= rows.Length) {
        r := rows[i], j := i - 1
        while (j >= 1 && (rows[j].y1 > r.y1 || (rows[j].y1 = r.y1 && rows[j].x1 > r.x1))) {
            rows[j + 1] := rows[j]
            j--
        }
        rows[j + 1] := r
        i++
    }
}

; The screen almost always has other text on it - another window alongside,
; a sidebar, a chat - and sorted top to bottom those lines sit BETWEEN the
; lines of the block you are pointing at. Walking from line to line would meet
; one of them immediately and stop. So the walk is done over one column: the
; rows that overlap row here sideways, and only those. Returns the column and
; where row here sits in it.
ColumnRows(rows, here) {
    a := rows[here]
    out := [], at := 1
    for r in rows
        if (r.x1 < a.x2 && a.x1 < r.x2) {
            out.Push(r)
            if (r == a)
                at := out.Length
        }
    return {rows: out, at: at}
}

; The text of rows first..last. A gap wider than most of a line between two
; rows is a new paragraph, kept as a line break - the Summary card shows it.
JoinRows(rows, first := 1, last := 0) {
    if !last
        last := rows.Length
    text := ""
    loop last - first + 1 {
        i := first + A_Index - 1
        if (i > first)
            text .= (rows[i].y1 - rows[i - 1].y2 > rows[i].h * 0.9) ? "`n" : " "
        text .= rows[i].text
    }
    return Trim(text)
}

MonitorRectAt(x, y) {
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return [l, t, r - l, b - t]
    }
    MonitorGet(MonitorGetPrimary(), &l, &t, &r, &b)
    return [l, t, r - l, b - t]
}
