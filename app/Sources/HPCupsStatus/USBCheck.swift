// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Gamunu Balagalla

import Foundation
import IOKit

enum USBCheck {
    /// Pulls the serial out of a usb:// device URI, if present.
    static func serial(fromURI uri: String) -> String? {
        guard uri.hasPrefix("usb:"), let c = URLComponents(string: uri) else { return nil }
        return c.queryItems?.first(where: { $0.name == "serial" })?.value
    }

    /// nil when the URI is not USB (nothing to check).
    static func devicePresent(deviceURI: String) -> Bool? {
        guard deviceURI.hasPrefix("usb:") else { return nil }
        guard let serial = serial(fromURI: deviceURI) else { return nil }
        return connectedSerials().contains(serial)
    }

    static func connectedSerials() -> Set<String> {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOUSBHostDevice"), &iter) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iter) }
        var out = Set<String>()
        while case let e = IOIteratorNext(iter), e != 0 {
            defer { IOObjectRelease(e) }
            if let p = IORegistryEntryCreateCFProperty(e, "USB Serial Number" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let s = p as? String {
                out.insert(s)
            }
        }
        return out
    }
}
