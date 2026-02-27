#!/usr/bin/env swift

import Foundation
import IOKit

// --- SMC structures (same as app) ---

struct SMCVersion {
    var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
    var reserved: UInt8 = 0; var release: UInt16 = 0
}
struct SMCPLimitData {
    var version: UInt16 = 0; var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
}
struct SMCKeyInfoData {
    var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
}
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0; var status: UInt8 = 0; var data8: UInt8 = 0; var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

let kSMCHandleYPCEvent: UInt32 = 2
let kSMCReadKey: UInt32 = 5
let kSMCGetKeyInfo: UInt32 = 9

func fourCC(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for c in s.utf8.prefix(4) { r = (r << 8) | UInt32(c) }
    return r
}

func fourCCString(_ v: UInt32) -> String {
    let chars = [
        Character(UnicodeScalar((v >> 24) & 0xFF)!),
        Character(UnicodeScalar((v >> 16) & 0xFF)!),
        Character(UnicodeScalar((v >> 8) & 0xFF)!),
        Character(UnicodeScalar(v & 0xFF)!),
    ]
    return String(chars)
}

// --- Open SMC ---

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0 else { print("ERROR: Cannot find AppleSMC service"); exit(1) }
var conn: io_connect_t = 0
guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("ERROR: Cannot open AppleSMC (try running with sudo)"); exit(1)
}
IOObjectRelease(service)

func readKey(_ key: String) -> (dataType: String, dataSize: UInt32, rawBytes: [UInt8])? {
    var inp = SMCParamStruct()
    var out = SMCParamStruct()
    inp.key = fourCC(key)
    inp.data8 = UInt8(kSMCGetKeyInfo)

    var inSize = MemoryLayout<SMCParamStruct>.stride
    var outSize = MemoryLayout<SMCParamStruct>.stride
    guard IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, &inp, inSize, &out, &outSize) == kIOReturnSuccess else { return nil }

    let dataType = fourCCString(out.keyInfo.dataType)
    let dataSize = out.keyInfo.dataSize

    inp.keyInfo.dataSize = dataSize
    inp.data8 = UInt8(kSMCReadKey)

    inSize = MemoryLayout<SMCParamStruct>.stride
    outSize = MemoryLayout<SMCParamStruct>.stride
    guard IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, &inp, inSize, &out, &outSize) == kIOReturnSuccess else { return nil }

    let b = out.bytes
    let raw = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7]
    return (dataType, dataSize, Array(raw.prefix(Int(dataSize))))
}

func decode(_ dataType: String, _ bytes: [UInt8]) -> String {
    switch dataType {
    case "sp78":
        // signed 7.8 fixed-point
        guard bytes.count >= 2 else { return "?" }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        let val = Double(raw) / 256.0
        return String(format: "%.2f°C", val)
    case "flt ", "ioft":
        // IEEE 754 single-precision float, little-endian on Apple Silicon
        guard bytes.count >= 4 else { return "?" }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let val = Float(bitPattern: bits)
        return String(format: "%.2f°C", val)
    case "fp88":
        // unsigned 8.8 fixed-point
        guard bytes.count >= 2 else { return "?" }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let val = Double(raw) / 256.0
        return String(format: "%.2f°C", val)
    case "ui8 ":
        return "\(bytes[0])°C"
    case "ui16":
        guard bytes.count >= 2 else { return "?" }
        let val = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return "\(val)°C (raw)"
    case "si16":
        guard bytes.count >= 2 else { return "?" }
        let val = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return "\(val)°C (raw)"
    default:
        return "unknown type"
    }
}

// --- Probe all known temperature keys ---

let allKeys: [(key: String, label: String)] = [
    // Intel CPU
    ("TC0D", "Intel CPU Die"),
    ("TC0E", "Intel CPU Die 2"),
    ("TC0F", "Intel CPU Die 3"),
    ("TC0P", "Intel CPU Proximity"),
    ("TC1D", "Intel CPU Core 1 Die"),
    ("TC2D", "Intel CPU Core 2 Die"),
    ("TC3D", "Intel CPU Core 3 Die"),
    ("TC4D", "Intel CPU Core 4 Die"),
    ("TCAD", "Intel CPU Package Die"),
    ("TCXC", "Intel CPU PECI"),
    // Apple Silicon CPU
    ("Tp01", "Apple Silicon CPU Core 1"),
    ("Tp02", "Apple Silicon CPU Core 2"),
    ("Tp03", "Apple Silicon CPU Core 3"),
    ("Tp04", "Apple Silicon CPU Core 4"),
    ("Tp05", "Apple Silicon CPU Core 5"),
    ("Tp06", "Apple Silicon CPU Core 6"),
    ("Tp07", "Apple Silicon CPU Core 7"),
    ("Tp08", "Apple Silicon CPU Core 8"),
    ("Tp09", "Apple Silicon CPU Core 9"),
    ("Tp0D", "Apple Silicon CPU P-cluster 1"),
    ("Tp0H", "Apple Silicon CPU P-cluster 2"),
    ("Tp0b", "Apple Silicon CPU E-cluster 1"),
    ("Tp0f", "Apple Silicon CPU E-cluster 2"),
    ("Tp0j", "Apple Silicon CPU E-cluster 3"),
    ("Tp0n", "Apple Silicon CPU E-cluster 4"),
    ("Tp0r", "Apple Silicon CPU E-cluster 5"),
    // GPU
    ("Tg0D", "GPU Die"),
    ("Tg0P", "GPU Proximity"),
    ("TG0D", "Intel GPU Die"),
    // Other
    ("TA0P", "Ambient"),
    ("Ts0P", "Palm rest"),
    ("Ts1P", "Palm rest 2"),
    ("TH0P", "Heatpipe"),
    ("TB0T", "Battery"),
    ("Tm0P", "Memory Proximity"),
    ("TW0P", "Wireless Module"),
    ("TN0P", "Northbridge Proximity"),
    ("TI0P", "Thunderbolt Proximity"),
    ("Tp0C", "Apple Silicon Power Block"),
    ("Tp0S", "Apple Silicon SOC"),
    ("Tp0z", "Apple Silicon Unknown z"),
]

print("=== SMC Temperature Sensor Diagnostic ===")
print("Key     Description                       Type    Size  Raw Bytes         Decoded")
print(String(repeating: "-", count: 95))

var found = 0
for entry in allKeys {
    guard let result = readKey(entry.key) else { continue }
    found += 1
    let hexBytes = result.rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    let decoded = decode(result.dataType, result.rawBytes)
    let key = entry.key.padding(toLength: 6, withPad: " ", startingAt: 0)
    let label = entry.label.padding(toLength: 32, withPad: " ", startingAt: 0)
    let dtype = result.dataType.padding(toLength: 6, withPad: " ", startingAt: 0)
    let hex = hexBytes.padding(toLength: 16, withPad: " ", startingAt: 0)
    print("\(key)  \(label)  \(dtype)  \(result.dataSize)     \(hex)  \(decoded)")
}

if found == 0 {
    print("No temperature keys found. Try running with: sudo swift diagnose_temps.swift")
}

IOServiceClose(conn)
print("\nDone. \(found) keys responded.")
