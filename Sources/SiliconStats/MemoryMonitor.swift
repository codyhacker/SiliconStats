import Foundation
import Darwin

struct MemoryState {
    let usedGB: Double
    let totalGB: Double
    var percentage: Double { (usedGB / totalGB) * 100.0 }
}

final class MemoryMonitor {
    private let totalBytes: UInt64 = {
        var size: size_t = MemoryLayout<UInt64>.size
        var total: UInt64 = 0
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        return total
    }()

    func currentState() -> MemoryState {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            let total = Double(totalBytes) / 1_073_741_824
            return MemoryState(usedGB: 0, totalGB: total)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active   = UInt64(stats.active_count) * pageSize
        let wired    = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        let totalGB = Double(totalBytes) / 1_073_741_824
        let usedGB  = Double(used) / 1_073_741_824

        return MemoryState(usedGB: usedGB, totalGB: totalGB)
    }
}
