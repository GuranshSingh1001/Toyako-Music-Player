import Foundation
import Combine
import Darwin

/// Lightweight process metrics for the Settings diagnostics panel.
/// CPU is calculated from this process' cumulative user + system CPU time;
/// memory uses the process resident footprint reported by Mach.
@MainActor
final class AppPerformanceMonitor: ObservableObject {
    @Published private(set) var memoryBytes: UInt64 = 0
    @Published private(set) var cpuPercent: Double = 0

    private var timer: Timer?
    private var previousCPUSeconds: Double?
    private var previousSampleTime: TimeInterval?

    var memoryDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var cpuDescription: String {
        String(format: "%.1f%%", cpuPercent)
    }

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPUSeconds = nil
        previousSampleTime = nil
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let cpuSeconds = processCPUSeconds()

        if let previousCPUSeconds, let previousSampleTime {
            let elapsed = max(0.001, now - previousSampleTime)
            let used = max(0, cpuSeconds - previousCPUSeconds)
            // 100% represents one fully occupied logical CPU core.
            cpuPercent = min(100 * Double(ProcessInfo.processInfo.activeProcessorCount),
                             (used / elapsed) * 100)
        }

        previousCPUSeconds = cpuSeconds
        previousSampleTime = now
        memoryBytes = processResidentMemory()
    }

    private func processCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return previousCPUSeconds ?? 0 }

        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private func processResidentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    pointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return memoryBytes }
        return UInt64(info.resident_size)
    }
}
