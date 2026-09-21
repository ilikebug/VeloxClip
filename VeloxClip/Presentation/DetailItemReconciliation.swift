import Foundation

/// Reconciles the detail pane's two views of one item.
///
/// The pane keeps a debounced snapshot because it carries the lazily-loaded
/// blob (list queries deliberately omit the `data` column). The store holds the
/// live row, which gains background updates — OCR write-back, tag edits,
/// favorite toggles — but never has the blob.
///
/// The pane used to render a mix of the two: the header read the live row while
/// the preview content and toolbar read the snapshot. So when OCR finished with
/// the pane open, the store updated and the header re-rendered, but the OCR
/// text panel — reading the snapshot — stayed empty until the user reselected
/// the item.
enum DetailItemReconciliation {
    /// Live fields win, except for the blob: the snapshot is usually the only
    /// place it exists.
    static func merge(snapshot: ClipboardItem, live: ClipboardItem?) -> ClipboardItem {
        guard let live, live.id == snapshot.id else { return snapshot }

        var merged = live
        // The snapshot resolved the blob via loadData(for:); the store's copy
        // is nil for anything that came back from a list query.
        merged.data = live.data ?? snapshot.data
        return merged
    }
}
