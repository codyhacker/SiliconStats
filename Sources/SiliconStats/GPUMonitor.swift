import Foundation
import IOKit

private let kIOMainPortGPU: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return kIOMasterPortDefault
    }
}()

final class GPUMonitor {
    func currentUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator"),
              IOServiceGetMatchingServices(kIOMainPortGPU, matching, &iterator) == kIOReturnSuccess
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perfStats = dict["PerformanceStatistics"] as? [String: Any]
            else { continue }

            let utilKeys = [
                "Device Utilization %",
                "GPU Activity(%)",
                "GPU Core Utilization",
                "gpuCoreUtilizationPercent",
            ]

            for key in utilKeys {
                if let val = perfStats[key] as? Int, val >= 0, val <= 100 {
                    return Double(val)
                }
                if let val = perfStats[key] as? Double, val >= 0, val <= 100 {
                    return val
                }
            }
        }
        return nil
    }
}
