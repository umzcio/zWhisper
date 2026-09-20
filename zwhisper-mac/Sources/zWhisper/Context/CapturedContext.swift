import Foundation

/// Architecture §3.7. Capture itself lands in M7 (600ms dot deadline);
/// M5 threads the type through the processing pipeline.
struct CapturedContext: Equatable, Sendable {
    /// Bundle id + display name of the frontmost app.
    let frontmostApp: String
    /// AXSelectedText of the focused element.
    let selectedText: String?
    /// Only read when the mode has readsClipboard (§6.2).
    let clipboard: String?
    let capturedAt: Date
}
