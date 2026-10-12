import Foundation
import IOKit
import IOKit.ps

/// IORegistry and power-source lookups.
extension KernelReaders {

    /// Reads a string property from an IORegistry path.
    ///
    /// The marketing model name lives at `IODeviceTree:/product`, not on
    /// `IOPlatformExpertDevice` where one would first look for it.
    static func ioRegistryString(path: String, key: String) -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return Self.string(from: entry, key: key)
    }

    /// Reads a string property from an IOService.
    static func ioRegistryString(service: String, key: String) -> String? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(service))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        return Self.string(from: entry, key: key)
    }

    private static func string(from entry: io_registry_entry_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }

        if let data = property as? Data {
            // IORegistry strings arrive NUL-terminated.
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            return text?.isEmpty == false ? text : nil
        }
        if let text = property as? String {
            return text.isEmpty ? nil : text
        }
        return nil
    }

    static func ioRegistryInt(service: String, key: String) -> Int? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(service))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        guard let property = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }

        return (property as? NSNumber)?.intValue
    }

    /// Battery state, or nil on a desktop Mac.
    ///
    /// Charge comes from the power-source API; health and cycle count come from
    /// `AppleSmartBattery` in the IORegistry, which not every machine exposes — each part
    /// degrades on its own rather than losing the whole reading.
    static func batteryInfo() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let charge = maximum > 0 ? Double(current) / Double(maximum) : 0
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            let cycles = ioRegistryInt(service: "AppleSmartBattery", key: "CycleCount") ?? 0
            let health = batteryHealth() ?? 1

            return BatteryInfo(
                charge: charge,
                health: health,
                cycleCount: cycles,
                isCharging: isCharging
            )
        }
        return nil
    }

    /// Maximum capacity relative to design capacity, as 0...1.
    private static func batteryHealth() -> Double? {
        guard let design = ioRegistryInt(service: "AppleSmartBattery", key: "DesignCapacity"),
              design > 0
        else { return nil }

        // Apple silicon reports "AppleRawMaxCapacity"; older machines report "MaxCapacity".
        let maximum = ioRegistryInt(service: "AppleSmartBattery", key: "AppleRawMaxCapacity")
            ?? ioRegistryInt(service: "AppleSmartBattery", key: "MaxCapacity")
        guard let maximum, maximum > 0 else { return nil }

        return min(1, Double(maximum) / Double(design))
    }
}
