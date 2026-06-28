import Testing
import Foundation
@testable import Delta

struct HTMLExporterTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    @Test func producesSelfContainedDocument() {
        let rows = DiffEngine.sideBySide("a", "b")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<style>"))
    }

    @Test func headerContainsGeneratedDate() {
        let html = HTMLExporter.html(rows: [], orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("1970-01-01T00:00:00Z"))
    }

    @Test func escapesHTMLSpecialChars() {
        // char diff of "<x>" vs "&y": left deletes <,x,> ; right inserts &,y
        let rows = DiffEngine.sideBySide("<x>", "&y")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("&lt;"))
        #expect(html.contains("&gt;"))
        #expect(html.contains("&amp;"))
        #expect(!html.contains("<x>"))
    }

    @Test func horizontalProducesTableWithRowPerDiffRow() {
        let rows = DiffEngine.sideBySide("a\nb", "a\nc")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("<table"))
        let trCount = html.components(separatedBy: "<tr>").count - 1
        #expect(trCount == rows.count)
    }

    @Test func verticalProducesTwoPanes() {
        let rows = DiffEngine.sideBySide("a\nb", "a\nc")
        let html = HTMLExporter.html(rows: rows, orientation: .vertical, generatedAt: epoch)
        #expect(html.contains("diff v"))
        let paneCount = html.components(separatedBy: "class=\"pane\"").count - 1
        #expect(paneCount == 2)
    }

    @Test func intralineChangeUsesSpans() {
        // "abc" vs "abd": equal a,b ; delete c / insert d
        let rows = DiffEngine.sideBySide("abc", "abd")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("<span class=\"del\">c</span>"))
        #expect(html.contains("<span class=\"ins\">d</span>"))
    }

    @Test func wholeLineAndGap() {
        // "a\nb" vs "a": equal a row, then delete "b" (left whole-line delete, right gap)
        let rows = DiffEngine.sideBySide("a\nb", "a")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("class=\"del\""))
        #expect(html.contains("class=\"gap\""))
    }
}
