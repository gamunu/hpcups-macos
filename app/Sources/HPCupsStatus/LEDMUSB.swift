// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Gamunu Balagalla

import Foundation
import IOKit
import IOUSBHost

enum LEDMError: Error, LocalizedError {
    case deviceNotFound
    case open(String)
    case io(String)
    case timeout
    case badReply(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Printer USB interface not found"
        case .open(let m): return "Cannot open printer USB interface: \(m)"
        case .io(let m): return "USB transfer failed: \(m)"
        case .timeout: return "Printer did not answer in time"
        case .badReply(let m): return "Unexpected printer reply: \(m)"
        case .http(let c, let m): return "Printer returned HTTP \(c) \(m)"
        }
    }
}

/// One claimed LEDM interface (vendor class 255, subclass 4, protocol 1).
/// Uses IOUSBHost, so there is no libusb dependency. Not thread safe on its
/// own: LEDMClient serializes access.
final class LEDMUSBConnection {
    private let interface: IOUSBHostInterface
    private let outPipe: IOUSBHostPipe
    private let inPipe: IOUSBHostPipe
    private let maxPacket: Int

    /// Finds the first 255/4/1 interface of a device with this VID/PID (and
    /// serial, when given) and claims it.
    init(vendor: Int = 0x03f0, product: Int = 0x3654, serial: String? = nil) throws {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOUSBHostInterface"), &iter) == KERN_SUCCESS
        else { throw LEDMError.deviceNotFound }
        defer { IOObjectRelease(iter) }

        var best: (service: io_service_t, number: Int)?
        while case let e = IOIteratorNext(iter), e != 0 {
            func prop(_ k: String, of s: io_service_t) -> Any? {
                IORegistryEntryCreateCFProperty(s, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            var ok = false
            if (prop("bInterfaceClass", of: e) as? Int) == 255,
               (prop("bInterfaceSubClass", of: e) as? Int) == 4,
               (prop("bInterfaceProtocol", of: e) as? Int) == 1,
               let num = prop("bInterfaceNumber", of: e) as? Int {
                var parent: io_registry_entry_t = 0
                if IORegistryEntryGetParentEntry(e, kIOServicePlane, &parent) == KERN_SUCCESS {
                    defer { IOObjectRelease(parent) }
                    let vid = prop("idVendor", of: parent) as? Int
                    let pid = prop("idProduct", of: parent) as? Int
                    let sn = prop("USB Serial Number", of: parent) as? String
                    if vid == vendor, pid == product, serial == nil || sn == serial {
                        if best == nil || num < best!.number {
                            if let b = best { IOObjectRelease(b.service) }
                            IOObjectRetain(e)
                            best = (e, num)
                        }
                        ok = true
                    }
                }
            }
            _ = ok
            IOObjectRelease(e)
        }
        guard let pick = best else { throw LEDMError.deviceNotFound }
        defer { IOObjectRelease(pick.service) }

        do {
            interface = try IOUSBHostInterface(__ioService: pick.service, options: [], queue: nil,
                                               interestHandler: nil)
        } catch {
            throw LEDMError.open(error.localizedDescription)
        }

        // Walk the endpoint descriptors for the bulk pair.
        var outAddr = 0, inAddr = 0, mps = 512
        let ifDesc = interface.interfaceDescriptor
        let cfgDesc = interface.configurationDescriptor
        var ep = IOUSBGetNextEndpointDescriptor(cfgDesc, ifDesc, nil)
        while let d = ep {
            let addr = Int(d.pointee.bEndpointAddress)
            if d.pointee.bmAttributes & 3 == 2 {
                if addr & 0x80 != 0 { if inAddr == 0 { inAddr = addr; mps = Int(d.pointee.wMaxPacketSize) } }
                else if outAddr == 0 { outAddr = addr }
            }
            ep = IOUSBGetNextEndpointDescriptor(cfgDesc, ifDesc, UnsafeRawPointer(d).assumingMemoryBound(to: IOUSBDescriptorHeader.self))
        }
        guard outAddr != 0, inAddr != 0 else { interface.destroy(); throw LEDMError.open("no bulk endpoints") }
        do {
            outPipe = try interface.copyPipe(withAddress: outAddr)
            inPipe = try interface.copyPipe(withAddress: inAddr)
        } catch {
            interface.destroy()
            throw LEDMError.open(error.localizedDescription)
        }
        maxPacket = max(mps, 64)
    }

    deinit { interface.destroy() }

    func write(_ data: Data, timeout: TimeInterval = 5) throws {
        var offset = 0
        while offset < data.count {
            let n = min(16384, data.count - offset)
            let buf = NSMutableData(data: data.subdata(in: offset..<offset + n))
            var sent = 0
            do {
                try outPipe.__sendIORequest(with: buf, bytesTransferred: &sent, completionTimeout: timeout)
            } catch {
                throw LEDMError.io(error.localizedDescription)
            }
            offset += max(sent, 0)
            if sent == 0 { break }
        }
    }

    /// Reads one bulk transfer. Returns empty Data on timeout.
    func read(timeout: TimeInterval) throws -> Data {
        let size = 16384
        let buf = NSMutableData(length: size)!
        var got = 0
        do {
            try inPipe.__sendIORequest(with: buf, bytesTransferred: &got, completionTimeout: timeout)
        } catch {
            let ns = error as NSError
            let code = UInt32(bitPattern: Int32(truncatingIfNeeded: ns.code))
            // kIOReturnTimeout, kIOReturnAborted, kIOUSBTransactionTimeout
            if code == 0xe00002d6 || code == 0xe00002eb || code == 0xe0004051 { return Data() }
            throw LEDMError.io("\(error.localizedDescription) (\(ns.code))")
        }
        return Data(bytes: buf.bytes, count: got)
    }

    /// Throws away anything the printer still has queued from earlier requests.
    func drain(quiet: TimeInterval) {
        while let d = try? read(timeout: quiet), !d.isEmpty {}
    }
}
