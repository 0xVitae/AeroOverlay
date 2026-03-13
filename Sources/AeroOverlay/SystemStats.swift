import Foundation
import IOKit.ps

struct SystemStats {
    let cpuUsage: Double       // 0-100
    let memUsedGB: Double
    let memTotalGB: Double
    let batteryPercent: Int?   // nil if no battery
    let batteryCharging: Bool

    static func fetch() -> SystemStats {
        return SystemStats(
            cpuUsage: getCPUUsage(),
            memUsedGB: getMemUsed(),
            memTotalGB: getMemTotal(),
            batteryPercent: getBatteryPercent(),
            batteryCharging: isBatteryCharging()
        )
    }

    // MARK: - CPU

    private static var previousInfo: host_cpu_load_info?

    private static func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = Double(cpuInfo.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3)

        if let prev = previousInfo {
            let dUser = user - Double(prev.cpu_ticks.0)
            let dSystem = system - Double(prev.cpu_ticks.1)
            let dIdle = idle - Double(prev.cpu_ticks.2)
            let dNice = nice - Double(prev.cpu_ticks.3)
            let total = dUser + dSystem + dIdle + dNice
            previousInfo = cpuInfo
            return total > 0 ? ((dUser + dSystem + dNice) / total) * 100 : 0
        } else {
            previousInfo = cpuInfo
            let total = user + system + idle + nice
            return total > 0 ? ((user + system + nice) / total) * 100 : 0
        }
    }

    // MARK: - Memory

    private static func getMemTotal() -> Double {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return Double(size) / (1024 * 1024 * 1024)
    }

    private static func getMemUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        return (active + wired + compressed) / (1024 * 1024 * 1024)
    }

    // MARK: - Battery

    private static func getBatteryPercent() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any],
              let capacity = desc[kIOPSCurrentCapacityKey] as? Int else { return nil }
        return capacity
    }

    private static func isBatteryCharging() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any],
              let charging = desc[kIOPSIsChargingKey] as? Bool else { return false }
        return charging
    }
}
