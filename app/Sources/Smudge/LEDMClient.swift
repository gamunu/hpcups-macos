// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Gamunu Balagalla

import Foundation

struct LEDMResponse {
    var status: Int
    var reason: String
    var headers: [String: String]   // lower-cased names
    var body: Data

    var text: String { String(decoding: body, as: UTF8.self) }
}

/// Minimal HTTP/1.1 reply framing for the printer's LEDM channel.
enum LEDMHTTP {
    /// Returns the parsed response and the number of bytes it used, or nil when
    /// the buffer does not yet hold a complete reply.
    static func parse(_ input: Data) -> (LEDMResponse, Int)? {
        let buf = Data(input)   // zero-based indices
        let crlf = Data("\r\n".utf8)
        let crlf2 = Data("\r\n\r\n".utf8)
        guard let hdrEnd = buf.range(of: crlf2) else { return nil }
        let head = String(decoding: buf[0..<hdrEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst()
        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]) else {
            // Not a status line: junk, skip past this header block.
            return (LEDMResponse(status: -1, reason: "junk", headers: [:], body: Data()), hdrEnd.upperBound)
        }
        var headers: [String: String] = [:]
        for l in lines {
            if let c = l.firstIndex(of: ":") {
                headers[l[..<c].lowercased().trimmingCharacters(in: .whitespaces)] =
                    l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
        }
        var pos = hdrEnd.upperBound
        let reason = parts.count > 2 ? String(parts[2]) : ""
        func make(_ body: Data) -> LEDMResponse {
            LEDMResponse(status: code, reason: reason, headers: headers, body: body)
        }
        if (headers["transfer-encoding"] ?? "").lowercased().contains("chunked") {
            var body = Data()
            while true {
                guard let lineEnd = buf.range(of: crlf, in: pos..<buf.count) else { return nil }
                let sizeStr = String(decoding: buf[pos..<lineEnd.lowerBound], as: UTF8.self)
                    .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                guard let size = Int(sizeStr, radix: 16) else {
                    return (make(body), lineEnd.upperBound)
                }
                pos = lineEnd.upperBound
                if size == 0 {
                    // The last chunk is followed by optional trailers and an empty line.
                    guard let end = buf.range(of: crlf, in: pos..<buf.count) else { return nil }
                    if end.lowerBound == pos { return (make(body), end.upperBound) }
                    guard let fin = buf.range(of: crlf2, in: pos..<buf.count) else { return nil }
                    return (make(body), fin.upperBound)
                }
                guard buf.count - pos >= size + 2 else { return nil }
                body.append(buf[pos..<pos + size])
                pos += size + 2
            }
        }
        if let cl = headers["content-length"], let n = Int(cl) {
            guard buf.count - pos >= n else { return nil }
            return (make(buf[pos..<pos + n]), pos + n)
        }
        // No framing: treat as an empty body.
        return (make(Data()), pos)
    }

    // Request formats copied from HPLIP (base/device.py, base/maint.py).

    static func getRequest(_ path: String) -> Data {
        Data("GET \(path) HTTP/1.1\r\nHost: localhost\r\nAccept: text/plain\r\nUser-Agent: hplip\r\n\r\n".utf8)
    }

    /// PUT in the format HPLIP uses for calibration data (base/maint.py, AlignType16Manual).
    static func putRequest(_ path: String, xml: String) -> Data {
        let body = Data(xml.utf8)
        var req = Data("PUT \(path) HTTP/1.1\r\nHost: localhost\r\nUser-Agent: hp\r\nAccept: text/plain\r\nAccept-Language: en-us,en\r\nAccept-Charset:utf-8\r\nContent-Type: text/xml\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        req.append(body)
        return req
    }

    /// POST in the format of HPLIP's Device.post, used for the InternalPrintDyn job request.
    static func postRequest(_ path: String, xml: String) -> Data {
        let body = Data(xml.utf8)
        var req = Data("POST \(path) HTTP/1.1\r\nConnection: Keep-alive\r\nUser-agent: hplip/2.0\r\nHost: localhost\r\nContent-type: text/xml\r\nContent-length: \(body.count)\r\n\r\n".utf8)
        req.append(body)
        return req
    }

    /// POST in the format of HPLIP's LocalOpenerEWS_LEDM.open_hp footer branch, used for /Calibration/Session.
    static func postFooterRequest(_ path: String, xml: String) -> Data {
        let body = Data(xml.utf8)
        var req = Data("POST \(path) HTTP/1.1\r\nContent-Type:text/xml\r\nContent-Length:\(body.count)\r\nAccept-Encoding: UTF-8\r\nHost:localhost\r\nUser-Agent:hplip\r\n\r\n".utf8)
        req.append(body)
        return req
    }

    /// Local name of the first XML element, namespace prefix removed.
    static func rootElement(_ body: Data) -> String? {
        let s = String(decoding: body.prefix(4096), as: UTF8.self)
        var i = s.startIndex
        while let lt = s[i...].firstIndex(of: "<") {
            let n = s.index(after: lt)
            guard n < s.endIndex else { return nil }
            if s[n] == "?" || s[n] == "!" { i = n; continue }
            var end = n
            while end < s.endIndex, !" \t\r\n/>".contains(s[end]) { end = s.index(after: end) }
            return String(s[n..<end]).split(separator: ":").last.map(String.init)
        }
        return nil
    }
}

/// Collects bytes from the USB channel and hands back the first complete reply
/// that answers the request. Junk, 100 Continue and late replies to earlier
/// requests (wrong XML root) are dropped.
struct LEDMReplyReader {
    var buffer = Data()
    let expectRoot: String?
    var log: ((String) -> Void)?

    init(expectRoot: String?, log: ((String) -> Void)? = nil) {
        self.expectRoot = expectRoot
        self.log = log
    }

    mutating func feed(_ bytes: Data) -> LEDMResponse? {
        buffer.append(bytes)
        while let (resp, used) = LEDMHTTP.parse(buffer) {
            buffer = Data(buffer.dropFirst(used))
            if resp.status < 0 || resp.status == 100 { continue }
            if let want = expectRoot, resp.status == 200 {
                let got = LEDMHTTP.rootElement(resp.body)
                if got != want {
                    log?("ledm: stale reply root \(got ?? "nil"), want \(want)")
                    continue   // late reply to an earlier request; keep reading
                }
            }
            return resp
        }
        return nil
    }
}

/// Talks HTTP to the printer's embedded web server over the LEDM USB
/// interface, the same way HPLIP's EWS_LEDM channel does. One request at a
/// time; each request drains stale bytes first and reads until a full reply
/// whose root element matches the resource arrives.
final class LEDMClient: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ledm.usb", qos: .utility)
    /// USB serial of the printer this client talks to. nil means the only attached HP device.
    let serial: String?

    init(serial: String?) { self.serial = serial }
    var overallTimeout: TimeInterval = 18
    var verbose = false

    // MARK: blocking API (call off the main thread)

    func get(_ path: String, expectRoot: String? = nil) throws -> LEDMResponse {
        try send(LEDMHTTP.getRequest(path), expectRoot: expectRoot ?? Self.defaultRoot(path))
    }

    /// PUT in the format HPLIP uses for calibration data (base/maint.py, AlignType16Manual).
    func put(_ path: String, xml: String) throws -> LEDMResponse {
        try send(LEDMHTTP.putRequest(path, xml: xml), expectRoot: nil, retry: false)
    }

    /// POST in the format of HPLIP's Device.post (base/device.py), used for
    /// the InternalPrintDyn job request.
    func post(_ path: String, xml: String) throws -> LEDMResponse {
        try send(LEDMHTTP.postRequest(path, xml: xml), expectRoot: nil, retry: false)
    }

    /// POST in the format of HPLIP's LocalOpenerEWS_LEDM.open_hp footer branch
    /// (base/device.py), used for /Calibration/Session.
    func postFooter(_ path: String, xml: String) throws -> LEDMResponse {
        try send(LEDMHTTP.postFooterRequest(path, xml: xml), expectRoot: nil, retry: false)
    }

    // MARK: async wrappers (run on the serial LEDM queue)

    func getAsync(_ path: String, expectRoot: String? = nil) async throws -> LEDMResponse {
        try await onQueue { try self.get(path, expectRoot: expectRoot) }
    }
    func postAsync(_ path: String, xml: String) async throws -> LEDMResponse {
        try await onQueue { try self.post(path, xml: xml) }
    }
    func postFooterAsync(_ path: String, xml: String) async throws -> LEDMResponse {
        try await onQueue { try self.postFooter(path, xml: xml) }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try work()) } catch { cont.resume(throwing: error) }
            }
        }
    }

    // MARK: core

    static func defaultRoot(_ path: String) -> String? {
        guard path.hasPrefix("/DevMgmt/"), path.hasSuffix(".xml") else { return nil }
        return String(path.dropLast(4).split(separator: "/").last ?? "")
    }

    private func log(_ s: String) {
        if verbose { FileHandle.standardError.write(Data((s + "\n").utf8)) }
    }

    private func send(_ request: Data, expectRoot: String?, retry: Bool = true) throws -> LEDMResponse {
        lock.lock(); defer { lock.unlock() }
        var lastError: Error = LEDMError.timeout
        for attempt in 0..<(retry ? 2 : 1) {
            do {
                return try attemptOnce(request, expectRoot: expectRoot)
            } catch let e as LEDMError {
                lastError = e
                switch e {
                case .timeout, .badReply: log("ledm attempt \(attempt) failed: \(e)")
                default: throw e
                }
            }
        }
        throw lastError
    }

    private func attemptOnce(_ request: Data, expectRoot: String?) throws -> LEDMResponse {
        let conn = try LEDMUSBConnection(serial: serial)
        conn.drain(quiet: 1.0)
        try conn.write(request)
        let deadline = Date().addingTimeInterval(overallTimeout)
        var reader = LEDMReplyReader(expectRoot: expectRoot) { [self] in log($0) }
        while Date() < deadline {
            if let resp = reader.feed(try conn.read(timeout: 1.0)) { return resp }
        }
        throw LEDMError.timeout
    }
}

/// One client per printer serial. Requests to one printer are serialized by its client;
/// different printers do not wait for each other.
final class LEDMClients: @unchecked Sendable {
    static let shared = LEDMClients()
    private let lock = NSLock()
    private var clients: [String: LEDMClient] = [:]

    private static func key(_ serial: String?) -> String { serial ?? "" }

    func client(for serial: String?) -> LEDMClient {
        lock.lock(); defer { lock.unlock() }
        if let c = clients[Self.key(serial)] { return c }
        let c = LEDMClient(serial: serial)
        clients[Self.key(serial)] = c
        return c
    }

    /// Forgets the client for a printer that was unplugged.
    func drop(_ serial: String?) {
        lock.lock(); defer { lock.unlock() }
        clients[Self.key(serial)] = nil
    }

    func dropAll() {
        lock.lock(); defer { lock.unlock() }
        clients = [:]
    }

    /// Forgets every client except the one for the selected printer.
    func keepOnly(_ serial: String?) {
        lock.lock(); defer { lock.unlock() }
        clients = clients.filter { $0.key == Self.key(serial) }
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return clients.count }
}
