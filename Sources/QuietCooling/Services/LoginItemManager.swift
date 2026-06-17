import Foundation
import ServiceManagement

protocol LoginItemManaging {
    func setLaunchAtLogin(_ enabled: Bool) throws
}

struct LoginItemManager: LoginItemManaging {
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
