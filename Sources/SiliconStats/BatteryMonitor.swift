import Foundation
import IOKit.ps

struct BatteryState {
    let percentage: Int
    let isCharging: Bool
    let isPluggedIn: Bool
}

final class BatteryMonitor {
    func currentState() -> BatteryState? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else { return nil }

        guard let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
              let isCharging = desc[kIOPSIsChargingKey] as? Bool
        else { return nil }

        let pluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        return BatteryState(percentage: capacity, isCharging: isCharging, isPluggedIn: pluggedIn)
    }
}
