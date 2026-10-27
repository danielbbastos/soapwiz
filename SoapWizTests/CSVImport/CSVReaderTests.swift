import Testing
@testable import SoapWiz

@Suite
struct CSVReaderTests {
    @Test func rows_EmptyText_HasNoRows() {
        #expect(CSVReader.rows(from: "").isEmpty)
    }

    @Test func rows_CommaFile_SplitsCells() {
        #expect(CSVReader.rows(from: "name,price\nOlive oil,4.5\n") == [["name", "price"], ["Olive oil", "4.5"]])
    }

    @Test func rows_SemicolonFileWithEuropeanDecimals_DetectsSemicolon() {
        let rows = CSVReader.rows(from: "name;price\nCoconut oil;5,50\nOlive oil;4,20")
        #expect(rows == [["name", "price"], ["Coconut oil", "5,50"], ["Olive oil", "4,20"]])
    }

    @Test func rows_TabFile_DetectsTab() {
        let rows = CSVReader.rows(from: "name\tprice\nOlive oil, extra\t4.5")
        #expect(rows == [["name", "price"], ["Olive oil, extra", "4.5"]])
    }

    @Test func rows_SingleColumn_DefaultsToComma() {
        #expect(CSVReader.rows(from: "name\nOlive oil\nShea butter") == [["name"], ["Olive oil"], ["Shea butter"]])    }

    @Test func rows_TiedDelimiters_PrefersSemicolonOverComma() {
        #expect(CSVReader.rows(from: "a,b;c") == [["a,b", "c"]])
    }

    @Test func rows_TiedRowCountsWithMoreCells_PrefersMoreCells() {
        #expect(CSVReader.rows(from: "a,b,c;d") == [["a", "b", "c;d"]])
    }

    @Test func rows_DelimiterMostRowsAgreeOn_Wins() {
        #expect(CSVReader.rows(from: "a;b\nc;d\ne;f,g\nh;i") == [["a", "b"], ["c", "d"], ["e", "f,g"], ["h", "i"]])
    }

    @Test func rows_DelimitersInsideQuotes_AreIgnoredWhenDetecting() {
        let rows = CSVReader.rows(from: "\"a;b;c\",d\n\"e;f;g\",h")
        #expect(rows == [["a;b;c", "d"], ["e;f;g", "h"]])
    }

    @Test func rows_QuotedFields_KeepDelimitersNewlinesAndDoubledQuotes() {
        let rows = CSVReader.rows(from: "a,\"b,c\",\"d\ne\",\"say \"\"hi\"\"\"")
        #expect(rows == [["a", "b,c", "d\ne", "say \"hi\""]])
    }

    @Test func rows_QuotedEmptyField_IsEmptyCell() {
        #expect(CSVReader.rows(from: "\"\",x") == [["", "x"]])
    }

    @Test func rows_CRLFInsideQuotes_IsPreserved() {
        #expect(CSVReader.rows(from: "\"a\r\nb\",c") == [["a\r\nb", "c"]])
    }

    @Test func rows_StrayQuoteInUnquotedField_IsKeptLiterally() {
        #expect(CSVReader.rows(from: "ab\"c,d") == [["ab\"c", "d"]])
    }

    @Test func rows_TextAfterClosingQuote_IsKept() {
        #expect(CSVReader.rows(from: "\"abc\"def,x") == [["abcdef", "x"]])
    }

    @Test func rows_MixedLineEndings_AllSplitRows() {
        #expect(CSVReader.rows(from: "a,b\r\nc,d\ne,f\rg,h") == [["a", "b"], ["c", "d"], ["e", "f"], ["g", "h"]])
    }

    @Test func rows_LeadingBOM_IsIgnored() {
        #expect(CSVReader.rows(from: "\u{FEFF}name,price\na,1") == [["name", "price"], ["a", "1"]])
    }

    @Test func rows_TrailingBlankRows_AreDropped() {
        #expect(CSVReader.rows(from: "a,b\nc,d\n\n,\n  \n\n") == [["a", "b"], ["c", "d"]])
    }

    @Test func rows_BlankRowInTheMiddle_IsKept() {
        #expect(CSVReader.rows(from: "a,b\n\nc,d") == [["a", "b"], [""], ["c", "d"]])
    }

    @Test func rows_RaggedRows_AreNotPadded() {
        #expect(CSVReader.rows(from: "a,b,c\nd\ne,f,g,h") == [["a", "b", "c"], ["d"], ["e", "f", "g", "h"]])
    }

    @Test func rows_EmptyCellsAndTrailingDelimiter_AreKept() {
        #expect(CSVReader.rows(from: "a,,c,\n,b,,") == [["a", "", "c", ""], ["", "b", "", ""]])
    }

    @Test func rows_UnclosedQuoteFollowedByLongText_StillDetectsDelimiterAndKeepsRestInOneField() {
        let tail = String(repeating: "x;y,z\n", count: 20_000)
        let rows = CSVReader.rows(from: "name;price\n\"open;1\n" + tail)
        #expect(rows.count == 2)
        #expect(rows[0] == ["name", "price"])
        #expect(rows[1] == ["open;1\n" + tail])
    }

    @Test func rows_RowsLongerThanTheSample_StillDetectsDelimiter() {
        let cell = String(repeating: "a", count: 20_000)
        let cells = ["Smith, John"] + Array(repeating: cell, count: 4)
        let row = cells.joined(separator: "\t")
        let rows = CSVReader.rows(from: row + "\n" + row)
        #expect(rows == [cells, cells])
        #expect(rows[0].count == 5)
    }

    @Test func rows_LastRowWithoutNewline_IsKept() {
        #expect(CSVReader.rows(from: "a,b\nc,d").last == ["c", "d"])
    }
}
