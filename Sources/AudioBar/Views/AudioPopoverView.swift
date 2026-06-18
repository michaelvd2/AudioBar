import AppKit
import AudioBarCore
import SwiftUI
import UniformTypeIdentifiers

struct AudioPopoverView: View {
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                header
                CaptureStripView(snapshot: store.eqStreamSnapshot)
            }
            .background(Color.primary.opacity(0.05))
            Divider()
            if store.needsFirstUseSetup {
                FirstUseSetupView(store: store)
                Divider()
            }
            OutputSourceListView(store: store)
            Divider()
            EQPanelView(store: store)
            SourceSettingsView(store: store)
            Divider()
            footer
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("AudioBar")
                    .font(.headline)
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Refresh audio apps")
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if !store.hiddenSources.isEmpty {
                Text("· Hidden \(store.hiddenSources.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("Hidden sources can be restored above the footer")
            }

            Spacer()

            Button {
                store.requestPermissions()
            } label: {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .background(.tertiary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .help("Re-request permissions (Accessibility · Input Monitoring)")

            FooterButton(title: "Restart", help: "Restart AudioBar") {
                restartAudioBar()
            }

            FooterButton(title: "Quit", help: "Quit AudioBar") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footerText: String {
        guard let lastRefreshDate = store.lastRefreshDate else {
            return "Refreshes every 3s"
        }
        return "Updated \(lastRefreshDate.formatted(date: .omitted, time: .shortened))"
    }

    private func restartAudioBar() {
        let bundlePath = Bundle.main.bundleURL.path
        let escapedBundlePath = bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "sleep 0.4; /usr/bin/open -n '\(escapedBundlePath)'"
        ]
        try? task.run()
        NSApp.terminate(nil)
    }
}

private struct FirstUseSetupView: View {
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text("First Use Setup")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Enable System Audio capture, Input Monitoring, and Accessibility prompts before using EQ or web media controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                PermissionPill(title: "System Audio")
                PermissionPill(title: "Input Monitoring")
                PermissionPill(title: "Accessibility")

                Spacer()

                Button("Enable AudioBar") {
                    store.completeFirstUseSetup()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct PermissionPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.tertiary.opacity(0.18), in: Capsule())
    }
}

private struct OutputSourceListView: View {
    @ObservedObject var store: AudioProcessStore
    @State private var isExpanded = true
    @State private var draggingID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Audio Outputs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    CountBadge(count: store.processes.count)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, isExpanded ? 8 : 10)

            if isExpanded {
                Divider()
                content
            }
        }
    }

    @ViewBuilder
    private var sourceRows: some View {
        VStack(spacing: 0) {
            ForEach(store.processes) { process in
                AudioProcessRow(process: process, store: store, draggingID: $draggingID)
                if process.id != store.processes.last?.id {
                    Divider()
                        .padding(.leading, 14)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.processes.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("No active output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            sourceRows
        }
    }
}

private struct SourceReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let store: AudioProcessStore

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else {
            return
        }
        store.moveSource(withID: draggingID, aboveID: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct SourceSettingsView: View {
    @ObservedObject var store: AudioProcessStore
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 10) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text("Launch at Login")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("Launch at Login", isOn: Binding(
                    get: { store.isLaunchAtLoginEnabled },
                    set: { store.setLaunchAtLoginEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .help("Open AudioBar automatically when you sign in")

            if !store.hiddenSources.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(spacing: 0) {
                        ForEach(store.hiddenSources) { source in
                            HStack(spacing: 10) {
                                Text(source.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer()

                                Button("Restore") {
                                    store.restoreHiddenSource(source.id)
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("Hidden Sources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        CountBadge(count: store.hiddenSources.count)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isExpanded.toggle()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
    }
}

private struct EQPanelView: View {
    @ObservedObject var store: AudioProcessStore
    @State private var isExpanded = true
    @State private var isSavingPreset = false
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .top) {
                            EQBaseline()

                            HStack(alignment: .bottom, spacing: 6) {
                                PreampSlider(store: store)

                                Divider()
                                    .frame(height: 118)

                                ForEach(EQBand.classic) { band in
                                    EQBandSlider(band: band, store: store)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                },
                label: {
                    HStack(spacing: 14) {
                        Label("EQ", systemImage: "slider.vertical.3")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        HStack(spacing: 8) {
                            Text(store.eqSettings.isBypassed ? "Off" : "On")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            Toggle("", isOn: Binding(
                                get: { !store.eqSettings.isBypassed },
                                set: { store.setEQBypassed(!$0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }

                        HStack(spacing: 8) {
                            Menu("Preset") {
                                ForEach(EQPreset.allCases, id: \.self) { preset in
                                    Button(preset.rawValue) {
                                        store.applyEQPreset(preset)
                                    }
                                }

                                if !store.savedEQPresets.isEmpty {
                                    Divider()
                                    ForEach(store.savedEQPresets) { preset in
                                        Button(preset.name) {
                                            store.applySavedEQPreset(preset)
                                        }
                                    }
                                }

                                Divider()
                                Button("Save Current...") {
                                    presetName = store.nextSavedEQPresetName()
                                    isSavingPreset = true
                                }
                            }
                            .font(.caption)

                            Button("Reset") {
                                store.resetEQ()
                            }
                            .font(.caption)
                        }
                    }
                    .controlSize(.small)
                }
            )
            .disclosureGroupStyle(.automatic)
            .help(isExpanded ? "Collapse EQ sliders" : "Expand EQ sliders")
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .alert("Save Preset", isPresented: $isSavingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") {
                store.saveCurrentEQPreset(named: presetName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current EQ curve as a preset.")
        }
    }
}

private struct CaptureStripView: View {
    let snapshot: SystemAudioStreamSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.isActive ? "waveform" : "waveform.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(snapshot.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(snapshot.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            StreamLevelBar(value: snapshot.levelFraction)
                .frame(width: 150, height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 11)
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.tertiary.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct MarqueeText: View {
    let text: String
    var isPlaying: Bool = true
    var font: Font = .caption
    var color: Color = .secondary

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animating = false

    var body: some View {
        let overflow = max(0, textWidth - containerWidth)
        GeometryReader { container in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { measure in
                        Color.clear
                            .onAppear {
                                textWidth = measure.size.width
                                containerWidth = container.size.width
                            }
                            .onChange(of: text) { _, _ in
                                textWidth = measure.size.width
                                containerWidth = container.size.width
                            }
                    }
                )
                .offset(x: animating ? -overflow : 0)
                .frame(width: container.size.width, height: container.size.height, alignment: .leading)
                .clipped()
                .animation(
                    overflow > 0
                        ? .linear(duration: max(3, Double(overflow) / 30)).repeatForever(autoreverses: false)
                        : .default,
                    value: animating
                )
        }
        .frame(height: 16)
        .onChange(of: overflow) { _, newValue in
            animating = isPlaying && newValue > 0
        }
        .onChange(of: isPlaying) { _, newValue in
            animating = newValue && overflow > 0
        }
        .onAppear {
            animating = isPlaying && overflow > 0
        }
    }
}

private struct FooterButton: View {
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .background(.tertiary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .help(help)
    }
}

private struct EQBaseline: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 71)
            Rectangle()
                .fill(.secondary.opacity(0.16))
                .frame(height: 1)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

private struct StreamLevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary.opacity(0.28))
                Capsule()
                    .fill(.green.opacity(0.8))
                    .frame(width: proxy.size.width * max(0, min(1, value)))
            }
        }
    }
}

private struct PreampSlider: View {
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        VStack(spacing: 5) {
            Text(valueText(store.eqSettings.preampDB))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(height: 14)

            Slider(
                value: Binding(
                    get: { store.eqSettings.preampDB },
                    set: { store.setEQPreamp($0) }
                ),
                in: EQSettings.gainRange,
                step: 1
            )
            .frame(width: 100, height: 18)
            .rotationEffect(.degrees(-90))
            .frame(width: 26, height: 104)

            Text("Pre")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
    }
}

private struct EQBandSlider: View {
    let band: EQBand
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        let gain = store.eqSettings.gain(for: band.frequencyHz)

        VStack(spacing: 5) {
            Text(valueText(gain))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(height: 14)

            Slider(
                value: Binding(
                    get: { store.eqSettings.gain(for: band.frequencyHz) },
                    set: { store.setEQGain($0, for: band.frequencyHz) }
                ),
                in: EQSettings.gainRange,
                step: 1
            )
            .frame(width: 100, height: 18)
            .rotationEffect(.degrees(-90))
            .frame(width: 26, height: 104)

            Text(band.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 30)
        }
    }
}

private func valueText(_ value: Double) -> String {
    if value > 0 {
        return "+\(Int(value))"
    }
    return "\(Int(value))"
}

private struct AudioProcessRow: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore
    @Binding var draggingID: String?
    @State private var draftVolume: Double?
    @State private var draftBalance: Double?
    @State private var isExpanded = false

    private static let sideMarkerWidth: CGFloat = 12
    private static let sliderTrackWidth: CGFloat = 104
    private static let valueColumnWidth: CGFloat = 34
    private static let rowSpacing: CGFloat = 6
    private static let controlGroupSpacing: CGFloat = 10
    private static var sliderRowWidth: CGFloat {
        sideMarkerWidth * 2 + sliderTrackWidth + valueColumnWidth + rowSpacing * 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if isExpanded {
                expandedControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .help(process.displaySubtitle)
        .contextMenu {
            Button("Hide Source") {
                store.hideSource(process)
            }
        }
        .opacity(draggingID == process.stableSourceID ? 0.5 : 1)
        .onDrop(
            of: [UTType.text],
            delegate: SourceReorderDropDelegate(
                targetID: process.stableSourceID,
                draggingID: $draggingID,
                store: store
            )
        )
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(process.appDisplayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(2)
                .onDrag {
                    draggingID = process.stableSourceID
                    return NSItemProvider(object: process.stableSourceID as NSString)
                }

            if !store.sourceDetail(for: process).isEmpty {
                MarqueeText(text: store.sourceDetail(for: process), isPlaying: store.isPlaybackPlaying(process))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .help(store.sourceDetail(for: process))
                    .offset(y: 2)
            } else {
                Spacer(minLength: 8)
            }

            playbackControls

            VolumeDragBar(
                value: displayedVolume,
                isEnabled: process.volumeCapability.isAdjustable,
                step: 1,
                onPreview: {
                    draftVolume = $0
                    store.previewVolume(for: process, to: $0)
                },
                onCommit: {
                    draftVolume = $0
                    store.setVolume(for: process, to: $0)
                }
            )
            .frame(width: 72)
            .help(volumeHelpText)

            Text(volumeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide stereo and balance" : "Show stereo and balance")
        }
    }

    private var expandedControls: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)

            ChannelModeButton(process: process, store: store)

            BalanceDragBar(
                value: displayedBalance,
                isEnabled: process.volumeCapability.isAdjustable,
                onChange: {
                    draftBalance = $0
                    store.setBalance(for: process, to: $0)
                }
            )
            .frame(width: 72)
            .help("Set left/right balance")

            Text(balanceLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            Color.clear
                .frame(width: 16, height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbackControls: some View {
        HStack(spacing: 2) {
            PreviousTrackButton(process: process, store: store)
            PlaybackControlButton(process: process, store: store)
            NextTrackButton(process: process, store: store)
            RewindPlaybackButton(process: process, store: store)
        }
        .padding(3)
        .background(.tertiary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }

    private var balanceSliderRow: some View {
        HStack(spacing: Self.rowSpacing) {
            Text("L")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: Self.sideMarkerWidth)

            BalanceDragBar(
                value: displayedBalance,
                isEnabled: process.volumeCapability.isAdjustable,
                onChange: {
                    draftBalance = $0
                    store.setBalance(for: process, to: $0)
                }
            )
            .frame(width: Self.sliderTrackWidth)
            .help("Set left/right balance")

            Text("R")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: Self.sideMarkerWidth)

            Text(balanceLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Self.valueColumnWidth, alignment: .leading)
        }
        .frame(width: Self.sliderRowWidth, height: 18, alignment: .trailing)
    }

    private var volumeLabel: String {
        guard process.volumeCapability.isAdjustable else {
            return "view"
        }
        return "\(Int(displayedVolume.rounded()))%"
    }

    private var displayedVolume: Double {
        min(100, max(0, draftVolume ?? Double(process.currentVolume ?? 100)))
    }

    private var displayedBalance: Double {
        min(100, max(-100, draftBalance ?? Double(store.balance(for: process))))
    }

    private var balanceLabel: String {
        let balance = Int(displayedBalance.rounded())
        if balance < 0 {
            return "L\(abs(balance))"
        }
        if balance > 0 {
            return "R\(balance)"
        }
        return "C"
    }

    private var volumeHelpText: String {
        guard process.volumeCapability.isAdjustable else {
            return "macOS does not expose a public per-app volume control for this source"
        }
        return "Set source volume"
    }
}

private struct ChannelModeButton: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

    static let horizontalPadding: CGFloat = 6

    var body: some View {
        Button(store.channelModeLabel(for: process)) {
            store.toggleChannelMode(for: process)
        }
        .buttonStyle(.plain)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 2)
        .background(.tertiary.opacity(0.18), in: Capsule())
        .contentShape(Capsule())
        .fixedSize()
        .help("Toggle mono/stereo for this source")
    }
}

private struct BalanceDragBar: View {
    let value: Double
    let isEnabled: Bool
    let onChange: (Double) -> Void

    private static let centerSnapThreshold = 8.0

    @State private var draftValue: Double?

    private var visibleValue: Double {
        min(100, max(-100, draftValue ?? value))
    }

    var body: some View {
        GeometryReader { proxy in
            let midpoint = proxy.size.width / 2
            let fraction = visibleValue / 100
            let fillWidth = abs(fraction) * midpoint
            let fillOffset = fraction < 0 ? midpoint - fillWidth : midpoint

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary.opacity(isEnabled ? 0.24 : 0.12))
                    .frame(height: 5)

                Capsule()
                    .fill(.secondary.opacity(isEnabled ? 0.5 : 0.2))
                    .frame(width: fillWidth, height: 5)
                    .offset(x: fillOffset)

                Rectangle()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 1, height: 12)
                    .offset(x: midpoint)

                Circle()
                    .fill(isEnabled ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.42))
                    .frame(width: 14, height: 14)
                    .offset(x: knobOffset(for: proxy.size.width))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else {
                            return
                        }
                        let nextValue = snappedValue(for: gesture.location.x, width: proxy.size.width)
                        draftValue = nextValue
                        onChange(nextValue)
                    }
                    .onEnded { gesture in
                        guard isEnabled else {
                            return
                        }
                        let nextValue = snappedValue(for: gesture.location.x, width: proxy.size.width)
                        draftValue = nextValue
                        onChange(nextValue)
                    }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.62)
    }

    private func knobOffset(for width: Double) -> Double {
        let knobWidth = 14.0
        let position = ((visibleValue + 100) / 200) * width
        return max(0, min(width - knobWidth, position - knobWidth / 2))
    }

    private func snappedValue(for locationX: Double, width: Double) -> Double {
        guard width > 0 else {
            return visibleValue
        }
        let fraction = min(1, max(0, locationX / width))
        let snappedValue = ((fraction * 200) - 100).rounded()
        if abs(snappedValue) <= Self.centerSnapThreshold {
            return 0
        }
        return snappedValue
    }
}

private struct PreviousTrackButton: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        Button {
            store.previousTrack(for: process)
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(process.playbackCapability.isControllable ? .secondary : .tertiary)
        .disabled(!process.playbackCapability.isControllable)
        .help("Previous track")
    }
}

private struct PlaybackControlButton: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        Button {
            store.togglePlayback(for: process)
        } label: {
            Image(systemName: store.isPlaybackPlaying(process) ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(process.playbackCapability.isControllable ? .secondary : .tertiary)
        .disabled(!process.playbackCapability.isControllable)
        .help(playbackHelpText)
    }

    private var playbackHelpText: String {
        guard process.playbackCapability.isControllable else {
            return "macOS does not expose playback control for this source"
        }
        return store.isPlaybackPlaying(process) ? "Pause source" : "Play source"
    }
}

private struct NextTrackButton: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        Button {
            store.nextTrack(for: process)
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(process.playbackCapability.isControllable ? .secondary : .tertiary)
        .disabled(!process.playbackCapability.isControllable)
        .help("Next track")
    }
}

private struct RewindPlaybackButton: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        Button {
            store.rewindPlayback(for: process)
        } label: {
            Image(systemName: "gobackward.15")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(process.playbackCapability.isControllable ? .secondary : .tertiary)
        .disabled(!process.playbackCapability.isControllable)
        .help("Rewind 15 seconds")
    }
}

private struct VolumeDragBar: View {
    let value: Double
    let isEnabled: Bool
    let step: Double
    let onPreview: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var draftValue: Double?

    private var visibleValue: Double {
        min(100, max(0, draftValue ?? value))
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = visibleValue / 100

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary.opacity(isEnabled ? 0.28 : 0.14))
                    .frame(height: 5)

                Capsule()
                    .fill(.secondary.opacity(isEnabled ? 0.58 : 0.22))
                    .frame(width: max(0, proxy.size.width * fraction), height: 5)

                Circle()
                    .fill(isEnabled ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.42))
                    .frame(width: 14, height: 14)
                    .offset(x: knobOffset(for: proxy.size.width))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else {
                            return
                        }
                        let previewValue = snappedValue(for: gesture.location.x, width: proxy.size.width)
                        draftValue = previewValue
                        onPreview(previewValue)
                    }
                    .onEnded { gesture in
                        guard isEnabled else {
                            return
                        }
                        let committedValue = snappedValue(for: gesture.location.x, width: proxy.size.width)
                        draftValue = committedValue
                        onCommit(committedValue)
                    }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.62)
    }

    private func knobOffset(for width: Double) -> Double {
        let knobWidth = 14.0
        return max(0, min(width - knobWidth, width * (visibleValue / 100) - knobWidth / 2))
    }

    private func snappedValue(for locationX: Double, width: Double) -> Double {
        guard width > 0 else {
            return visibleValue
        }
        let rawValue = min(100, max(0, (locationX / width) * 100))
        return (rawValue / step).rounded() * step
    }
}
