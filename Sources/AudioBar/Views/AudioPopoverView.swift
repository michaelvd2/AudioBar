import AppKit
import AudioBarCore
import SwiftUI

struct AudioPopoverView: View {
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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
        .frame(width: 430)
        .onAppear {
            store.startAutoRefresh()
        }
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
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            if !store.hiddenSources.isEmpty {
                Text("Blacklisted \(store.hiddenSources.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("Hidden sources can be restored above the footer")
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
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

    private let visibleRowLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    content
                },
                label: {
                    HStack {
                        Text("Audio Outputs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(store.processes.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            )
            .disclosureGroupStyle(.automatic)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, isExpanded ? 0 : 10)
        }
        .frame(minHeight: store.processes.isEmpty ? 104 : nil)
    }

    @ViewBuilder
    private var sourceRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(store.processes) { process in
                AudioProcessRow(process: process, store: store)
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
            VStack(spacing: 8) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("No active output")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            if store.processes.count > visibleRowLimit {
                ScrollView {
                    sourceRows
                }
                .frame(maxHeight: 220)
            } else {
                sourceRows
            }
        }
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
                        Text("\(store.hiddenSources.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
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
                        AudioStreamMeter(snapshot: store.eqStreamSnapshot)

                        HStack(alignment: .bottom, spacing: 8) {
                            PreampSlider(store: store)

                            Divider()
                                .frame(height: 118)

                            ForEach(EQBand.classic) { band in
                                EQBandSlider(band: band, store: store)
                            }
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    HStack(spacing: 10) {
                        Label("EQ", systemImage: "slider.vertical.3")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        Toggle("On", isOn: Binding(
                            get: { !store.eqSettings.isBypassed },
                            set: { store.setEQBypassed(!$0) }
                        ))
                        .toggleStyle(.switch)
                        .font(.caption)
                        .frame(width: 76, alignment: .trailing)

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
            )
            .disclosureGroupStyle(.automatic)
            .help(isExpanded ? "Collapse EQ sliders" : "Expand EQ sliders")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

private struct AudioStreamMeter: View {
    let snapshot: SystemAudioStreamSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.isActive ? "waveform" : "waveform.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text(snapshot.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StreamLevelBar(value: snapshot.levelFraction)
                .frame(width: 92, height: 5)
        }
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
    @State private var draftVolume: Double?
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(process.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(process.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var control: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                PlaybackControlButton(process: process, store: store)

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
                .frame(width: 118)
                .help(volumeHelpText)

                Button {
                    store.hideSource(process)
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .help("Hide source")
            }
            .frame(width: 174, height: 18, alignment: .trailing)

            Text(volumeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .center)
                .padding(.trailing, 56)
        }
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

    private var volumeHelpText: String {
        guard process.volumeCapability.isAdjustable else {
            return "macOS does not expose a public per-app volume control for this source"
        }
        return "Set source volume"
    }
}

private struct PlaybackControlButton: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        Button {
            store.togglePlayback(for: process)
        } label: {
            Image(systemName: process.isActiveOutput ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 18)
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
        return process.isActiveOutput ? "Pause source" : "Play source"
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
                    .frame(height: 6)

                Capsule()
                    .fill(.secondary.opacity(isEnabled ? 0.58 : 0.22))
                    .frame(width: max(0, proxy.size.width * fraction), height: 6)

                Circle()
                    .fill(isEnabled ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.42))
                    .frame(width: 18, height: 18)
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
        .frame(height: 18)
        .opacity(isEnabled ? 1 : 0.62)
    }

    private func knobOffset(for width: Double) -> Double {
        let knobWidth = 18.0
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
