import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case timeout
    case proxy
    case rejected(String)
    case parse(String)
    case usage

    var description: String {
        switch self {
        case .timeout:
            "helper timed out"
        case .proxy:
            "helper proxy unavailable"
        case .rejected(let message):
            message
        case .parse(let message):
            message
        case .usage:
            "usage: helper_write_probe release-all | set-above-current"
        }
    }
}

private func withProxy<T>(
    _ body: (QuietCoolingHelperXPCProtocol, @escaping (Result<T, Error>) -> Void) -> Void
) throws -> T {
    let connection = NSXPCConnection(
        machServiceName: QuietCoolingHelperConstants.machServiceName,
        options: .privileged
    )
    connection.remoteObjectInterface = NSXPCInterface(with: QuietCoolingHelperXPCProtocol.self)

    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: Result<T, Error>?

    func finish(_ newResult: Result<T, Error>) {
        lock.lock()
        if result == nil {
            result = newResult
            semaphore.signal()
        }
        lock.unlock()
    }

    connection.resume()
    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ finish(.failure($0)) }) as? QuietCoolingHelperXPCProtocol else {
        connection.invalidate()
        throw ProbeError.proxy
    }

    body(proxy, finish)

    guard semaphore.wait(timeout: .now() + 2) == .success else {
        connection.invalidate()
        throw ProbeError.timeout
    }

    connection.invalidate()
    return try result!.get()
}

private func listFans() throws -> [HelperFan] {
    try withProxy { proxy, finish in
        proxy.listFans { fans, message in
            if let message {
                finish(.failure(ProbeError.rejected(message as String)))
                return
            }

            finish(.success(fans.compactMap { item -> HelperFan? in
                guard
                    let dictionary = item as? NSDictionary,
                    let id = dictionary["id"] as? String,
                    let name = dictionary["name"] as? String,
                    let minimumRPM = (dictionary["minimumRPM"] as? NSNumber)?.intValue,
                    let maximumRPM = (dictionary["maximumRPM"] as? NSNumber)?.intValue
                else {
                    return nil
                }

                return HelperFan(
                    id: id,
                    name: name,
                    minimumRPM: minimumRPM,
                    maximumRPM: maximumRPM
                )
            }))
        }
    }
}

private func readRPM(fanID: String) throws -> Int {
    try withProxy { proxy, finish in
        proxy.readFanRPM(fanID as NSString) { success, rpm, message in
            if success {
                finish(.success(Int(rpm)))
            } else {
                finish(.failure(ProbeError.rejected(message as String? ?? "read rejected")))
            }
        }
    }
}

private func setRPM(_ rpm: Int, fanID: String) throws -> Int {
    try withProxy { proxy, finish in
        proxy.setMinimumRPM(Int32(rpm), forFanID: fanID as NSString) { success, applied, message in
            if success {
                finish(.success(Int(applied)))
            } else {
                finish(.failure(ProbeError.rejected(message as String? ?? "set rejected")))
            }
        }
    }
}

private func releaseAll() throws {
    try withProxy { proxy, finish in
        proxy.releaseAllFans { success, message in
            if success {
                finish(.success(()))
            } else {
                finish(.failure(ProbeError.rejected(message as String? ?? "release rejected")))
            }
        }
    }
}

private func runSetAboveCurrent() throws {
    let fans = try listFans()
    print("fans=\(fans.count)")
    defer { try? releaseAll() }

    for fan in fans {
        let current = try readRPM(fanID: fan.id)
        let target = min(max(current + 500, fan.minimumRPM), fan.maximumRPM)
        let applied = try setRPM(target, fanID: fan.id)
        print("set \(fan.id) current=\(current) target=\(target) applied=\(applied)")
    }

    Thread.sleep(forTimeInterval: 2)

    for fan in fans {
        print("after \(fan.id)=\(try readRPM(fanID: fan.id))")
    }

    try releaseAll()
    print("released-all")
}

@main
private enum HelperWriteProbe {
    static func main() {
        do {
            switch CommandLine.arguments.dropFirst().first {
            case "release-all":
                try releaseAll()
                print("released-all")
            case "set-above-current":
                try runSetAboveCurrent()
            default:
                throw ProbeError.usage
            }
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
}
