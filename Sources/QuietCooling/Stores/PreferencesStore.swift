import Foundation

struct UserPreferences: Equatable {
    var selectedMode: CoolingMode
    var quietCeilingRPM: Int
    var preCoolingStrength: PreCoolingStrength
    var launchAtLogin: Bool
    var menuBarDisplayMode: MenuBarDisplayMode
    var showModeIndicator: Bool
    var selectedSensorID: String?

    static let defaults = UserPreferences(
        selectedMode: .preventFanBlast,
        quietCeilingRPM: 2_200,
        preCoolingStrength: .medium,
        launchAtLogin: false,
        menuBarDisplayMode: .iconOnly,
        showModeIndicator: false,
        selectedSensorID: nil
    )
}

final class PreferencesStore {
    private enum Key {
        static let selectedMode = "selectedMode"
        static let quietCeilingRPM = "quietCeilingRPM"
        static let preCoolingStrength = "preCoolingStrength"
        static let launchAtLogin = "launchAtLogin"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let showModeIndicator = "showModeIndicator"
        static let selectedSensorID = "selectedSensorID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            preCoolingStrength: enumValue(
                forKey: Key.preCoolingStrength,
                default: UserPreferences.defaults.preCoolingStrength
            ),
            launchAtLogin: defaults.bool(forKey: Key.launchAtLogin),
            menuBarDisplayMode: enumValue(
                forKey: Key.menuBarDisplayMode,
                default: UserPreferences.defaults.menuBarDisplayMode
            ),
            showModeIndicator: defaults.bool(forKey: Key.showModeIndicator),
            selectedSensorID: defaults.string(forKey: Key.selectedSensorID)
        )
    }

    func save(_ preferences: UserPreferences) {
        defaults.set(preferences.selectedMode.rawValue, forKey: Key.selectedMode)
        defaults.set(preferences.quietCeilingRPM, forKey: Key.quietCeilingRPM)
        defaults.set(preferences.preCoolingStrength.rawValue, forKey: Key.preCoolingStrength)
        defaults.set(preferences.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(preferences.menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode)
        defaults.set(preferences.showModeIndicator, forKey: Key.showModeIndicator)

        if let selectedSensorID = preferences.selectedSensorID {
            defaults.set(selectedSensorID, forKey: Key.selectedSensorID)
        } else {
            defaults.removeObject(forKey: Key.selectedSensorID)
        }
    }

    func reset() {
        save(.defaults)
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
}
