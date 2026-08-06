import Testing
import Foundation
import UIKit
@testable import SoapWiz

@Suite("RecipeImageTextRecogniser")
struct RecipeImageTextRecogniserTests {

    @Test func recogniseText_RenderedRecipe_ReadsTheLines() async throws {
        let image = Self.render(lines: ["Olive Oil 70%", "Coconut Oil 30%"])
        let text = try await RecipeImageTextRecogniser.recogniseText(in: image)

        #expect(text.lowercased().contains("olive"))
        #expect(text.lowercased().contains("coconut"))
    }

    @Test func recogniseText_ReadsTopToBottom() async throws {
        let image = Self.render(lines: ["Olive Oil", "Coconut Oil", "Castor Oil"])
        let text = try await RecipeImageTextRecogniser.recogniseText(in: image)
        let lowered = text.lowercased()

        let olive = try #require(lowered.range(of: "olive"))
        let coconut = try #require(lowered.range(of: "coconut"))
        let castor = try #require(lowered.range(of: "castor"))
        #expect(olive.lowerBound < coconut.lowerBound)
        #expect(coconut.lowerBound < castor.lowerBound)
    }

    @Test func recogniseText_BlankImage_ReturnsEmpty() async throws {
        let text = try await RecipeImageTextRecogniser.recogniseText(in: Self.render(lines: []))
        #expect(text.isEmpty)
    }

    @Test func cgOrientation_MapsEveryCase() {
        #expect(UIImage.Orientation.up.cgOrientation == .up)
        #expect(UIImage.Orientation.right.cgOrientation == .right)
        #expect(UIImage.Orientation.downMirrored.cgOrientation == .downMirrored)
    }

    // MARK: - Reading order

    private func box(_ text: String, left: Double, centre: Double, width: Double = 0.2) -> RecipeImageTextRecogniser.TextBox {
        RecipeImageTextRecogniser.TextBox(
            text: text,
            rect: CGRect(x: left, y: centre, width: width, height: 0.02)
        )
    }

    @Test func rows_OrdersTopToBottom() {
        let result = RecipeImageTextRecogniser.rows(of: [
            box("bottom", left: 0.1, centre: 0.10),
            box("top", left: 0.1, centre: 0.80),
            box("middle", left: 0.1, centre: 0.45)
        ])
        #expect(result == ["top", "middle", "bottom"])
    }

    /// A table row arrives as separate boxes. They belong on one line, read
    /// across, so the name and its amount stay together.
    @Test func rows_SameRowBoxes_ReadLeftToRightOnOneLine() {
        let result = RecipeImageTextRecogniser.rows(of: [
            box("55%", left: 0.70, centre: 0.500),
            box("Olive Oil", left: 0.10, centre: 0.502)
        ])
        #expect(result == ["Olive Oil 55%"])
    }

    /// The case that broke the old comparator: A shares a row with B, and B
    /// with C, but A and C are further apart than the tolerance. Used inside
    /// `sorted(by:)` that is not a strict weak ordering, and the result could
    /// come out in any order at all. Grouping in one pass is well defined.
    @Test func rows_ChainedTolerances_StillProduceAStableReadingOrder() {
        let chained = [
            box("A", left: 0.10, centre: 0.5000),
            box("B", left: 0.40, centre: 0.4920),
            box("C", left: 0.70, centre: 0.4840)
        ]
        let result = RecipeImageTextRecogniser.rows(of: chained)
        let reversed = RecipeImageTextRecogniser.rows(of: chained.reversed())

        #expect(result == reversed, "reading order must not depend on the order Vision found the boxes")
        #expect(result.joined(separator: " ") == "A B C")
    }

    @Test func rows_EmptyInput_ReturnsEmpty() {
        #expect(RecipeImageTextRecogniser.rows(of: []).isEmpty)
    }

    @Test func rows_ASingleBox_IsItsOwnRow() {
        #expect(RecipeImageTextRecogniser.rows(of: [box("Olive Oil 55%", left: 0.1, centre: 0.5)]) == ["Olive Oil 55%"])
    }

    /// End to end through Vision: two columns on one visual row have to come
    /// back as one line, not two.
    @Test func recogniseText_TwoColumnRow_KeepsTheNameWithItsAmount() async throws {
        let image = Self.renderColumns(rows: [("Olive Oil", "55%"), ("Coconut Oil", "25%")])
        let text = try await RecipeImageTextRecogniser.recogniseText(in: image)
        let lines = text.split(separator: "\n").map(String.init)

        let olive = try #require(lines.first { $0.contains("Olive") })
        #expect(olive.contains("55"), "got \(lines)")
    }

    /// Two columns per row, well separated horizontally.
    private static func renderColumns(rows: [(String, String)]) -> UIImage {
        let size = CGSize(width: 1000, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52),
                .foregroundColor: UIColor.black
            ]
            for (index, row) in rows.enumerated() {
                let top = 80 + Double(index) * 140
                row.0.draw(at: CGPoint(x: 60, y: top), withAttributes: attributes)
                row.1.draw(at: CGPoint(x: 700, y: top), withAttributes: attributes)
            }
        }
    }

    /// Black text on white at a size Vision reads reliably.
    private static func render(lines: [String]) -> UIImage {
        let size = CGSize(width: 900, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56),
                .foregroundColor: UIColor.black
            ]
            for (index, line) in lines.enumerated() {
                let origin = CGPoint(x: 60, y: 60 + Double(index) * 110)
                line.draw(at: origin, withAttributes: attributes)
            }
        }
    }
}
