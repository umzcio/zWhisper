import SwiftUI

/// §6.2 Modes screen (M6): header + filter toolbar, 2-column card grid, editor
/// sheet (SPRING_SHEET), delete alert, save toast, and the ModeCycleStrip
/// footer. All persisted state flows through AppState's modes API (§7).
struct ModesView: View {
    let appState: AppState

    /// §6.2 toolbar SegmentedControl options.
    enum Segment: String, CaseIterable, Identifiable {
        case all = "All"
        case builtIn = "Built-in"
        case custom = "Custom"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .all
    @State private var search = ""
    @State private var draft: ModeDraft?
    @State private var deleteTarget: Mode?
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    /// §5.3: a just-added card pops in at scale 0.8→1 instead of the stagger.
    @State private var lastAddedID: UUID?

    private var filtered: [Mode] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return appState.modes.filter { mode in
            switch segment {
            case .all: break
            case .builtIn: guard mode.isBuiltIn else { return false }
            case .custom: guard !mode.isBuiltIn else { return false }
            }
            guard !query.isEmpty else { return true }
            return "\(mode.name) \(mode.description)".lowercased().contains(query)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                toolbar
                grid
                ModeCycleStrip(appState: appState)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZWColor.surface1)

            if let draft {
                ModeEditorSheet(
                    appState: appState,
                    draft: draft,
                    onCancel: closeEditor,
                    onSave: save
                )
                .id(draft.identity)
                .transition(.offset(y: -24).combined(with: .opacity))
            }

            if let deleteTarget {
                deleteAlert(deleteTarget)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if let toastMessage {
                saveToast(toastMessage)
                    .transition(.offset(x: 24).combined(with: .opacity))
            }
        }
    }

    // MARK: Header (§6.2)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modes")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(ZWColor.text1)
                Text("Choose how zWhisper rewrites your voice. Modes persist across sessions.")
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text2)
            }
            Spacer(minLength: 16)
            Button { openNewMode() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("New Mode")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ZWColor.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(ZWButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: Toolbar (§6.2)

    private var toolbar: some View {
        HStack {
            ModeSegmentedControl(selection: $segment)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text3)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text1)
            }
            .padding(.horizontal, 8)
            .frame(width: 192, height: 28)
            .background(ZWColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: Grid (§6.2: 2 cols, gap 16, §5.3 stagger 0.05s spring 400/30)

    private var grid: some View {
        ScrollView {
            if filtered.isEmpty {
                Text("No modes match “\(search)”.")
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text3)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, mode in
                        ModeCard(
                            mode: mode,
                            isActive: mode.id == appState.activeMode.id,
                            isNew: mode.id == lastAddedID,
                            entranceDelay: Double(index) * 0.05,
                            onSelect: { appState.setActiveMode(mode) },
                            onEdit: { openEditor(mode) },
                            onDuplicate: { lastAddedID = appState.duplicateMode(mode).id },
                            onDelete: {
                                withAnimation(AppState.springDefault) { deleteTarget = mode }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sheet / alert / toast overlays

    private func deleteAlert(_ mode: Mode) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .onTapGesture {
                    withAnimation(AppState.springDefault) { deleteTarget = nil }
                }
            VStack(spacing: 0) {
                Text("Delete “\(mode.name)”?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ZWColor.text1)
                Text("This can’t be undone.")
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text2)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Button("Cancel") {
                        withAnimation(AppState.springDefault) { deleteTarget = nil }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface3)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(ZWButtonStyle(hoverScale: 1, pressScale: 0.97))
                    Button("Delete") {
                        appState.deleteCustomMode(id: mode.id)
                        withAnimation(AppState.springDefault) { deleteTarget = nil }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(ZWColor.accentRed)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(ZWButtonStyle(hoverScale: 1, pressScale: 0.97))
                }
                .padding(.top, 12)
            }
            .padding(16)
            .frame(width: 280)
            .background(ZWColor.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 48, y: 32)
        }
    }

    /// §3.7 Modes save toast: top-right, radius 10, px 12 py 8, green check,
    /// 12px/500, slides x 24→0 (SPRING_DEFAULT), auto-dismiss 3s.
    private func saveToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(ZWColor.accentGreen)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZWColor.text1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ZWColor.surface1.background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 32, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 12)
        .padding(.trailing, 16)
        .allowsHitTesting(false)
    }

    // MARK: Actions

    private func openEditor(_ mode: Mode) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            draft = ModeDraft(mode: mode, isNew: false)
        }
    }

    private func openNewMode() {
        let mode = Mode(
            id: UUID(),
            name: "",
            icon: "sparkles",
            colorHex: "#BF5AF2",
            description: "Custom mode",
            instructions: "",
            readsSelectedText: false,
            readsClipboard: false,
            autoActivationRules: [],
            shortcutIndex: appState.nextFreeShortcutIndex(),
            isBuiltIn: false
        )
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            draft = ModeDraft(mode: mode, isNew: true)
        }
    }

    private func closeEditor() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            draft = nil
        }
    }

    private func save(_ draft: ModeDraft) {
        var mode = draft.mode
        mode.name = mode.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isNew {
            mode.description = Self.describeNew(mode.instructions)
            let saved = appState.addCustomMode(mode)
            lastAddedID = saved.id
            showToast(saved.name + " saved" + Self.shortcutSuffix(saved.shortcutIndex))
        } else {
            appState.updateCustomMode(mode)
            showToast(mode.name + " saved" + Self.shortcutSuffix(mode.shortcutIndex))
        }
        closeEditor()
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(AppState.springDefault) { toastMessage = message }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(AppState.springDefault) { toastMessage = nil }
        }
    }

    private static func shortcutSuffix(_ index: Int?) -> String {
        if let index { return " · ⌘\(index) assigned" }
        return ""
    }

    /// §6.2: a new card's description is the first instruction sentence (≤64 chars).
    static func describeNew(_ instructions: String) -> String {
        let first = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !first.isEmpty else { return "Custom mode" }
        return first.count > 64 ? String(first.prefix(61)) + "…" : first
    }
}

/// §6.2 editor draft: a mutable copy of the mode plus the is-new flag.
private struct ModeDraft {
    var mode: Mode
    var isNew: Bool
    var identity: String { "\(mode.id.uuidString)-\(isNew)" }
}

/// §3.8 ShortcutKey: kbd chip, radius 6, hairline, surface-2, mono 11px/500 text-2.
private struct KbdChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(ZWColor.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ZWColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
    }
}

/// §3.10 SegmentedControl: surface-2 outer radius 8 padding 2, segments 12px/500
/// radius 6, sliding surface-3 indicator (SPRING_MICRO).
private struct ModeSegmentedControl: View {
    @Binding var selection: ModesView.Segment
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ModesView.Segment.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == option ? ZWColor.text1 : ZWColor.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(ZWColor.surface3)
                                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "modes-segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(ZWColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
    }
}

/// §6.2 mode card: 96px, radius 12, surface-2, hairline, padding 12. Active:
/// 1px accent border + outer ring + 20px check badge at −6. Hover: lift −2 +
/// shadow 150ms + ⋯ menu fades in. Click → setActiveMode.
private struct ModeCard: View {
    let mode: Mode
    let isActive: Bool
    let isNew: Bool
    let entranceDelay: Double
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var appeared = false

    private var modeColor: Color { Color(hex: mode.colorHex) }
    private var isSuper: Bool { mode.readsSelectedText || mode.readsClipboard }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.icon)
                .font(.system(size: 17))
                .foregroundStyle(modeColor)
                .frame(width: 36, height: 36)
                .background(modeColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mode.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ZWColor.text1)
                        .lineLimit(1)
                    if mode.isBuiltIn {
                        badge("Built-in", background: ZWColor.surface3, foreground: ZWColor.text2)
                    } else {
                        badge("Custom", background: ZWColor.accentBlue.opacity(0.15), foreground: ZWColor.accentBlue)
                    }
                    if isSuper {
                        badge("Super", background: ZWColor.accentPurple.opacity(0.15), foreground: ZWColor.accentPurple)
                    }
                }
                Text(mode.description)
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let index = mode.shortcutIndex {
                KbdChip(text: "⌘\(index)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(ZWColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isActive {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ZWColor.accentBlue, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(ZWColor.accentBlue, lineWidth: 1)
                        .padding(-1.5)
                }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ZWColor.separator, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .topTrailing) {
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(ZWColor.accentBlue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .offset(x: 6, y: -6)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "doc.on.doc", action: onDuplicate)
                if !mode.isBuiltIn {
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hovering ? ZWColor.text1 : ZWColor.text2)
                    .frame(width: 24, height: 24)
                    .background(hovering ? ZWColor.surface3 : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .opacity(hovering ? 1 : 0)
            .padding(6)
        }
        .onHover { hovering = $0 }
        .offset(y: (appeared ? 0 : 16) + (hovering ? -2 : 0))
        .scaleEffect(appeared ? 1 : (isNew ? 0.8 : 1))
        .opacity(appeared ? 1 : 0)
        .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 16, y: 12)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isActive)
        .onAppear {
            // §5.3 grid entrance: y 16→0 + fade, stagger 0.05s, spring 400/30.
            withAnimation(.spring(response: 0.31, dampingFraction: 0.75).delay(entranceDelay)) {
                appeared = true
            }
        }
    }

    /// 10px pill (§6.2 badges).
    private func badge(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background)
            .clipShape(Capsule())
    }
}

/// §6.2 ModeCycleStrip: frosted footer (py 10) with the ⌥⇧K hint and a
/// horizontally scrollable pill carousel; active pill accent-blue/25 + accent
/// ring traveling via matched geometry (SPRING_MICRO).
private struct ModeCycleStrip: View {
    let appState: AppState
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("Try it: hold")
                KbdChip(text: "⌥⇧")
                Text("and tap")
                KbdChip(text: "K")
                Text("to cycle modes")
            }
            .font(.system(size: 12))
            .foregroundStyle(ZWColor.text2)
            .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(appState.modes) { mode in
                        pill(mode)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(ZWColor.surface2.opacity(0.5).background(.ultraThinMaterial))
        .overlay(alignment: .top) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
    }

    private func pill(_ mode: Mode) -> some View {
        let isActive = mode.id == appState.activeMode.id
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                appState.setActiveMode(mode)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: mode.colorHex))
                Text(mode.name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(isActive ? ZWColor.text1 : ZWColor.text2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if isActive {
                    Capsule()
                        .fill(ZWColor.accentBlue.opacity(0.25))
                        .overlay(Capsule().strokeBorder(ZWColor.accentBlue, lineWidth: 1))
                        .matchedGeometryEffect(id: "mode-cycle-highlight", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// §6.2 editor sheet: 560px wide, radius 12, slides from the top over a
/// black/30 scrim (SPRING_SHEET). Left form + 220px live preview pane; Esc
/// cancels; Save is disabled until the name is non-empty.
private struct ModeEditorSheet: View {
    let appState: AppState
    let draft: ModeDraft
    let onCancel: () -> Void
    let onSave: (ModeDraft) -> Void

    @State private var mode: Mode
    @State private var previewText = ""
    @State private var previewFailed = false
    @State private var previewing = false
    @State private var previewTask: Task<Void, Never>?

    private var canSave: Bool {
        !mode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(appState: AppState, draft: ModeDraft, onCancel: @escaping () -> Void, onSave: @escaping (ModeDraft) -> Void) {
        self.appState = appState
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        _mode = State(initialValue: draft.mode)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                sheetHeader
                HStack(spacing: 0) {
                    form
                    Rectangle().fill(ZWColor.separator).frame(width: 1)
                    livePreview
                }
                .frame(minHeight: 400, maxHeight: .infinity)
                footer
            }
            .frame(width: 560)
            .frame(maxHeight: 600)
            .background(ZWColor.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 48, y: 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onExitCommand(perform: onCancel)
        .onDisappear { previewTask?.cancel() }
    }

    /// 40px header: 24px tinted icon tile + title + shortcut kbd (§6.2).
    private var sheetHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: mode.icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: mode.colorHex))
                .frame(width: 24, height: 24)
                .background(Color(hex: mode.colorHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(draft.isNew ? "New Mode" : "Edit “\(draft.mode.name)”")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZWColor.text1)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let index = mode.shortcutIndex {
                Text("⌘\(index)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ZWColor.text3)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nameField
                iconPicker
                instructionsField
                contextSection
                rulesSection
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nameField: some View {
        field("Name") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("My Mode", text: $mode.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
                HStack(spacing: 10) {
                    ForEach(BuiltInModes.colorSwatches, id: \.self) { hex in
                        colorSwatch(hex)
                    }
                }
            }
        }
    }

    /// 20px swatch; selected scales 1.15 with a white ring (§6.2, SPRING_MICRO).
    private func colorSwatch(_ hex: String) -> some View {
        let selected = mode.colorHex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                mode.colorHex = hex
            }
        } label: {
            ZStack {
                Circle().fill(Color(hex: hex))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .overlay {
                if selected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 2)
                        .padding(-3)
                }
            }
            .scaleEffect(selected ? 1.15 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// 8-glyph picker, 32px tiles (§6.2).
    private var iconPicker: some View {
        field("Icon") {
            HStack(spacing: 6) {
                ForEach(BuiltInModes.iconPickerOptions, id: \.self) { icon in
                    let selected = mode.icon == icon
                    Button {
                        mode.icon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(selected ? Color(hex: mode.colorHex) : ZWColor.text2)
                            .frame(width: 32, height: 32)
                            .background(selected ? ZWColor.accentBlue.opacity(0.15) : ZWColor.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? ZWColor.accentBlue : ZWColor.separator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(ZWButtonStyle(hoverScale: 1.06, pressScale: 0.92))
                }
            }
        }
    }

    /// 120px AI Instructions textarea with placeholder (§6.2).
    private var instructionsField: some View {
        field("AI Instructions") {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $mode.instructions)
                        .font(.system(size: 12))
                        .foregroundStyle(ZWColor.text1)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                    if mode.instructions.isEmpty {
                        Text(BuiltInModes.instructionsPlaceholder)
                            .font(.system(size: 12))
                            .foregroundStyle(ZWColor.text3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 120)
                .background(ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
                Text("These instructions shape the final text after transcription.")
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.text3)
            }
        }
    }

    /// §6.2 "Include context": purple uppercase label + Super pill, two switches.
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("INCLUDE CONTEXT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(ZWColor.accentPurple)
                Text("Super")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ZWColor.accentPurple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(ZWColor.accentPurple.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 2)
            Toggle("Read selected text", isOn: $mode.readsSelectedText)
                .toggleStyle(.switch)
                .tint(ZWColor.accentPurple)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text1)
            Toggle("Read clipboard", isOn: $mode.readsClipboard)
                .toggleStyle(.switch)
                .tint(ZWColor.accentPurple)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text1)
        }
        .padding(10)
        .background(ZWColor.surface2.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
    }

    /// §6.2 auto-activation: `When [app chip] [domain] is frontmost` rows.
    private var rulesSection: some View {
        field("Auto-activation") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(mode.autoActivationRules.indices), id: \.self) { index in
                    ruleRow(index)
                        .transition(.opacity.combined(with: .scale(scale: 1, anchor: .top)))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode.autoActivationRules.append(ActivationRule(appName: "Mail", domain: nil))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add rule")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(ZWColor.accentBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if mode.autoActivationRules.isEmpty {
                    Text("e.g. “When Mail is frontmost → activate this mode”.")
                        .font(.system(size: 11))
                        .foregroundStyle(ZWColor.text3)
                }
            }
        }
    }

    private func ruleRow(_ index: Int) -> some View {
        HStack(spacing: 6) {
            Text("When")
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text2)
            Menu {
                ForEach(BuiltInModes.ruleApps, id: \.self) { app in
                    Button(app) { mode.autoActivationRules[index].appName = app }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(mode.autoActivationRules[index].appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ZWColor.text1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ZWColor.text3)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ZWColor.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            if mode.autoActivationRules[index].appName == "Safari" {
                TextField("domain.com", text: Binding(
                    get: { mode.autoActivationRules[index].domain ?? "" },
                    set: { mode.autoActivationRules[index].domain = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(ZWColor.text1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(width: 96)
                .background(ZWColor.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
            }
            Text("is frontmost")
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text2)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = mode.autoActivationRules.remove(at: index)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ZWColor.text3)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(hoverScale: 1, pressScale: 0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ZWColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
    }

    // MARK: Live preview (§6.2: 220px, border-l, surface-2/40)

    private var livePreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.accentPurple)
                Text("LIVE PREVIEW")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(ZWColor.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ZWColor.separator).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    previewBox(label: "BEFORE") {
                        Text(BuiltInModes.newModeSample)
                            .font(.system(size: 12))
                            .foregroundStyle(ZWColor.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    previewBox(label: "AFTER · \(mode.name.isEmpty ? "UNTITLED MODE" : mode.name.uppercased())") {
                        afterContent
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)

            Button(action: runSample) {
                HStack(spacing: 6) {
                    Image(systemName: previewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 9))
                    Text(previewing ? "Stop" : "Sample")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(previewing ? ZWColor.accentRed : ZWColor.accentPurple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background((previewing ? ZWColor.accentRed : ZWColor.accentPurple).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(ZWButtonStyle())
            .padding(12)
            .overlay(alignment: .top) {
                Rectangle().fill(ZWColor.separator).frame(height: 1)
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(ZWColor.surface2.opacity(0.4))
    }

    /// Raw/processed boxes: min-height 64, 12px, surface-1/70 (§6.2).
    private func previewBox<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(ZWColor.text3)
            content()
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .background(ZWColor.surface1.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var afterContent: some View {
        if previewFailed {
            // §8 actionable failure (Apple Intelligence off, no cloud key).
            Text("Requires Apple Intelligence or a cloud key")
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if previewing || !previewText.isEmpty {
            HStack(alignment: .bottom, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if previewing {
                    // Purple caret blink while streaming (§6.2).
                    Rectangle()
                        .fill(ZWColor.accentPurple)
                        .frame(width: 1.5, height: 12)
                        .phaseAnimator([false, true]) { content, phase in
                            content.opacity(phase ? 1 : 0)
                        }
                }
            }
        } else {
            Text("The processed result appears here.")
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Sample": streams `previewMode` over the generic sample; chunks are
    /// cumulative (the box replaces, never appends — architecture §6).
    private func runSample() {
        if previewing {
            previewTask?.cancel()
            previewTask = nil
            previewing = false
            return
        }
        previewText = ""
        previewFailed = false
        previewing = true
        let sampleMode = mode
        previewTask = Task { @MainActor in
            do {
                for try await chunk in appState.previewMode(sampleMode) {
                    try Task.checkCancellation()
                    previewText = chunk
                }
                previewing = false
            } catch {
                guard !Task.isCancelled else { return }
                previewFailed = true
                previewing = false
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .font(.system(size: 13))
                .foregroundStyle(ZWColor.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .buttonStyle(ZWButtonStyle())
            Button {
                onSave(ModeDraft(mode: mode, isNew: draft.isNew))
            } label: {
                Text("Save Mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ZWColor.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(ZWButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
    }

    /// 11px/600 uppercase tracking-0.02em text-3 label (§3.10 group title style).
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(ZWColor.text3)
            content()
        }
    }
}
