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
