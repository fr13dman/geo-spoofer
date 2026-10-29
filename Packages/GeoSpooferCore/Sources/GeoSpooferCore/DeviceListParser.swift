import Foundation

public enum DeviceListParser {
    public static func simulators(from data: Data) throws -> [Device] {
        let root = try jsonObject(data)
        guard let devicesByRuntime = root["devices"] as? [String: Any] else { return [] }
        var devices: [Device] = []
        for value in devicesByRuntime.values {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard let udid = entry["udid"] as? String, let name = entry["name"] as? String else { continue }
                let state = (entry["state"] as? String) ?? ""
                let available = (entry["isAvailable"] as? Bool) ?? true
                guard state == "Booted", available else { continue }
                devices.append(Device(id: udid, name: name, kind: .simulator, connected: true))
            }
        }
        return devices.sorted { $0.name < $1.name }
    }

    public static func phones(from data: Data) throws -> [Device] {
        let root = try jsonObject(data)
        let list = phoneEntries(in: root)
        var devices: [Device] = []
        for entry in list {
            guard let id = phoneID(entry), let name = phoneName(entry) else { continue }
            let platform = phonePlatform(entry)
            if let platform, !platform.localizedCaseInsensitiveContains("ios"), !platform.localizedCaseInsensitiveContains("iphone") {
                continue
            }
            guard phoneIsAvailable(entry) else { continue }
            devices.append(Device(id: id, name: name, kind: .iPhone, connected: true))
        }
        return devices.sorted { $0.name < $1.name }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private static func phoneEntries(in root: [String: Any]) -> [[String: Any]] {
        if let result = root["result"] as? [String: Any], let devices = result["devices"] as? [[String: Any]] {
            return devices
        }
        if let devices = root["devices"] as? [[String: Any]] {
            return devices
        }
        return []
    }

    private static func phoneID(_ entry: [String: Any]) -> String? {
        if let id = entry["identifier"] as? String { return id }
        if let hardware = entry["hardwareProperties"] as? [String: Any], let udid = hardware["udid"] as? String {
            return udid
        }
        if let properties = entry["properties"] as? [String: Any] {
            if let udid = properties["udid"] as? String { return udid }
            if let hardware = properties["hardware"] as? [String: Any], let udid = hardware["udid"] as? String {
                return udid
            }
        }
        return nil
    }

    private static func phoneName(_ entry: [String: Any]) -> String? {
        if let properties = entry["deviceProperties"] as? [String: Any], let name = properties["name"] as? String {
            return name
        }
        if let properties = entry["properties"] as? [String: Any], let name = properties["name"] as? String {
            return name
        }
        return entry["name"] as? String
    }

    private static func phonePlatform(_ entry: [String: Any]) -> String? {
        if let properties = entry["deviceProperties"] as? [String: Any], let platform = properties["platform"] as? String {
            return platform
        }
        if let properties = entry["properties"] as? [String: Any], let platform = properties["platform"] as? String {
            return platform
        }
        return entry["platform"] as? String
    }

    private static func phoneIsAvailable(_ entry: [String: Any]) -> Bool {
        let tokens = visibilityTokens(entry).map { $0.lowercased() }
        if tokens.contains(where: { $0.contains("unavailable") || $0 == "hidden" || $0.contains("disconnected") }) {
            return false
        }
        return true
    }

    private static func visibilityTokens(_ entry: [String: Any]) -> [String] {
        var tokens: [String] = []
        if let value = entry["visibilityClass"] as? String { tokens.append(value) }
        if let value = entry["state"] as? String { tokens.append(value) }
        if let connection = entry["connectionProperties"] as? [String: Any] {
            for key in ["tunnelState", "transportType"] {
                if let value = connection[key] as? String { tokens.append(value) }
            }
        }
        if let properties = entry["properties"] as? [String: Any], let state = properties["state"] as? [String: Any] {
            if let value = state["visibilityClass"] as? String { tokens.append(value) }
        }
        return tokens
    }
}
