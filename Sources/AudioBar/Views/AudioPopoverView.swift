import AppKit
import AudioBarCore
import SwiftUI

struct AudioPopoverView: View {
    @ObservedObject var store: AudioProcessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360)
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
            ScrollView {
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
            .frame(maxHeight: 360)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

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

private struct AudioProcessRow: View {
    let process: AudioProcess
    @ObservedObject var store: AudioProcessStore

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

                capabilityText
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var capabilityText: some View {
        switch process.volumeCapability {
        case .scripted:
            Text("scripted volume")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .webAppKeyboard:
            Text("web app volume")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .unavailable:
            Text("view only")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch process.volumeCapability {
        case .scripted, .webAppKeyboard:
            VStack(alignment: .trailing, spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(process.currentVolume ?? 50) },
                        set: { store.setVolume(for: process, to: $0) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .frame(width: 118)

                Text(volumeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .help("macOS public APIs do not expose per-app volume for this app")
        }
    }

    private var volumeLabel: String {
        if let currentVolume = process.currentVolume {
            return "\(currentVolume)%"
        }
        return "--%"
    }
}
