import AppKit
import SwiftUI

/// §6.3 History screen, embedded in the management window (M6): list + detail
/// functional — playback, transport, word-level click-to-seek (interpolated
/// across segment spans per §10.5), search + mode/date filters, row quick
/// actions, and the reprocess bar as a shell (wired in M5, kept a shell for M6).
struct HistoryView: View {
    let appState: AppState
    var embedded = false

    @State private var selection: HistoryEntry.ID?
    @State private var search = ""
    @State private var player = HistoryPlayer()
    @State private var loadedEntryID: HistoryEntry.ID?
    @State private var filterOpen = false
    @State private var modeFilter: Set<Mode.ID> = []
    @State private var dateFilter: DateFilter = .all

    private enum DateFilter: String, CaseIterable {
        case today, week, all

        var title: String {
            switch self {
            case .today: "Today"
            case .week: "This week"
            case .all: "All"
            }
        }
    }

    /// §6.3: mode chips + date row AND-combined with the search query.
    private var filteredEntries: [HistoryEntry] {
        appState.history.filter { entry in
            if !modeFilter.isEmpty && !modeFilter.contains(entry.modeID) { return false }
            switch dateFilter {
            case .today:
                guard Calendar.current.isDateInToday(entry.createdAt) else { return false }
            case .week:
                guard entry.createdAt >= Date().addingTimeInterval(-7 * 86_400) else { return false }
            case .all:
                break
            }
            guard !search.isEmpty else { return true }
            return entry.processedText.localizedCaseInsensitiveContains(search)
                || entry.rawTranscript.localizedCaseInsensitiveContains(search)
        }
    }

    private var activeFilterCount: Int {
        modeFilter.count + (dateFilter == .all ? 0 : 1)
    }

    private var selectedEntry: HistoryEntry? {
        appState.history.first { $0.id == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: 340)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(ZWColor.separator).frame(width: 1)
                }
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZWColor.surface1)
        .onChange(of: selection) {
            // Quick-play loads the player itself; skip the reload for that entry.
            guard selection != loadedEntryID else { return }
            player.load(url: selectedEntry.flatMap { appState.audioURL(for: $0) })
            loadedEntryID = selection
        }
        .onDisappear { player.stop() }
    }

    // MARK: List pane (§6.3: 340px, 72px rows under sticky date headers)

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(ZWColor.text3)
                    TextField("Search transcripts", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(ZWColor.text1)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                filterButton
            }
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedByDay, id: \.title) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                HistoryRow(
                                    entry: entry,
                                    mode: appState.mode(for: entry.modeID),
                                    isSelected: entry.id == selection,
                                    onPlay: { quickPlay(entry) },
                                    onCopy: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.processedText, forType: .string)
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = entry.id
                                }
                            }
                        } header: {
                            Text(group.title.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.66)
                                .foregroundStyle(ZWColor.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(ZWColor.surface1.opacity(0.9).background(.ultraThinMaterial))
                        }
                    }
                }
            }
        }
    }

    /// §6.3 filter button: 28×28; active (open or filtered) → accent/20 tint +
    /// 14px mono 9px count badge.
    private var filterButton: some View {
        let active = filterOpen || activeFilterCount > 0
        return Button { filterOpen.toggle() } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13))
                .foregroundStyle(active ? ZWColor.accentBlue : ZWColor.text2)
                .frame(width: 28, height: 28)
                .background(active ? ZWColor.accentBlue.opacity(0.2) : ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(ZWColor.accentBlue)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(ZWButtonStyle(pressScale: 0.95))
        .popover(isPresented: $filterOpen, arrowEdge: .top) {
            filterPopover
        }
    }

    /// §6.3 filter popover: 240px wide, radius 14 — mode checkmark list
    /// (multi-select, mode-color icon) + date segmented row.
    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Literal uppercase — .textCase(.uppercase)+tracking mis-measures
            // and clips the first glyph on 1x displays.
            Text("MODES")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(ZWColor.text3)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(appState.modes) { mode in
                    modeFilterRow(mode)
                }
            }
            .padding(.bottom, 12)
            Text("DATE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(ZWColor.text3)
                .padding(.bottom, 6)
            Picker("Date", selection: $dateFilter) {
                ForEach(DateFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
        .frame(width: 240)
    }

    private func modeFilterRow(_ mode: Mode) -> some View {
        let on = modeFilter.contains(mode.id)
        return Button {
            if on { modeFilter.remove(mode.id) } else { modeFilter.insert(mode.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: mode.colorHex))
                    .frame(width: 16)
                Text(mode.name)
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text1)
                Spacer(minLength: 8)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZWColor.accentBlue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(on ? ZWColor.accentBlue.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Row quick action (§6.3): select the entry and start playback. Loads the
    /// player directly so the selection-change handler doesn't restart it.
    private func quickPlay(_ entry: HistoryEntry) {
        selection = entry.id
        player.load(url: appState.audioURL(for: entry))
        loadedEntryID = entry.id
        player.play()
    }

    private var groupedByDay: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var groups: [(String, [HistoryEntry])] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        for entry in filteredEntries {
            let title: String
            if calendar.isDateInToday(entry.createdAt) {
                title = "Today"
            } else if calendar.isDateInYesterday(entry.createdAt) {
                title = "Yesterday"
            } else {
                title = formatter.string(from: entry.createdAt)
            }
            if let last = groups.last, last.0 == title {
                groups[groups.count - 1].1.append(entry)
            } else {
                groups.append((title, [entry]))
            }
        }
        return groups
    }

    // MARK: Detail pane (§6.3)

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedEntry {
            VStack(spacing: 0) {
                detailHeader(entry)
                WaveformStrip(
                    audioURL: appState.audioURL(for: entry),
                    progress: player.duration > 0 ? player.currentTime / player.duration : 0
                ) { fraction in
                    player.seek(to: fraction * player.duration)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                transport
                transcript(entry)
                reprocessBarShell
            }
        } else {
            // §6.3 empty state: 48px surface-2 mic tile, text-3
            VStack(spacing: 12) {
                Image(systemName: "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(ZWColor.text3)
                    .frame(width: 48, height: 48)
                    .background(ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Select a recording")
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ entry: HistoryEntry) -> some View {
        let mode = appState.mode(for: entry.modeID)
        return HStack(spacing: 10) {
            Image(systemName: mode.icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: mode.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: mode.colorHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(mode.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(ZWColor.text1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(ZWColor.surface2.opacity(0.8))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(ZWColor.separator, lineWidth: 1))
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ZWColor.text3)
            Text(Self.formatClock(entry.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ZWColor.text2)
            Spacer(minLength: 0)
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.processedText, forType: .string)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ZWColor.text2)
            .buttonStyle(ZWButtonStyle())
            Button("Delete") {
                appState.deleteHistory(id: entry.id)
                selection = nil
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ZWColor.accentRed)
            .buttonStyle(ZWButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// §6.3 transport: skip ±5s (32px round ghost, mono "5" caption), play/pause
    /// 36px accent circle, time `0:12.4 / 0:38` mono, speed segmented 1×/1.5×/2×.
    private var transport: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                TransportButton(systemName: "gobackward", caption: "5") {
                    player.skip(-5)
                }
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(ZWColor.accentBlue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                }
                .buttonStyle(ZWButtonStyle(pressScale: 0.94))
                TransportButton(systemName: "goforward", caption: "5") {
                    player.skip(5)
                }
            }
            Text("\(Self.formatTenths(player.currentTime)) / \(Self.formatClock(player.duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ZWColor.text2)
            Spacer(minLength: 0)
            Picker("Speed", selection: Binding(
                get: { player.rate },
                set: { player.setRate($0) }
            )) {
                Text("1×").tag(Float(1))
                Text("1.5×").tag(Float(1.5))
                Text("2×").tag(Float(2))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// §6.3 transcript: 15px/500 relaxed paragraphs, px 20 py 16. Every word is
    /// a button — word times interpolated linearly across each segment's
    /// [start, end] span (§10.5 segment approximation). Click seeks + plays;
    /// during playback the active word is highlighted and auto-scrolled into view.
    private func transcript(_ entry: HistoryEntry) -> some View {
        let paragraphs = Self.timedParagraphs(for: entry)
        let activeWord = activeWordID(in: paragraphs)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if paragraphs.isEmpty {
                        Text(entry.processedText)
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.15)
                            .foregroundStyle(ZWColor.text1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, words in
                            FlowLayout(spacing: 4, lineSpacing: 6) {
                                ForEach(words) { word in
                                    WordButton(
                                        word: word.text,
                                        timestamp: Self.formatTenths(word.time),
                                        isActive: word.id == activeWord
                                    ) {
                                        player.seek(to: word.time)
                                        if !player.isPlaying { player.play() }
                                    }
                                    .id(word.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: activeWord) {
                if let activeWord {
                    withAnimation(.easeOut(duration: 0.5)) {
                        proxy.scrollTo(activeWord, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One paragraph per segment; word i of n in a segment is placed at
    /// `start + i/n * (end − start)` (§10.5).
    private static func timedParagraphs(for entry: HistoryEntry) -> [[TimedWord]] {
        var nextID = 0
        return entry.segments.compactMap { segment in
            let words = segment.text.split { $0 == " " || $0 == "\n" }
            guard !words.isEmpty else { return nil }
            let span = max(0, segment.end - segment.start)
            return words.enumerated().map { index, word in
                defer { nextID += 1 }
                return TimedWord(
                    id: nextID,
                    text: String(word),
                    time: segment.start + Double(index) / Double(words.count) * span
                )
            }
        }
    }

    /// During playback: the last word whose time ≤ currentTime.
    private func activeWordID(in paragraphs: [[TimedWord]]) -> Int? {
        guard player.isPlaying else { return nil }
        var active: Int?
        for paragraph in paragraphs {
            for word in paragraph where word.time <= player.currentTime {
                active = word.id
            }
        }
        return active
    }

    /// §6.3 reprocess bar — shell only; the pipeline is wired in M5 and the M6
    /// bar keeps this a shell (row quick action likewise stays disabled).
    private var reprocessBarShell: some View {
        HStack(spacing: 10) {
            Text("Reprocess with…")
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text2)
            ForEach(["Email", "Message", "Note", "Meeting"], id: \.self) { name in
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ZWColor.text3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ZWColor.surface2)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(ZWColor.separator, lineWidth: 1))
            }
            Spacer(minLength: 0)
            Button("Apply") {}
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ZWColor.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(ZWButtonStyle())
                .disabled(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ZWColor.surface2.opacity(0.4).background(.ultraThinMaterial))
        .overlay(alignment: .top) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
    }

    /// `m:ss` (§4.3 meta / §6.3 duration).
    static func formatClock(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let rest = Int(seconds.rounded()) % 60
        return String(format: "%d:%02d", minutes, rest)
    }

    /// `m:ss.d` (§6.3 transport/word timestamps).
    static func formatTenths(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let rest = seconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, rest)
    }
}

private struct TimedWord: Identifiable {
    let id: Int
    let text: String
    let time: TimeInterval
}

/// §6.3 list row: 28px mode squircle · title 13px/500 truncated · meta 11px
/// text-2 · uppercase mode chip replaced on hover by 24×24 quick actions
/// (play / reprocess / copy). Selected bg #0A84FF26, hover surface-3/70.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let mode: Mode
    let isSelected: Bool
    let onPlay: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: mode.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: mode.colorHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: entry))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ZWColor.text1)
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                Text(mode.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(ZWColor.text2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(ZWColor.surface2)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(ZWColor.separator, lineWidth: 1))
                    .opacity(hovering ? 0 : 1)
                HStack(spacing: 2) {
                    QuickActionButton(systemName: "play.fill", action: onPlay)
                    // M6: reprocess stays a shell (§6.3) — intentionally not wired.
                    QuickActionButton(systemName: "arrow.clockwise") {}
                        .disabled(true)
                        .opacity(0.4)
                    QuickActionButton(systemName: "doc.on.doc", action: onCopy)
                }
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 72)
        .background(isSelected ? ZWColor.accentBlue.opacity(0.15) : (hovering ? ZWColor.surface3.opacity(0.7) : .clear))
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovering)
    }

    private static func title(for entry: HistoryEntry) -> String {
        let text = entry.processedText.replacingOccurrences(of: "\n", with: " ")
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }

    /// §6.3 meta: `9:41 AM · 0:38 · 142 words`.
    private var meta: String {
        let time = entry.createdAt.formatted(date: .omitted, time: .shortened)
        let duration = HistoryView.formatClock(entry.duration)
        let words = entry.processedText.split(separator: " ").count
        return "\(time) · \(duration) · \(words) words"
    }
}

/// §6.3 row quick action: 24×24 surface-2 hairline button.
private struct QuickActionButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text2)
                .frame(width: 24, height: 24)
                .background(ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(ZWColor.separator, lineWidth: 1)
                )
        }
        .buttonStyle(ZWButtonStyle(pressScale: 0.9))
    }
}

/// §6.3 transcript word: hover pill surface-3 with mono `m:ss.d` timestamp chip
/// 24px above; active word accent-blue/20 bg + accent text (120ms transition).
private struct WordButton: View {
    let word: String
    let timestamp: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(word)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(isActive ? ZWColor.accentBlue : ZWColor.text1)
                .padding(.horizontal, 2)
                .background(isActive ? ZWColor.accentBlue.opacity(0.2) : (hovering ? ZWColor.surface3 : .clear))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: hovering)
        .overlay(alignment: .top) {
            Text(timestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ZWColor.text2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(ZWColor.separator, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .fixedSize()
                .offset(y: -26)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(false)
        }
        .zIndex(hovering ? 1 : 0)
    }
}

/// 32px round ghost skip button with mono caption (§6.3 transport).
private struct TransportButton: View {
    let systemName: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: systemName)
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text2)
                Text(caption)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(ZWColor.text2)
                    .offset(y: 1)
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(ZWButtonStyle(hoverScale: 1.08, pressScale: 0.94))
    }
}

/// Horizontal-wrap layout for the transcript word flow and filter mode chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                maxX = max(maxX, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxX = max(maxX, x - spacing)
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
