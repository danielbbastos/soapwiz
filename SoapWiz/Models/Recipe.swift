import SwiftData

@Model
final class Recipe {
    var name: String
    var desc: String

    init(name: String, desc: String = "") {
        self.name = name
        self.desc = desc
    }
}
