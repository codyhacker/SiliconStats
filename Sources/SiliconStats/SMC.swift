import Foundation
import IOKit

// Raw SMC data structures matching the kernel driver's expectations
private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let kSMCUserClientOpen: UInt32 = 0
private let kSMCUserClientClose: UInt32 = 1
private let kSMCHandleYPCEvent: UInt32 = 2
private let kSMCReadKey: UInt32 = 5
private let kSMCGetKeyInfo: UInt32 = 9

final class SMC {
    private var connection: io_connect_t = 0
    private var isOpen = false

    func open() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        isOpen = (result == kIOReturnSuccess)
        return isOpen
    }

    func close() {
        if isOpen {
            IOServiceClose(connection)
            isOpen = false
        }
    }

    private static let candidateKeys = [
        "TC0D", "TC0E", "TC0F", "TC0P",           // Intel: die, die2, die3, proximity
        "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0H",   // Apple Silicon: P-core clusters
        "Tp0j", "Tp0r", "Tp0n", "Tp0b", "Tp0f",   // Apple Silicon: E-core clusters
    ]

    private var resolvedKey: String?

    /// Read CPU temperature in Celsius.
    /// On first call, probes all candidate keys and locks onto the best one (highest plausible reading,
    /// which is most likely the CPU die rather than an ambient/proximity sensor).
    func readCPUTemperature() -> Double? {
        if let key = resolvedKey {
            return readTemperature(key: key)
        }

        var bestKey: String?
        var bestTemp: Double = 0

        for key in Self.candidateKeys {
            if let temp = readTemperature(key: key), temp > 20, temp < 110 {
                if temp > bestTemp {
                    bestTemp = temp
                    bestKey = key
                }
            }
        }

        resolvedKey = bestKey
        return bestKey != nil ? bestTemp : nil
    }

    private struct SMCReadResult {
        let dataType: UInt32
        let dataSize: UInt32
        let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    }

    private func readTemperature(key: String) -> Double? {
        guard let result = readSMCKey(key: key), result.dataSize > 0 else { return nil }

        let typeStr = fourCCString(result.dataType)
        switch typeStr {
        case "sp78":
            let raw = Int16(bitPattern: UInt16(result.bytes.0) << 8 | UInt16(result.bytes.1))
            return Double(raw) / 256.0
        case "flt ", "ioft":
            let bits = UInt32(result.bytes.0)
                     | UInt32(result.bytes.1) << 8
                     | UInt32(result.bytes.2) << 16
                     | UInt32(result.bytes.3) << 24
            return Double(Float(bitPattern: bits))
        case "fp88":
            let raw = UInt16(result.bytes.0) << 8 | UInt16(result.bytes.1)
            return Double(raw) / 256.0
        case "ui8 ":
            return Double(result.bytes.0)
        default:
            return nil
        }
    }

    private func readSMCKey(key: String) -> SMCReadResult? {
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = fourCharCode(key)
        inputStruct.data8 = UInt8(kSMCGetKeyInfo)

        guard callSMC(input: &inputStruct, output: &outputStruct) else { return nil }

        let dataType = outputStruct.keyInfo.dataType
        let dataSize = outputStruct.keyInfo.dataSize
        guard dataSize > 0 else { return nil }

        inputStruct.keyInfo.dataSize = dataSize
        inputStruct.data8 = UInt8(kSMCReadKey)

        guard callSMC(input: &inputStruct, output: &outputStruct) else { return nil }

        let b = outputStruct.bytes
        return SMCReadResult(
            dataType: dataType,
            dataSize: dataSize,
            bytes: (b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7)
        )
    }

    private func fourCCString(_ v: UInt32) -> String {
        String([
            Character(UnicodeScalar((v >> 24) & 0xFF)!),
            Character(UnicodeScalar((v >> 16) & 0xFF)!),
            Character(UnicodeScalar((v >> 8) & 0xFF)!),
            Character(UnicodeScalar(v & 0xFF)!),
        ])
    }

    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> Bool {
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(kSMCHandleYPCEvent),
            &input,
            inputSize,
            &output,
            &outputSize
        )
        return result == kIOReturnSuccess
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    deinit { close() }
}
