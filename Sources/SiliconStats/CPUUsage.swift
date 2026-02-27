import Foundation
import Darwin

final class CPUUsage {
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)

    /// Returns overall CPU usage as a percentage (0–100).
    func currentUsage() -> Double {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return -1 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var totalUser: UInt64 = 0, totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0, totalNice: UInt64 = 0

        for i in 0..<Int(cpuCount) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser   += UInt64(info[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle   += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            totalNice   += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }

        let userDelta   = totalUser   - previousTicks.user
        let systemDelta = totalSystem - previousTicks.system
        let idleDelta   = totalIdle   - previousTicks.idle
        let niceDelta   = totalNice   - previousTicks.nice

        previousTicks = (totalUser, totalSystem, totalIdle, totalNice)

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return 0 }

        let usedDelta = userDelta + systemDelta + niceDelta
        return (Double(usedDelta) / Double(totalDelta)) * 100.0
    }
}
