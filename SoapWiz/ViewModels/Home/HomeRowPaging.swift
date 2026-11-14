import Foundation

/// A Home card's rows and how many of them it shows: a few while collapsed,
/// more once expanded, the rest left to History.
protocol HomeRowPaging {
    associatedtype Item
    var items: [Item] { get }
}

extension HomeRowPaging {
    /// Rows the card shows before "Show more".
    static var collapsedRowLimit: Int { 4 }

    /// Rows the card shows at most once expanded; the rest are left to History.
    static var expandedRowLimit: Int { 10 }

    var count: Int { items.count }

    /// Whether there are more rows than the collapsed card shows.
    var canExpand: Bool { count > Self.collapsedRowLimit }

    /// The rows the card lists: the first four, or up to ten once expanded.
    func visibleItems(isExpanded: Bool) -> [Item] {
        Array(items.prefix(isExpanded && canExpand ? Self.expandedRowLimit : Self.collapsedRowLimit))
    }

    /// The rows the expanded card leaves to History: only past ten, and none
    /// while collapsed, where "Show more" comes first.
    func historyCount(isExpanded: Bool) -> Int {
        isExpanded ? max(0, count - Self.expandedRowLimit) : 0
    }
}
