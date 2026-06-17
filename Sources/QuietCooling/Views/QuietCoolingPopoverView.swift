import SwiftUI

struct QuietCoolingPopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            StatusPanel(model: model)

            Picker("Mode", selection: $model.selectedMode) {
                ForEach(CoolingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!model.canAdjustControls && model.selectedMode != .off && model.selectedMode != .system)

            QuietCeilingControl(model: model)

            Picker("Pre-cooling strength", selection: $model.preCoolingStrength) {
                ForEach(PreCoolingStrength.allCases) { strength in
                    Text(strength.title).tag(strength)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!model.canAdjustControls)

            Text("Raises the fan floor only within your quiet range. macOS can still cool normally when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.showingSettings {
                Divider()
                SettingsPanel(model: model)
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quiet Cooling")
                    .font(.headline)
                Text("Keep your Mac cooler before it gets loud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(status: model.status)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                model.showingSettings.toggle()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button(role: .destructive) {
                model.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .font(.caption)
    }
}

private struct StatusPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricRow(label: "Mode", value: model.selectedMode.title, systemImage: "slider.horizontal.3")
            MetricRow(label: "Fan", value: DisplayFormatters.fanRPM(model.fanRPM), systemImage: "fan")
            MetricRow(label: "Temp", value: DisplayFormatters.temperature(model.temperatureC), systemImage: "thermometer.medium")
            MetricRow(label: "Status", value: model.status.displayText, systemImage: "waveform.path.ecg")

            if let hardwareNotice = model.hardwareNotice {
                Label(hardwareNotice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastErrorMessage = model.lastErrorMessage {
                Label(lastErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MetricRow: View {
    var label: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

private struct StatusPill: View {
    var status: CoolingStatus

    var body: some View {
        Text(status.isLimited ? "Limited" : "Safe")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.isLimited ? .orange : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct QuietCeilingControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Quiet ceiling", systemImage: "dial.low")
                Spacer()
                Text(DisplayFormatters.fanRPM(model.quietCeilingRPM))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { Double(model.quietCeilingRPM) },
                    set: { model.quietCeilingRPM = Int(($0 / 50).rounded() * 50) }
                ),
                in: model.quietCeilingRange,
                step: 50
            )
            .disabled(!model.canAdjustControls)

            HStack {
                Text(DisplayFormatters.fanRPM(Int(model.quietCeilingRange.lowerBound)))
                Spacer()
                Text(DisplayFormatters.fanRPM(Int(model.quietCeilingRange.upperBound)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct SettingsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.subheadline.weight(.semibold))

            Picker("Menu bar display", selection: $model.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Show mode indicator in menu bar", isOn: $model.showModeIndicator)
                .toggleStyle(.checkbox)

            HStack {
                Label("Sensor", systemImage: "sensor")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Hottest Mac sensor")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack {
                Spacer()
                Button {
                    model.resetDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .font(.caption)
    }
}
