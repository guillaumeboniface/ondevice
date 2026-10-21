import Foundation
import Darwin

struct TurnMeasurement: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var captureSeconds: Double = 0
    var sttSeconds: Double = 0
    var firstTokenAfterRelease: Double?
    var generationSeconds: Double = 0
    var firstPCMEnqueuedAfterRelease: Double?
    var completedAfterRelease: Double?
    var interrupted = false
    var failure: String?
    var residentBytes: UInt64 = 0
    var peakSampledResidentBytes: UInt64 = 0
    var thermalState = "unknown"
    var batteryLevel: Float = -1
}

struct DiagnosticReport: Encodable {
    let created = Date()
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let coldLoadSeconds: Double?
    let bundledAssetBytes: Int64
    let peakSampledResidentBytes: UInt64
    let turns: [TurnMeasurement]
    let measurementNotes = "Release-to-PCM is a software enqueue measurement. Last-word-to-first-useful-audio, WER, acoustic latency, installed size and energy require the device protocol. Peak RSS is sampled once per second and can miss transients."
}

enum Diagnostics {
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
