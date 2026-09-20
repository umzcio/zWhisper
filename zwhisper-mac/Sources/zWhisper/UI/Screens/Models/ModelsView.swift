import Foundation
import SwiftUI

/// §2.1: accent-orange and the star accent are spec tokens that ZWColor
/// doesn't carry — defined once here per §2.1 (`#FF9F0A` / `#FFD60A`).
private let modelCloudOrange = Color(hex: "FF9F0A")
private let modelStarYellow = Color(hex: "FFD60A")

/// §5.1/§5.3 motion values used on this screen.
private enum ModelsMotion {
    /// SPRING_DEFAULT (400/30): toasts, menus, banners, list rows.
    static let springDefault = Animation.spring(response: 0.31, dampingFraction: 0.75)
    /// SPRING_MICRO (500/35): segmented thumb, check scale-ins, star pop.
    static let springMicro = Animation.spring(response: 0.28, dampingFraction: 0.78)
    /// §5.3 download bar expand: height 0→auto, 250ms, cubic-bezier(0.16,1,0.3,1).
    static let expand = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.25)
    /// §6.4 ActiveBanner model swap crossfade.
    static let bannerSwap = Animation.easeInOut(duration: 0.18)
}

private enum ModelTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case local = "Local"
    case cloud = "Cloud"
    var id: String { rawValue }
}

private enum ModelSort: String, CaseIterable, Identifiable {
    case speed = "Speed"
    case accuracy = "Accuracy"
    case size = "Size"
    var id: String { rawValue }
}

private let modelProviders = ["All providers", "OpenAI", "Anthropic", "Deepgram", "Groq"]

/// §6.4 Models screen, embedded in the management window (M6).
struct ModelsView: View {
    let appState: AppState

    @State private var typeFilter: ModelTypeFilter = .all
    @State private var providerFilter = modelProviders[0]
    @State private var favoritesOnly = false
    @State private var sort: ModelSort = .speed
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    private let listTopAnchor = "models-list-top"

    /// §6.4 ActiveBanner: the local with state .active, else first downloaded,
    /// else first local.
    private var activeEntry: ModelCatalogEntry {
        ModelCatalogEntry.locals.first { appState.modelStates[$0.id] == .active }
            ?? ModelCatalogEntry.locals.first { appState.modelStates[$0.id] == .downloaded }
            ?? ModelCatalogEntry.locals[0]
    }

    private var visibleEntries: [ModelCatalogEntry] {
        let filtered = ModelCatalogEntry.all.filter { entry in
            switch typeFilter {
            case .all: break
            case .local: if entry.isCloud { return false }
            case .cloud: if !entry.isCloud { return false }
            }
            if providerFilter != modelProviders[0], entry.provider != providerFilter { return false }
            if favoritesOnly, !appState.modelPreferences.favoriteIDs.contains(entry.id) { return false }
            return true
        }
        return filtered.sorted { a, b in
            switch sort {
            case .speed: a.speedDots > b.speedDots
            case .accuracy: a.accuracyDots > b.accuracyDots
            case .size: Self.sizeMB(of: a) < Self.sizeMB(of: b)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(
                    onChange: { withAnimation(ModelsMotion.springDefault) { proxy.scrollTo(listTopAnchor, anchor: .top) } }
                )
                modelList
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZWColor.surface1)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ModelsToastPill(message: toastMessage)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Header + banner + filters (§6.4, px 20)

    private func header(onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Models")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(ZWColor.text1)
                Text("Local models run on-device and are unlimited. Cloud models use your own API keys.")
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text2)
            }

            ActiveBanner(entry: activeEntry, onChange: onChange)

            ModelFilterBar(
                typeFilter: $typeFilter,
                providerFilter: $providerFilter,
                favoritesOnly: $favoritesOnly,
                sort: $sort
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Rows (§6.4: 8px gaps, stagger 0.035)

    private var modelList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                Color.clear
                    .frame(height: 0)
                    .id(listTopAnchor)
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    ModelRow(
                        entry: entry,
                        index: index,
                        status: appState.modelStates[entry.id] ?? .none,
                        starred: appState.modelPreferences.favoriteIDs.contains(entry.id),
                        hasAPIKey: entry.provider.map { appState.hasCloudAPIKey(for: appState.cloudAPIKeyAccount(for: $0)) } ?? false,
                        appState: appState,
                        onKeySaved: { showToast("API key saved locally") }
                    )
                }
                if visibleEntries.isEmpty {
                    Text("No models match these filters.")
                        .font(.system(size: 12))
                        .foregroundStyle(ZWColor.text3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 128)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .animation(ModelsMotion.springDefault, value: visibleEntries)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Footer strip (§6.4: frosted, hairline top)

    private var footer: some View {
        HStack {
            Text("Local models run on-device. Audio never leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(ZWColor.text2)
            Spacer()
            Button("Compare models") {
                // §6.4 marks this link decorative.
                showToast("Coming soon")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ZWColor.accentBlue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
    }

    /// §6.4 inline toast pill, bottom-center, 3s.
    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(ModelsMotion.springDefault) { toastMessage = message }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(ModelsMotion.springDefault) { toastMessage = nil }
        }
    }

    /// Download size in MB parsed from the catalog `sizeLabel` (cloud "—" → 0).
    static func sizeMB(of entry: ModelCatalogEntry) -> Double {
        let parts = entry.sizeLabel.split(separator: " ")
        guard let value = parts.first.flatMap({ Double($0) }) else { return 0 }
        return parts.count > 1 && parts[1] == "GB" ? value * 1024 : value
    }

    /// `formatMB` from the prototype's modelsData.
    static func formatMB(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return "\(Int(mb.rounded())) MB"
    }
}

// MARK: - ActiveBanner (§6.4)

private struct ActiveBanner: View {
    let entry: ModelCatalogEntry
    let onChange: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            ModelIconTile(isCloud: entry.isCloud)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ZWColor.text1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(ZWColor.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(ZWColor.separator, lineWidth: 1))
                    Text(entry.engine)
                        .font(.system(size: 12))
                        .foregroundStyle(ZWColor.text2)
                    HStack(spacing: 4) {
                        Circle().fill(ZWColor.accentGreen).frame(width: 6, height: 6)
                        Text("Active")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ZWColor.accentGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(ZWColor.accentGreen.opacity(0.2))
                    .clipShape(Capsule())
                }
                Text(metaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.text3)
            }
            .id(entry.id)
            .transition(.opacity)

            Spacer(minLength: 8)

            Button(action: onChange) {
                HStack(spacing: 4) {
                    Text("Change")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ZWColor.text3)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZWColor.text1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
            }
            .buttonStyle(ZWButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .animation(ModelsMotion.bannerSwap, value: entry.id)
        .onAppear {
            withAnimation(ModelsMotion.springDefault) { appeared = true }
        }
    }

    private var metaLine: String {
        if entry.isCloud {
            return "\(entry.provider ?? entry.engine) cloud · \(entry.priceHint ?? "BYOK")"
        }
        return "On-device · \(entry.sizeLabel) · \(entry.detail)"
    }
}

// MARK: - FilterBar (§6.4)

private struct ModelFilterBar: View {
    @Binding var typeFilter: ModelTypeFilter
    @Binding var providerFilter: String
    @Binding var favoritesOnly: Bool
    @Binding var sort: ModelSort

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 8) {
            // Type segmented control.
            HStack(spacing: 0) {
                ForEach(ModelTypeFilter.allCases) { option in
                    Button {
                        withAnimation(ModelsMotion.springMicro) { typeFilter = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(typeFilter == option ? ZWColor.text1 : ZWColor.text2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background {
                                if typeFilter == option {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(ZWColor.surface3)
                                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                                        .matchedGeometryEffect(id: "thumb", in: thumb)
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

            ModelMiniSelect(value: providerFilter, options: modelProviders) { providerFilter = $0 }

            // Favorites-only star toggle (§6.4: #FFD60A at 10% bg / 30% border when on).
            Button {
                favoritesOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12))
                    Text("Favorites only")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(favoritesOnly ? modelStarYellow : ZWColor.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(favoritesOnly ? modelStarYellow.opacity(0.1) : ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(favoritesOnly ? modelStarYellow.opacity(0.3) : ZWColor.separator, lineWidth: 1)
                )
            }
            .buttonStyle(ZWButtonStyle(hoverScale: 1.0, pressScale: 0.95))

            Spacer(minLength: 0)

            Text("Sort")
                .font(.system(size: 11))
                .foregroundStyle(ZWColor.text3)
            ModelMiniSelect(value: sort.rawValue, options: ModelSort.allCases.map(\.rawValue)) { label in
                if let match = ModelSort.allCases.first(where: { $0.rawValue == label }) {
                    sort = match
                }
            }
        }
    }
}

/// §6.4 ghost button + 10px-radius menu (min-w 128).
private struct ModelMiniSelect: View {
    let value: String
    let options: [String]
    let onChange: (String) -> Void

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Text(value)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ZWColor.text3)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ZWColor.text1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ZWColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.self) { option in
                    MiniSelectRow(
                        label: option,
                        isSelected: option == value,
                        action: {
                            onChange(option)
                            open = false
                        }
                    )
                }
            }
            .padding(4)
            .frame(minWidth: 128)
        }
    }
}

private struct MiniSelectRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ZWColor.accentBlue)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected || hovering ? ZWColor.text1 : ZWColor.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovering ? ZWColor.surface3.opacity(0.6) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Model row (§6.4)

private struct ModelRow: View {
    let entry: ModelCatalogEntry
    let index: Int
    let status: ModelDownloadStatus
    let starred: Bool
    let hasAPIKey: Bool
    let appState: AppState
    let onKeySaved: () -> Void

    @State private var hovering = false
    @State private var appeared = false

    private var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ModelIconTile(isCloud: entry.isCloud)

                // Name 13px/600 + badges + price hint; description 12px text-2.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ZWColor.text1)
                            + Text(" — \(entry.engine)")
                            .font(.system(size: 13))
                            .foregroundStyle(ZWColor.text3)
                        ModelBadge(label: entry.isCloud ? "Cloud" : "Local", color: entry.isCloud ? modelCloudOrange : ZWColor.accentGreen)
                        if let badge = entry.badge {
                            ModelBadge(label: badge, color: badge == "Fastest cloud" ? ZWColor.accentPurple : modelCloudOrange)
                        }
                        if status == .active {
                            ModelBadge(label: "Active", color: ZWColor.accentGreen)
                        }
                        if let priceHint = entry.priceHint {
                            Text(priceHint)
                                .font(.system(size: 11))
                                .foregroundStyle(ZWColor.text3)
                        }
                    }
                    Text(entry.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(ZWColor.text2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // DotMeters in a 118px right column.
                HStack(spacing: 16) {
                    DotMeter(label: "Speed", value: entry.speedDots)
                    DotMeter(label: "Accuracy", value: entry.accuracyDots)
                }
                .frame(width: 118, alignment: .leading)

                ModelStarButton(starred: starred) {
                    appState.toggleModelFavorite(id: entry.id)
                }

                stateControl
                    .frame(width: 118, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 64)

            if case .downloading(let progress, let bytesPerSecond) = status {
                progressRegion(progress: progress, bytesPerSecond: bytesPerSecond)
                    .transition(.opacity)
            }
        }
        .background(ZWColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(ModelsMotion.expand, value: isDownloading)
        .onHover { hovering = $0 }
        .onAppear {
            // §5.3: rows y 12→0, stagger 0.035s.
            withAnimation(ModelsMotion.springDefault.delay(Double(index) * 0.035)) {
                appeared = true
            }
        }
    }

    // MARK: State control (§6.4)

    @ViewBuilder
    private var stateControl: some View {
        if entry.isCloud {
            ApiKeyButton(
                provider: entry.provider ?? entry.engine,
                hasKey: hasAPIKey,
                appState: appState,
                onSaved: onKeySaved
            )
        } else {
            switch status {
            case .none:
                Button {
                    appState.downloadModel(entry.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Download")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZWColor.text1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface3.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
                }
                .buttonStyle(ZWButtonStyle())

            case .queued:
                Text("Queued")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZWColor.text3)

            case .downloading:
                Button("Cancel") {
                    appState.cancelModelDownload(entry.id)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZWColor.accentRed)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(hovering ? ZWColor.accentRed.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(ZWButtonStyle(hoverScale: 1.0, pressScale: 0.97))

            case .downloaded:
                if hovering {
                    HStack(spacing: 4) {
                        Button("Set Active") {
                            appState.setActiveModel(entry.id)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(ZWColor.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(ZWButtonStyle())

                        ModelTrashButton {
                            appState.deleteModelDownload(entry.id)
                        }
                    }
                } else {
                    statusLabel("Downloaded")
                }

            case .active:
                statusLabel("Active")
            }
        }
    }

    /// §6.4: green check (scale 0.5→1) + green text.
    private func statusLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ZWColor.accentGreen)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    // MARK: Progress region (§6.4: row expands 250ms)

    private func progressRegion(progress: Double, bytesPerSecond: Double) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZWColor.surface3)
                    Capsule()
                        .fill(ZWColor.accentBlue)
                        .frame(width: max(4, geometry.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 4)

            HStack {
                let done = ModelsView.formatMB(progress * ModelsView.sizeMB(of: entry))
                Text("\(done) / \(entry.sizeLabel) — \(String(format: "%.0f", bytesPerSecond / 1_000_000)) MB/s")
                    .foregroundStyle(ZWColor.text2)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .foregroundStyle(ZWColor.text3)
            }
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Shared pieces (§6.4)

/// 36px squircle chip: local green/15, cloud orange/15.
private struct ModelIconTile: View {
    let isCloud: Bool

    var body: some View {
        Image(systemName: isCloud ? "cloud" : "cpu")
            .font(.system(size: 17))
            .foregroundStyle(isCloud ? modelCloudOrange : ZWColor.accentGreen)
            .frame(width: 36, height: 36)
            .background((isCloud ? modelCloudOrange : ZWColor.accentGreen).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 10px pill badge ("Fastest cloud" purple, "BYOK" orange, …).
private struct ModelBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// §6.4 DotMeter: label 10px uppercase text-3 + 5 dots (filled accent, empty surface-3).
private struct DotMeter: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(ZWColor.text3)
            HStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { dot in
                    Circle()
                        .fill(dot < value ? ZWColor.accentBlue : ZWColor.surface3)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .help("\(label) \(value)/5")
    }
}

/// §6.4 StarButton: ☆→★, tap scale 0.85, star pop 1.3→1, #FFD60A.
private struct ModelStarButton: View {
    let starred: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var popping = false

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 15))
                .foregroundStyle(starred ? modelStarYellow : (hovering ? ZWColor.text2 : ZWColor.text3))
                .scaleEffect(popping ? 1.3 : 1)
                .frame(width: 28, height: 28)
                .background(hovering ? ZWColor.surface3.opacity(0.7) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(ZWButtonStyle(hoverScale: 1.0, pressScale: 0.85))
        .onHover { hovering = $0 }
        .onChange(of: starred) {
            guard starred else { return }
            popping = true
            withAnimation(ModelsMotion.springMicro) { popping = false }
        }
    }
}

/// Hover-revealed trash on downloaded rows (§6.4).
private struct ModelTrashButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(hovering ? ZWColor.accentRed : ZWColor.text3)
                .frame(width: 28, height: 28)
                .background(hovering ? ZWColor.accentRed.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(ZWButtonStyle(hoverScale: 1.0, pressScale: 0.9))
        .onHover { hovering = $0 }
    }
}

/// §6.4 ApiKeyPopover: gear → masked mono input, Save → Keychain + toast.
/// Green dot while a key is stored.
private struct ApiKeyButton: View {
    let provider: String
    let hasKey: Bool
    let appState: AppState
    let onSaved: () -> Void

    @State private var open = false
    @State private var key = ""
    @State private var hovering = false

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(hovering ? ZWColor.text2 : ZWColor.text3)
                .frame(width: 28, height: 28)
                .background(hovering ? ZWColor.surface3.opacity(0.7) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if hasKey {
                        Circle()
                            .fill(ZWColor.accentGreen)
                            .frame(width: 6, height: 6)
                            .offset(x: -1, y: 1)
                    }
                }
        }
        .buttonStyle(ZWButtonStyle(hoverScale: 1.0, pressScale: 0.9))
        .onHover { hovering = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(provider) API Key".uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(ZWColor.text3)

                SecureField("sk-…••••", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ZWColor.text1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
                    .onSubmit(save)

                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(ZWColor.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .opacity(trimmedKey.isEmpty ? 0.4 : 1)
                }
                .buttonStyle(ZWButtonStyle())
                .disabled(trimmedKey.isEmpty)
                .keyboardShortcut(.defaultAction)

                Text("Stored locally, never uploaded.")
                    .font(.system(size: 10))
                    .foregroundStyle(ZWColor.text3)
            }
            .padding(12)
            .frame(width: 240)
        }
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        appState.saveCloudAPIKey(trimmedKey, for: appState.cloudAPIKeyAccount(for: provider))
        key = ""
        open = false
        onSaved()
    }
}

/// §6.4 inline toast pill (bottom-center, 3s — driven by ModelsView).
private struct ModelsToastPill: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ZWColor.accentGreen)
                .frame(width: 16, height: 16)
                .background(ZWColor.accentGreen.opacity(0.2))
                .clipShape(Circle())
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZWColor.text1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ZWColor.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
