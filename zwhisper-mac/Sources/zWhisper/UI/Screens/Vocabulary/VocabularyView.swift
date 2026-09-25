import SwiftUI

/// §6.5 Vocabulary screen: single scrolling column (px 20, py 16, gap 20) —
/// Custom Words chip field, Text Replacements table, hints demo card. All
/// mutations go through AppState; any vocabulary change raises the §6.5 toast.
struct VocabularyView: View {
    let appState: AppState

    /// SPRING_MICRO from spec §5.1 (spring 500/35).
    static let springMicro = Animation.spring(response: 0.28, dampingFraction: 0.78)
    /// §5.3 height-ease (0.16, 1, 0.3, 1) over 250ms for row insert/remove.
    static let rowEase = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.25)

    @State private var appeared = false
    @State private var toastVisible = false
    @State private var toastGeneration = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    customWordsSection
                        .modifier(SectionEntrance(appeared: appeared, index: 0))
                    replacementsSection
                        .modifier(SectionEntrance(appeared: appeared, index: 1))
                    HintsDemoCard(appState: appState)
                        .modifier(SectionEntrance(appeared: appeared, index: 2))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if toastVisible {
                toast
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .background(ZWColor.surface1)
        .onAppear { appeared = true }
        .onChange(of: appState.vocabulary) { showToast() }
    }

    // MARK: Section 1 — Custom Words (§6.5)

    private var customWordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "Custom Words",
                subtitle: "Names, jargon, and terms the model should always recognize."
            )
            AddWordRow(appState: appState)
            WordChipField(appState: appState)
                .padding(.top, 2)
        }
    }

    // MARK: Section 2 — Text Replacements (§6.5)

    private var replacementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "Text Replacements",
                subtitle: "Automatically swap phrases during processing."
            )
            ReplacementsTable(appState: appState)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(ZWColor.text1)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(ZWColor.text2)
        }
    }

    // MARK: Toast (§6.5: bottom-center pill, 3s)

    private var toast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ZWColor.accentGreen)
                .frame(width: 16, height: 16)
                .background(ZWColor.accentGreen.opacity(0.2), in: Circle())
            Text("Vocabulary updated — applies to your next dictation")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZWColor.text1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(ZWColor.surface3, in: Capsule())
        .overlay(Capsule().strokeBorder(ZWColor.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .padding(.bottom, 16)
        .allowsHitTesting(false)
    }

    private func showToast() {
        toastGeneration += 1
        let generation = toastGeneration
        withAnimation(AppState.springDefault) { toastVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard generation == toastGeneration else { return }
            withAnimation(AppState.springDefault) { toastVisible = false }
        }
    }
}

/// §5.3 Vocabulary sections: y 16→0 + fade, stagger 0.08s, SPRING_DEFAULT.
private struct SectionEntrance: ViewModifier {
    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(AppState.springDefault.delay(Double(index) * 0.08), value: appeared)
    }
}

// MARK: - Add-word input row (§6.5)

/// Input "Add a word…" + accent Add (Enter submits). A duplicate shakes the
/// input x [0,−6,6,−6,6,0] over 300ms and flashes a red ring.
private struct AddWordRow: View {
    let appState: AppState

    @State private var draft = ""
    @State private var shakeTrigger = 0
    @State private var duplicateError = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Add a word…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(ZWColor.text1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ZWColor.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            duplicateError ? ZWColor.accentRed : (focused ? ZWColor.accentBlue : ZWColor.separator),
                            lineWidth: 1
                        )
                )
                .focused($focused)
                .onSubmit(submit)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: shakeTrigger) { content, value in
                    content.offset(x: value)
                } keyframes: { _ in
                    // §6.5 duplicate shake: x [0,−6,6,−6,6,0], 300ms.
                    KeyframeTrack(\.self) {
                        CubicKeyframe(-6, duration: 0.06)
                        CubicKeyframe(6, duration: 0.06)
                        CubicKeyframe(-6, duration: 0.06)
                        CubicKeyframe(6, duration: 0.06)
                        CubicKeyframe(0, duration: 0.06)
                    }
                }

            Button(action: submit) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ZWColor.accentBlue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(ZWButtonStyle())
        }
    }

    private func submit() {
        let word = draft.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        var added = false
        withAnimation(VocabularyView.springMicro) {
            added = appState.addVocabularyWord(word)
        }
        if added {
            draft = ""
            duplicateError = false
        } else {
            shakeTrigger += 1
            duplicateError = true
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                duplicateError = false
            }
        }
    }
}

// MARK: - Chip field (§6.5)

/// Wrapping field of word chips. Initial mount cascades chips at 0.02s stagger
/// (scale 0.8, §5.3); late adds pop scale 0.6→1 with an accent-blue/35 bg
/// flash fading to surface-2 (SPRING_MICRO); removes scale→0.6 fade + reflow.
private struct WordChipField: View {
    let appState: AppState

    @State private var acceptLateAdds = false

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(appState.vocabulary.customWords.enumerated()), id: \.element.id) { index, word in
                WordChip(
                    word: word,
                    lateAdd: acceptLateAdds,
                    cascadeDelay: Double(index) * 0.02
                ) {
                    withAnimation(VocabularyView.springMicro) {
                        appState.removeVocabularyWord(id: word.id)
                    }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            if appState.vocabulary.customWords.isEmpty {
                Text("No custom words yet — add one above.")
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text3)
                    .padding(.vertical, 4)
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                acceptLateAdds = true
            }
        }
    }
}

/// §6.5 chip: 6px-radius pill, 13px/500, hairline; hover reveals a 14px ×
/// button (red tint) and a surface-3 tooltip 28px above.
private struct WordChip: View {
    let word: Word
    /// Inserted after the initial mount cascade — pop + accent bg flash.
    let lateAdd: Bool
    let cascadeDelay: Double
    let onRemove: () -> Void

    @State private var appeared = false
    @State private var flash = false
    @State private var hovering = false
    @State private var removeHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(word.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ZWColor.text1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(removeHovering ? ZWColor.accentRed : ZWColor.text3)
                    .frame(width: 14, height: 14)
                    .background(
                        removeHovering ? ZWColor.accentRed.opacity(0.2) : .clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .onHover { removeHovering = $0 }
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("Remove \(word.text)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(
            flash ? ZWColor.accentBlue.opacity(0.35) : ZWColor.surface2,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(ZWColor.separator, lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : (lateAdd ? 0.6 : 0.8))
        .opacity(appeared ? 1 : 0)
        .overlay(alignment: .top) {
            tooltip
                .offset(y: -28)
                .opacity(hovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: hovering)
                .allowsHitTesting(false)
        }
        .zIndex(hovering ? 1 : 0)
        .onHover { hovering = $0 }
        .onAppear {
            if lateAdd {
                appeared = true
                flash = true
                withAnimation(.easeOut(duration: 0.45).delay(0.25)) { flash = false }
            } else {
                withAnimation(VocabularyView.springMicro.delay(cascadeDelay)) { appeared = true }
            }
        }
    }

    /// §6.5 hover tooltip: "Used N× · last: {when}" ("never" when nil).
    private var tooltip: some View {
        let when = word.lastUsedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "never"
        return Text("Used \(word.useCount)× · last: \(when)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ZWColor.text1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(ZWColor.surface3, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

// MARK: - Text Replacements table (§6.5)

/// Grid 1fr 1fr 36px, surface-2/60 header row, inline-editable cells, hover
/// trash, and an add row (two inputs + Add) whose rows slide in height
/// 0→auto over 250ms (§5.3 row ease).
private struct ReplacementsTable: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            hairline

            ForEach(appState.vocabulary.replacements) { row in
                ReplacementRow(row: row, appState: appState)
                    .transition(.opacity)
                if row.id != appState.vocabulary.replacements.last?.id {
                    hairline
                }
            }

            if appState.vocabulary.replacements.isEmpty {
                Text("No replacements yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            hairline
            AddReplacementRow(appState: appState)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ZWColor.separator, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("WHEN I SAY")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("REPLACE WITH")
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
                .frame(width: 36)
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.2)
        .foregroundStyle(ZWColor.text3)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(ZWColor.surface2.opacity(0.6))
    }

    private var hairline: some View {
        Rectangle().fill(ZWColor.separator).frame(height: 1)
    }
}

private struct ReplacementRow: View {
    let row: Replacement
    let appState: AppState

    @State private var hovering = false
    @State private var trashHovering = false

    var body: some View {
        HStack(spacing: 8) {
            EditableCell(value: row.trigger, placeholder: "When I say…") { newValue in
                var updated = row
                updated.trigger = newValue
                withAnimation(VocabularyView.rowEase) {
                    appState.updateReplacement(updated)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EditableCell(value: row.replacement, placeholder: "Replace with…") { newValue in
                var updated = row
                updated.replacement = newValue
                withAnimation(VocabularyView.rowEase) {
                    appState.updateReplacement(updated)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(VocabularyView.rowEase) {
                    appState.removeReplacement(id: row.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(trashHovering ? ZWColor.accentRed : ZWColor.text3)
                    .frame(width: 28, height: 28)
                    .background(
                        trashHovering ? ZWColor.accentRed.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .onHover { trashHovering = $0 }
            .opacity(hovering ? 1 : 0)
            .frame(width: 36)
            .accessibilityLabel("Delete replacement")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(hovering ? ZWColor.surface2.opacity(0.4) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// §6.5 inline-editable cell: click → input, commit on Enter/blur with a
/// 300ms accent bg flash; Esc cancels.
private struct EditableCell: View {
    let value: String
    let placeholder: String
    let onCommit: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @State private var flash = false
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(ZWColor.surface3.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(ZWColor.accentBlue, lineWidth: 1)
                    )
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
            } else {
                Button {
                    draft = value
                    editing = true
                } label: {
                    Text(value.isEmpty ? placeholder : value)
                        .font(.system(size: 13))
                        .italic(value.isEmpty)
                        .foregroundStyle(value.isEmpty ? ZWColor.text3 : ZWColor.text1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            flash
                ? ZWColor.accentBlue.opacity(0.2)
                : (hovering && !editing ? ZWColor.surface3.opacity(0.5) : .clear),
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.3), value: flash)
    }

    private func commit() {
        guard editing else { return }
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != value else { return }
        onCommit(trimmed)
        flash = true
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            flash = false
        }
    }
}

/// §6.5 add row: two inputs ("my email" → "alex@zwhisper.app") + Add.
private struct AddReplacementRow: View {
    let appState: AppState

    @State private var trigger = ""
    @State private var replacement = ""

    private var canAdd: Bool {
        !trigger.trimmingCharacters(in: .whitespaces).isEmpty
            && !replacement.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            input("my email", text: $trigger)
                .frame(maxWidth: .infinity)
            input("alex@zwhisper.app", text: $replacement)
                .frame(maxWidth: .infinity)

            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        ZWColor.accentBlue.opacity(canAdd ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(ZWButtonStyle())
            .disabled(!canAdd)
            .frame(width: 36)
            .accessibilityLabel("Add replacement")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(ZWColor.text1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ZWColor.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ZWColor.separator, lineWidth: 1)
            )
            .onSubmit(add)
    }

    private func add() {
        guard canAdd else { return }
        withAnimation(VocabularyView.rowEase) {
            appState.addReplacement(
                trigger: trigger.trimmingCharacters(in: .whitespaces),
                replacement: replacement.trimmingCharacters(in: .whitespaces)
            )
        }
        trigger = ""
        replacement = ""
    }
}

// MARK: - Hints demo card (§6.5)

/// §6.5 hints demo: purple 32px icon tile + mini teleprompter (surface-1/60,
/// radius 8) streaming the scripted sentence at 140ms/word. The four vocab
/// words arrive as underlined accent chips (y 6→0, SPRING_MICRO); clicking
/// one pops a "{word} — from your vocabulary" card. Replay restarts the loop.
private struct HintsDemoCard: View {
    let appState: AppState

    private static let tokens = "Hey Aysima, can you send the Terraform plan to Nguyen before we push the GraphQL schema update?"
        .split(separator: " ")
        .map(String.init)
    private static let vocabWords: Set<String> = ["aysima", "terraform", "nguyen", "graphql"]

    @State private var shown = 0
    @State private var runID = 0
    @State private var popped: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 15))
                .foregroundStyle(ZWColor.accentPurple)
                .frame(width: 32, height: 32)
                .background(
                    ZWColor.accentPurple.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary hints")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ZWColor.text1)
                    Text("While dictating, zWhisper shows clickable hints when it detects a custom word.")
                        .font(.system(size: 12))
                        .foregroundStyle(ZWColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                teleprompter

                HStack {
                    poppedCard
                    Spacer(minLength: 8)
                    replayButton
                }
                .frame(minHeight: 28)
            }
        }
        .padding(14)
        .background(ZWColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ZWColor.separator, lineWidth: 1)
        )
        .task(id: runID) { await stream() }
    }

    private var teleprompter: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(Self.tokens.prefix(shown).enumerated()), id: \.offset) { _, token in
                tokenView(token)
            }
            if shown < Self.tokens.count {
                Rectangle()
                    .fill(ZWColor.accentBlue)
                    .frame(width: 1, height: 14)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 0 : 1)
                    } animation: { _ in
                        .linear(duration: 0.5)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 36)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ZWColor.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ZWColor.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tokenView(_ token: String) -> some View {
        if let word = Self.vocabMatch(for: token) {
            let punct = String(token.dropFirst(word.count))
            Button {
                withAnimation(VocabularyView.springMicro) {
                    popped = popped == word ? nil : word
                }
            } label: {
                Text(word + punct)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ZWColor.accentBlue)
                    .underline(true, color: ZWColor.accentBlue)
                    .padding(.horizontal, 4)
                    .background(
                        popped == word ? ZWColor.accentBlue.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .transition(.offset(y: 6).combined(with: .opacity))
        } else {
            Text(token)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ZWColor.text1)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var poppedCard: some View {
        if let word = popped {
            HStack(spacing: 6) {
                Text(word)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ZWColor.text1)
                Text("— from your vocabulary" + usedSuffix(for: word))
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text2)
                Button {
                    withAnimation(VocabularyView.springMicro) { popped = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ZWColor.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss hint")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ZWColor.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ZWColor.separator, lineWidth: 1)
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private var replayButton: some View {
        Button { runID += 1 } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                Text("Replay")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(ZWColor.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ZWColor.surface1, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ZWColor.separator, lineWidth: 1)
            )
        }
        .buttonStyle(ZWButtonStyle())
    }

    /// " · Used N×" when the word exists in the user's vocabulary (§6.5).
    private func usedSuffix(for word: String) -> String {
        guard let match = appState.vocabulary.customWords.first(where: {
            $0.text.localizedCaseInsensitiveCompare(word) == .orderedSame
        }) else { return "" }
        return " · Used \(match.useCount)×"
    }

    private static func vocabMatch(for token: String) -> String? {
        let clean = token.trimmingCharacters(in: .alphanumerics.inverted)
        guard !clean.isEmpty, vocabWords.contains(clean.lowercased()) else { return nil }
        return clean
    }

    private func stream() async {
        shown = 0
        withAnimation(VocabularyView.springMicro) { popped = nil }
        for index in 1...Self.tokens.count {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(VocabularyView.springMicro) { shown = index }
        }
    }
}

// MARK: - Flow layout for chips and teleprompter tokens

/// Left-to-right wrapping layout (chips: §6.5 6px gaps).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layoutRows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func layoutRows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], height: CGFloat)] {
        var rows: [(indices: [Int], height: CGFloat)] = []
        var current: [Int] = []
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, !current.isEmpty {
                rows.append((current, rowHeight))
                current = []
                x = 0
                rowHeight = 0
            }
            current.append(index)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !current.isEmpty { rows.append((current, rowHeight)) }
        return rows
    }
}
