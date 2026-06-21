import SwiftUI

struct QuietCoolingPopoverView: View {
    @ObservedObject var model: AppModel
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero

            if !model.pinnedTelemetry.isEmpty {
                pinnedStrip
            }

            gaugeSection

            StrategySection(model: model)

            if model.nerdModeEnabled {
                NerdPanel(model: model)
            }

            HardCoolControl(model: model)

            if model.showingSettings {
                Divider()
                SettingsPanel(model: model)
            }

            if showDetails {
                Divider()
                DetailsPanel(model: model)
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Label("QuietCooling", systemImage: "wind")
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Spacer()
            QuietStatusPill(status: model.quietStatus)
        }
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            valuePair(value: temperatureText, unit: "°C")
            Divider().frame(height: 28)
            valuePair(value: DisplayFormatters.plainRPM(model.gaugeFanRPM), unit: "rpm")
            Spacer(minLength: 0)
        }
    }

    private func valuePair(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .medium))
                .monospacedDigit()
            Text(unit)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var temperatureText: String {
        guard let temperatureC = model.temperatureC else { return "—" }
        return "\(Int(temperatureC.rounded()))"
    }

    private var pinnedStrip: some View {
        let pinned = model.surfaceTelemetry.filter { model.pinnedTelemetry.contains($0.id) }
        return HStack(spacing: 6) {
            ForEach(pinned, id: \.id) { item in
                HStack(spacing: 5) {
                    Text(item.chip).foregroundStyle(.secondary)
                    Text(item.value).fontWeight(.medium)
                    Button {
                        model.togglePinned(item.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
    }

    private var gaugeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fan speed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.selectedMode == .manual {
                    HStack(spacing: 6) {
                        Text("Manual").foregroundStyle(.orange)
                        Button("Auto") { model.returnToAutoStrategy() }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption)
                } else {
                    Text("Auto").font(.caption).foregroundStyle(.secondary)
                }
            }

            QuietGaugeView(
                range: model.gaugeFanRange,
                fanRPM: model.gaugeFanRPM,
                audibleRPM: model.audibleLineRPM,
                macOSMarkerRPM: model.currentRPMMarker,
                isEnabled: model.canAdjustControls,
                onSetFan: { model.driveFanManually(toRPM: $0) },
                onSetAudible: { model.setAudibleLineRPM($0) }
            )

            HStack {
                Text(DisplayFormatters.plainRPM(model.gaugeFanRange.minimumRPM))
                Spacer()
                Text(DisplayFormatters.plainRPM(model.gaugeFanRange.maximumRPM))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                showDetails.toggle()
            } label: {
                Label("Details", systemImage: showDetails ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.borderless)

            Toggle(isOn: $model.nerdModeEnabled) {
                Label("Nerd mode", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .toggleStyle(.button)
            .controlSize(.small)

            Spacer()

            Button("Settings") { model.showingSettings.toggle() }
                .buttonStyle(.borderless)
            Button("Quit", role: .destructive) { model.quit() }
                .buttonStyle(.borderless)
        }
        .font(.caption)
    }
}

private struct QuietStatusPill: View {
    let status: AppModel.QuietStatus

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }

    private var text: String {
        switch status {
        case .quiet: "Quiet"
        case .audible: "Audible"
        case .limited: "Limited"
        }
    }

    private var icon: String {
        switch status {
        case .quiet: "speaker.wave.1"
        case .audible: "speaker.wave.3"
        case .limited: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch status {
        case .quiet: .green
        case .audible: .orange
        case .limited: .secondary
        }
    }
}

private struct StrategySection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Strategy")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ModeSelector(model: model)
        }
    }
}

private struct ModeSelector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CoolingMode.allCases) { mode in
                let isSelected = model.selectedMode == mode
                Button(mode.selectorTitle) {
                    model.setSelectedMode(mode)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canSelectMode(mode))
                .opacity(model.canSelectMode(mode) ? 1 : 0.42)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 4)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.11) : .clear)
                )
                .accessibilityLabel(mode.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strategy")
    }
}

private struct NerdPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aggressiveness")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(coefficientText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }

            Picker("Aggressiveness", selection: $model.preCoolingStrength) {
                ForEach(PreCoolingStrength.allCases) { strength in
                    Text(strength.title).tag(strength)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!model.canAdjustControls)

            FanResponseCurveView(
                strength: model.preCoolingStrength,
                audibleRPM: model.audibleLineRPM,
                range: model.gaugeFanRange
            )
            .frame(height: 128)

            HStack(spacing: 14) {
                legend(color: .blue, text: "your ramp")
                legend(color: .secondary, text: "macOS")
                legend(color: .orange, text: "audible")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 2)
            Text(text)
        }
    }

    private var coefficientText: String {
        let s = model.preCoolingStrength
        return "floor \(DisplayFormatters.plainRPM(s.floorRPM)) · ×\(String(format: "%.1f", s.gain)) · lead \(s.leadC)°"
    }
}

private struct DetailsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.surfaceTelemetry, id: \.id) { item in
                HStack(spacing: 8) {
                    Button {
                        model.togglePinned(item.id)
                    } label: {
                        Image(systemName: "pin")
                            .foregroundStyle(model.pinnedTelemetry.contains(item.id) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.pinnedTelemetry.contains(item.id) ? "Unpin \(item.label)" : "Pin \(item.label)")

                    Text(item.label).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.value)
                }
                .font(.caption)
            }

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .padding(.top, 2)
        }
    }
}

private struct HardCoolControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    model.setHardCoolActive(!model.isHardCoolActive)
                } label: {
                    Label(
                        model.isHardCoolActive ? "Stop hard cool" : "Hard cool now",
                        systemImage: model.isHardCoolActive ? "stop.circle" : "snowflake"
                    )
                }
                .disabled(!model.canAdjustControls)

                Spacer()

                Text("Until \(model.hardCoolTargetTemperatureC)°C")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(model.hardCoolTargetTemperatureC) },
                    set: { model.setHardCoolTargetTemperatureC(Int($0.rounded())) }
                ),
                in: 35...55,
                step: 1
            )
            .disabled(!model.canAdjustControls)
        }
    }
}

private struct SettingsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.subheadline.weight(.semibold))

            HelperControls(model: model)

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

private struct HelperControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Helper", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.helperInstallStatus.displayText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HStack(spacing: 8) {
                Button {
                    model.installHelper()
                } label: {
                    Label("Install", systemImage: "plus.circle")
                }

                Button {
                    model.refreshHelperInstallStatus()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button(role: .destructive) {
                    model.uninstallHelper()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}
