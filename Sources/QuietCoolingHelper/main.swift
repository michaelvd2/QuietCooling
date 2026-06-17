import Foundation
import QuietCoolingHelperCore
import QuietCoolingShared

let writer = NoProvenFloorFanWriter.makeDefault()
let service = QuietCoolingHelperService(writer: writer)
let delegate = QuietCoolingHelperListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: QuietCoolingHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
