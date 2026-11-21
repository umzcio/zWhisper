import SwiftUI

/// A context-mode result shown the way the paste review shows it: every
/// line that would be typed, numbered and wrapped in a scroll view, with
/// invisible, control and reordering characters drawn as markers
/// (PasteGuard.review), and a summary that warns about several lines or
/// hidden characters. Used by the popover review and by History for
/// results that were discarded without being approved.
struct ReviewText: View {
    let text: String
    /// What happens to the text, e.g. "Return types" or "Copy gives".
    let action: String

    var body: some View {
        let shown = PasteGuard.review(text)
        let lines = shown.lines
        let multiline = lines.count > 1
        let warn = multiline || shown.hidden > 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: warn ? "exclamationmark.triangle.fill" : "eye")
                Text(Self.summary(shown, action: action))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(warn ? ZWColor.accentOrange : ZWColor.text2)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if multiline {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ZWColor.text3)
                                    .frame(minWidth: 18, alignment: .trailing)
                            }
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 13))
                                .foregroundStyle(ZWColor.text1)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(8)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZWColor.surface2.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    static func summary(_ shown: PasteGuard.Review, action: String) -> String {
        let lines = shown.lines.count
        var text = lines > 1
            ? "\(action) all \(lines) lines (\(shown.scalars) characters)."
            : "\(action) this (\(shown.scalars) characters)."
        if shown.hidden > 0 {
            text += " \(shown.hidden) hidden \(shown.hidden == 1 ? "character is" : "characters are") marked ⟨U+…⟩."
        } else if lines > 1 {
            text += " Check each one."
        }
        return text
    }
}
