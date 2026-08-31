import SwiftUI
import UIKit

/// The hero photo at the top of the recipe detail screen.
///
/// Split out because it is a self-contained piece of presentation — how wide the
/// crop is, and whether there is a picture at all — with nothing to say about
/// the recipe's contents.
extension RecipeDetailView {

    /// A wider crop on iPad. The photo is as wide as the screen either way, so
    /// one ratio cannot serve both: a phone ratio across an iPad's width spends
    /// half the screen on the picture and pushes the recipe itself below the
    /// fold, while the iPad's ratio on a phone is a letterbox strip.
    ///
    /// Both are wide enough that the recipe starts on the first screen, and no
    /// wider: the frame is filled and cropped, so every step wider trades away
    /// the top and bottom of the user's photo. A portrait shot is cropped hard
    /// at any of these — it is a centre crop, which is where the subject of a
    /// photographed bar almost always is.
    ///
    /// Deliberately the device idiom rather than `horizontalSizeClass`, for the
    /// reason spelled out in `RecipeRowView`: `ContentView` pins the whole
    /// `TabView` to `.compact`, which leaves the size class saying "compact"
    /// everywhere.
    static let heroAspectRatio: CGFloat =
        UIDevice.current.userInterfaceIdiom == .phone ? 3.0 / 2.0 : 2.0 / 1.0

    /// Nil for a recipe with no photo, which leaves the screen laid out exactly
    /// as it was — an empty well at the top of every unphotographed recipe would
    /// spend a third of the screen saying nothing.
    var heroImage: UIImage? {
        recipe.imageData.flatMap(UIImage.init(data:))
    }
}
