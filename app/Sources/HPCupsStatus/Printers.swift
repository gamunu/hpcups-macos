// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Gamunu Balagalla

import Foundation

// MARK: USB device model (pure, so it can be tested with fake devices)

struct USBInterfaceInfo: Equatable, Sendable {
    var number: Int
    var interfaceClass: Int
    var subclass: Int
    var protocolCode: Int

    /// The LEDM channel: vendor class 255, subclass 4, protocol 1.
    var isLEDM: Bool { interfaceClass == 255 && subclass == 4 && protocolCode == 1 }
}

struct USBDeviceInfo: Equatable, Sendable {
    var vendor: Int
    var product: Int
    var serial: String?
    var interfaces: [USBInterfaceInfo]
    var registryID: UInt64 = 0
}

enum LEDMLookup: Equatable, Sendable {
    case notConnected
    case noLEDM(USBDeviceInfo)
    case found(USBDeviceInfo, USBInterfaceInfo)
}

enum LEDMMatch {
    static let hpVendor = 0x03f0

    /// The LEDM interface of a device, the lowest numbered one when there are several.
    static func ledmInterface(of device: USBDeviceInfo) -> USBInterfaceInfo? {
        device.interfaces.filter(\.isLEDM).min { $0.number < $1.number }
    }

    /// Picks the HP device that belongs to a queue. With a serial, only that device matches. Without
    /// one, a lone HP device is taken, because with several there is no way to tell which is meant.
    static func lookup(serial: String?, in devices: [USBDeviceInfo]) -> LEDMLookup {
        let hp = devices.filter { $0.vendor == hpVendor }
        let device: USBDeviceInfo?
        if let serial, !serial.isEmpty {
            device = hp.first { $0.serial == serial }
        } else {
            device = hp.count == 1 ? hp[0] : nil
        }
        guard let device else { return .notConnected }
        guard let iface = ledmInterface(of: device) else { return .noLEDM(device) }
        return .found(device, iface)
    }
}

// MARK: device URI

enum DeviceURI {
    static func isUSB(_ uri: String) -> Bool { uri.lowercased().hasPrefix("usb:") }

    /// The serial in usb://HP/<model>?serial=XXXX, nil when absent or empty.
    static func serial(_ uri: String) -> String? {
        guard isUSB(uri), let c = URLComponents(string: uri) else { return nil }
        let v = c.queryItems?.first(where: { $0.name.lowercased() == "serial" })?.value
        guard let v, !v.isEmpty else { return nil }
        return v
    }

    /// "DeskJet 2300 series" from usb://HP/DeskJet%202300%20series?serial=X (percent-decoded).
    static func model(_ uri: String) -> String? {
        guard isUSB(uri), let c = URLComponents(string: uri) else { return nil }
        let path = c.path.hasPrefix("/") ? String(c.path.dropFirst()) : c.path
        return path.isEmpty ? nil : path
    }
}

// MARK: capabilities

enum AlignmentSupport: String, Equatable, Sendable {
    case automatic, semiAutomatic, manual, none

    init(mode: String?) {
        switch mode?.lowercased() {
        case "automatic": self = .automatic
        case "semiautomatic": self = .semiAutomatic
        case "manual": self = .manual
        default: self = .none
        }
    }

    var summary: String {
        switch self {
        case .automatic: return "automatic"
        case .semiAutomatic: return "semi-automatic (scan the page)"
        case .manual: return "manual (not supported by this app)"
        case .none: return "none reported"
        }
    }
}

/// What one printer can do, read once from /DevMgmt/InternalPrintCap.xml and ConsumableConfigDyn.
struct PrinterCaps: Equatable, Sendable {
    var jobTypes: [String]
    var alignment: AlignmentSupport

    /// Maintenance cards that work on this printer. Manual alignment gets no card.
    var cards: [MaintenanceJob] {
        var out: [MaintenanceJob] = []
        for job in MaintenanceJob.allCases {
            if let jt = job.jobType {
                if jobTypes.contains(jt) { out.append(job) }
            } else if alignment == .automatic || alignment == .semiAutomatic {
                out.append(job)
            }
        }
        return out
    }

    var alignmentNote: String? {
        alignment == .manual ? "This printer uses manual alignment, which this app does not support." : nil
    }

    static func parse(printCap: Data, consumables: Data?) -> PrinterCaps {
        let types = Maintenance.supportedJobTypes(printCap)
        let mode = consumables.flatMap { InkParser.parse($0)?.alignmentMode }
        return PrinterCaps(jobTypes: types, alignment: AlignmentSupport(mode: mode))
    }
}

enum LEDMSupport: Equatable, Sendable {
    case unknown
    case available
    case unavailable(String)

    static let noInkReason = "This printer does not report ink levels over USB"
}

// MARK: queue choice

enum PrinterChoice {
    static func isOurs(_ p: PrinterInfo) -> Bool {
        p.makeAndModel.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix("hpcups-macos")
    }

    static func isHP(_ p: PrinterInfo) -> Bool {
        let m = p.makeAndModel.lowercased()
        return m.hasPrefix("hp ") || m.hasPrefix("hewlett") || p.deviceURI.lowercased().hasPrefix("usb://hp/")
    }

    /// Queues made with this driver, else any HP queue, else every queue.
    static func shown(_ all: [PrinterInfo]) -> [PrinterInfo] {
        let ours = all.filter(isOurs)
        if !ours.isEmpty { return ours }
        let hp = all.filter(isHP)
        return hp.isEmpty ? all : hp
    }

    /// Keeps the remembered queue when it still exists, else the first one. nil when there are none.
    static func resolve(current: String, in list: [PrinterInfo]) -> String? {
        if list.contains(where: { $0.name == current }) { return current }
        return list.first?.name
    }

    /// True or false for a USB queue with a serial, nil when there is nothing to check.
    static func connection(of p: PrinterInfo, connected: Set<String>) -> Bool? {
        guard DeviceURI.isUSB(p.deviceURI), let s = DeviceURI.serial(p.deviceURI) else { return nil }
        return connected.contains(s)
    }
}
