import Foundation
import QuietCoolingShared

struct UserPreferences: Equatable {
    var selectedMode: CoolingMode
    var quietCeilingRPM: Int
    var manualTargetRPM: Int
    var customPreCoolingCeilingRPM: Int
    var hardCoolTargetTemperatureC: Int
    var preCoolingStrength: PreCoolingStrength
    var launchAtLogin: Bool
    var selectedSensorID: String?

    static let defaults = UserPreferences(
        selectedMode: .preventFanBlast,
        quietCeilingRPM: 3_000,
        manualTargetRPM: 2_800,
        customPreCoolingCeilingRPM: 3_400,
        hardCoolTargetTemperatureC: 40,
        preCoolingStrength: .medium,
        launchAtLogin: false,
        selectedSensorID: nil
    )
}

final class PreferencesStore {
    private enum Key {
        static let selectedMode = "selectedMode"
        static let quietCeilingRPM = "quietCeilingRPM"
        static let manualTargetRPM = "manualTargetRPM"
        static let customPreCoolingCeilingRPM = "customPreCoolingCeilingRPM"
        static let hardCoolTargetTemperatureC = "hardCoolTargetTemperatureC"
        static let preCoolingStrength = "preCoolingStrength"
        static let launchAtLogin = "launchAtLogin"
        static let selectedSensorID = "selectedSensorID"
    }

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        migrateLegacyPreferencesIfNeeded()
    }

    static func standardStore() -> PreferencesStore {
        PreferencesStore(
            defaults: .standard,
            legacyDefaults: UserDefaults(suiteName: QuietCoolingHelperConstants.legacyAppBundleIdentifier)
        )
    }

    func load() -> UserPreferences {
        UserPreferences(
            selectedMode: enumValue(
                forKey: Key.selectedMode,
                default: UserPreferences.defaults.selectedMode
            ),
            quietCeilingRPM: validQuietCeiling(
                defaults.object(forKey: Key.quietCeilingRPM) as? Int
            ),
            manualTargetRPM: validManualTarget(
                defaults.object(forKey: Key.manualTargetRPM) as? Int
            ),
            customPreCoolingCeilingRPM: validCustomPreCoolingCeiling(
                defaults.object(forKey: Key.customPreCoolingCeilingRPM) as? Int
            ),
            hardCoolTargetTemperatureC: validHardCoolTargetTemperature(
                defaults.object(forKey: Key.hardCoolTargetTemperatureC) as? Int
            ),
            preCoolingStrength: enumValue(
                forKey: Key.preCoolingStrength,
                default: UserPreferences.defaults.preCoolingStrength
            ),
            launchAtLogin: defaults.bool(forKey: Key.launchAtLogin),
            selectedSensorID: defaults.string(forKey: Key.selectedSensorID)
        )
    }

    func save(_ preferences: UserPreferences) {
        defaults.set(preferences.selectedMode.rawValue, forKey: Key.selectedMode)
        defaults.set(preferences.quietCeilingRPM, forKey: Key.quietCeilingRPM)
        defaults.set(preferences.manualTargetRPM, forKey: Key.manualTargetRPM)
        defaults.set(preferences.customPreCoolingCeilingRPM, forKey: Key.customPreCoolingCeilingRPM)
        defaults.set(preferences.hardCoolTargetTemperatureC, forKey: Key.hardCoolTargetTemperatureC)
        defaults.set(preferences.preCoolingStrength.rawValue, forKey: Key.preCoolingStrength)
        defaults.set(preferences.launchAtLogin, forKey: Key.launchAtLogin)

        if let selectedSensorID = preferences.selectedSensorID {
            defaults.set(selectedSensorID, forKey: Key.selectedSensorID)
        } else {
            defaults.removeObject(forKey: Key.selectedSensorID)
        }
    }

    func reset() {
        save(.defaults)
    }

    private func migrateLegacyPreferencesIfNeeded() {
        guard defaults.object(forKey: Key.selectedMode) == nil,
              let legacyDefaults,
              legacyDefaults.object(forKey: Key.selectedMode) != nil
        else {
            return
        }

        for key in [
            Key.selectedMode,
            Key.quietCeilingRPM,
            Key.manualTargetRPM,
            Key.customPreCoolingCeilingRPM,
            Key.hardCoolTargetTemperatureC,
            Key.preCoolingStrength,
            Key.launchAtLogin,
            Key.selectedSensorID
        ] {
            guard let value = legacyDefaults.object(forKey: key) else {
                continue
            }
            defaults.set(value, forKey: key)
        }
    }

    private func enumValue<T: RawRepresentable>(forKey key: String, default fallback: T) -> T
        where T.RawValue == String
    {
        guard let rawValue = defaults.string(forKey: key), let value = T(rawValue: rawValue) else {
            return fallback
        }

        return value
    }

    private func validQuietCeiling(_ storedValue: Int?) -> Int {
        guard let storedValue, storedValue > 0 else {
            return UserPreferences.defaults.quietCeilingRPM
        }

        return storedValue
    }

    private func validManualTarget(_ storedValue: Int?) -> Int {
        guard let storedValue, storedValue > 0 else {
            return UserPreferences.defaults.manualTargetRPM
        }

        return storedValue
    }

    private func validCustomPreCoolingCeiling(_ storedValue: Int?) -> Int {
        guard let storedValue, storedValue > 0 else {
            return UserPreferences.defaults.customPreCoolingCeilingRPM
        }

        return storedValue
    }

    private func validHardCoolTargetTemperature(_ storedValue: Int?) -> Int {
        guard let storedValue, (35...55).contains(storedValue) else {
            return UserPreferences.defaults.hardCoolTargetTemperatureC
        }

        return storedValue
    }
}
