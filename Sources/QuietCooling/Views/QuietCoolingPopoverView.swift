import SwiftUI

struct QuietCoolingPopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            StatusPanel(model: model)

            ModeSelector(model: model)

            if model.selectedMode == .manual {
                ManualRPMControl(model: model)
            } else {
                QuietCeilingControl(model: model)

                Picker("Pre-cooling strength", selection: $model.preCoolingStrength) {
                    ForEach(PreCoolingStrength.allCases) { strength in
                        Text(strength.title).tag(strength)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.canAdjustControls)

                if model.preCoolingStrength == .custom {
                    CustomPreCoolingCeilingControl(model: model)
                }

                Text(model.preCoolingStrength == .custom
                    ? "Tracks macOS, then ramps earlier up to your custom ceiling."
                    : "Tracks macOS, then ramps earlier within your quiet range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TemporaryFanTestControl(model: model)

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
            .accessibilityLabel("Launch at login")
            .accessibilityValue(model.launchAtLogin ? "On" : "Off")

            Spacer()

            Button("Settings") {
                model.showingSettings.toggle()
            }
            .accessibilityLabel("Settings")

            Button("Close") {
                model.closeControls()
            }
            .accessibilityLabel("Close controls")

            Button("Quit", role: .destructive) {
                model.quit()
            }
            .accessibilityLabel("Quit")
        }
        .font(.caption)
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
        .accessibilityLabel("Mode")
    }
}

private struct StatusPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricRow(label: "Mode", value: model.selectedMode.title, systemImage: "slider.horizontal.3")
            MetricRow(label: "Actual fan", value: DisplayFormatters.fanRPM(model.fanRPM), systemImage: "fan")
            MetricRow(label: "Temp", value: DisplayFormatters.temperature(model.temperatureC), systemImage: "thermometer.medium")
            MetricRow(label: "Status", value: model.status.displayText, systemImage: "waveform.path.ecg")
            MetricRow(label: "Helper", value: model.helperInstallStatus.displayText, systemImage: "lock.shield")

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
                .frame(width: 72, alignment: .leading)
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
                Text(DisplayFormatters.fanRPM(model.quietCeilingRPMForControls))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { Double(model.quietCeilingRPMForControls) },
                    set: { model.setQuietCeilingRPM(Int(($0 / 50).rounded() * 50)) }
                ),
                in: model.quietCeilingRange,
                step: 50
            )
            .disabled(!model.canAdjustControls)
            .overlay {
                RPMMarkerLine(
                    range: model.quietCeilingRange,
                    markerRPM: model.likelyAudibleQuietCeilingRPM
                )
            }

            HStack {
                Text("Min \(DisplayFormatters.fanRPM(Int(model.quietCeilingRange.lowerBound)))")
                Spacer()
                if model.likelyAudibleQuietCeilingRPM != nil {
                    Text("Likely audible")
                    Spacer()
                }
                Text(DisplayFormatters.fanRPM(Int(model.quietCeilingRange.upperBound)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct ManualRPMControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        RPMControlShell(
            label: "Manual target",
            systemImage: "dial.high",
            value: Double(model.manualTargetRPMForControls),
            range: model.manualRPMRange,
            lowerLabel: "Min \(DisplayFormatters.fanRPM(Int(model.manualRPMRange.lowerBound)))",
            markerRPM: model.currentRPMMarker,
            isEnabled: model.canAdjustControls,
            commitsContinuously: true,
            onCommit: { model.setManualTargetRPM(Int($0)) }
        )
    }
}

private struct CustomPreCoolingCeilingControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        RPMControlShell(
            label: "Custom ceiling",
            systemImage: "dial.medium",
            value: Double(model.customPreCoolingCeilingRPMForControls),
            range: model.customPreCoolingCeilingRange,
            lowerLabel: "Min \(DisplayFormatters.fanRPM(Int(model.customPreCoolingCeilingRange.lowerBound)))",
            markerRPM: model.currentRPMMarker,
            isEnabled: model.canAdjustControls,
            onCommit: { model.setCustomPreCoolingCeilingRPM(Int($0)) }
        )
    }
}

private struct TemporaryFanTestControl: View {
    @ObservedObject var model: AppModel
    @State private var dragBuffer = RPMSliderDragBuffer(value: 0)

    private var externalValue: Double {
        Double(model.temporaryTestRPMForControls)
    }

    private var displayedValue: Double {
        dragBuffer.visibleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(
                    "Test fan RPM",
                    isOn: Binding(
                        get: { model.isTemporaryFanTestActive },
                        set: { model.setTemporaryFanTestActive($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(!model.canAdjustControls)

                Spacer()

                Text(model.isTemporaryFanTestActive
                    ? DisplayFormatters.fanRPM(Int(displayedValue))
                    : "Off")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { dragBuffer.visibleValue },
                    set: { newValue in
                        if !dragBuffer.isEditing {
                            dragBuffer.beginEditing()
                        }
                        dragBuffer.updateDraftValue(newValue)
                        if model.isTemporaryFanTestActive {
                            model.setTemporaryTestRPM(Int(newValue))
                        }
                    }
                ),
                in: model.temporaryTestRPMRange,
                step: 50,
                onEditingChanged: { isEditing in
                    if isEditing {
                        dragBuffer.beginEditing()
                    } else {
                        model.setTemporaryTestRPM(Int(dragBuffer.commitEditing()))
                    }
                }
            )
            .disabled(!model.canAdjustControls || !model.isTemporaryFanTestActive)
            .onAppear {
                dragBuffer.updateExternalValue(externalValue)
            }
            .onChange(of: externalValue) { _, newValue in
                dragBuffer.updateExternalValue(newValue)
            }
            .overlay {
                RPMMarkerLine(
                    range: model.temporaryTestRPMRange,
                    markerRPM: model.temporaryTestRPMMarker
                )
            }

            HStack {
                Text("Min \(DisplayFormatters.fanRPM(Int(model.temporaryTestRPMRange.lowerBound)))")
                Spacer()
                if let markerRPM = model.temporaryTestRPMMarker {
                    Text(DisplayFormatters.macOSBaselineRPM(markerRPM))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Spacer()
                }
                Text(DisplayFormatters.fanRPM(Int(model.temporaryTestRPMRange.upperBound)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if let progressText = model.fanTargetProgressText {
                Text(progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct RPMControlShell: View {
    var label: String
    var systemImage: String
    var value: Double
    var range: ClosedRange<Double>
    var lowerLabel: String
    var markerRPM: Int?
    var isEnabled: Bool
    var commitsContinuously: Bool
    var onCommit: (Double) -> Void
    @State private var dragBuffer: RPMSliderDragBuffer

    init(
        label: String,
        systemImage: String,
        value: Double,
        range: ClosedRange<Double>,
        lowerLabel: String,
        markerRPM: Int?,
        isEnabled: Bool,
        commitsContinuously: Bool = false,
        onCommit: @escaping (Double) -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.value = value
        self.range = range
        self.lowerLabel = lowerLabel
        self.markerRPM = markerRPM
        self.isEnabled = isEnabled
        self.commitsContinuously = commitsContinuously
        self.onCommit = onCommit
        self._dragBuffer = State(initialValue: RPMSliderDragBuffer(value: value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer()
                Text(DisplayFormatters.fanRPM(Int(dragBuffer.visibleValue)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { dragBuffer.visibleValue },
                    set: { newValue in
                        if !dragBuffer.isEditing {
                            dragBuffer.beginEditing()
                        }
                        dragBuffer.updateDraftValue(newValue)
                        if commitsContinuously {
                            onCommit(newValue)
                        }
                    }
                ),
                in: range,
                step: 50,
                onEditingChanged: { isEditing in
                    if isEditing {
                        dragBuffer.beginEditing()
                    } else {
                        onCommit(dragBuffer.commitEditing())
                    }
                }
            )
            .disabled(!isEnabled)
            .onAppear {
                dragBuffer.updateExternalValue(value)
            }
            .onChange(of: value) { _, newValue in
                dragBuffer.updateExternalValue(newValue)
            }
            .overlay {
                RPMMarkerLine(range: range, markerRPM: markerRPM)
            }

            HStack {
                Text(lowerLabel)
                Spacer()
                if let markerRPM {
                    Text(DisplayFormatters.macOSBaselineRPM(markerRPM))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Spacer()
                }
                Text(DisplayFormatters.fanRPM(Int(range.upperBound)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct RPMMarkerLine: View {
    var range: ClosedRange<Double>
    var markerRPM: Int?

    var body: some View {
        GeometryReader { geometry in
            if let markerRPM, range.upperBound > range.lowerBound {
                let normalized = min(
                    max((Double(markerRPM) - range.lowerBound) / (range.upperBound - range.lowerBound), 0),
                    1
                )

                Rectangle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 1, height: 18)
                    .offset(x: normalized * geometry.size.width)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
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
