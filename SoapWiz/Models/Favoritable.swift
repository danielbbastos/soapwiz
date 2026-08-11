/// A model the user can pin to the top of its list.
protocol Favoritable {
    var isFavorite: Bool { get set }
}

extension Recipe: Favoritable {}
extension Ingredient: Favoritable {}

extension Array where Element: Favoritable {
    /// Favourites first, each group keeping the order it arrived in — which is the
    /// alphabetical order the `@Query` sorted by. Toggling inside `withAnimation`
    /// then reads as the row sliding to its new position.
    ///
    /// Partitioned rather than sorted with a comparator: `sort` is introsort and is
    /// not documented as stable, so a comparator that only ranks `isFavorite` would
    /// be free to shuffle equal elements and scramble the alphabetical order inside
    /// each group. Two passes cost nothing at this size and are deterministic.
    var favoritesFirst: [Element] {
        filter(\.isFavorite) + filter { !$0.isFavorite }
    }
}
