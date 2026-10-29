// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Gamunu Balagalla
//
// Draws the app icon and writes app/Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift  (from the repo root)

import AppKit
import SwiftUI

struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.42, blue: 0.96),
                                              Color(red: 0.10, green: 0.20, blue: 0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 1024 - 200, height: 1024 - 200)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)

            // Paper coming out of the top, with the three ink colors.
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                    .frame(width: 400, height: 330)
                VStack(spacing: 26) {
                    HStack(spacing: 18) {
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.0, green: 0.68, blue: 0.94))
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.93, green: 0.0, blue: 0.55))
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 1.0, green: 0.85, blue: 0.0))
                    }
                    .frame(width: 300, height: 90)
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.18)).frame(width: 300, height: 18)
                    }
                }
                .padding(.top, 50)
            }
            .offset(y: -150)

            // Printer body.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.84)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 600, height: 260)
                    .overlay(alignment: .bottom) {
                        // Output slot.
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(white: 0.18))
                            .frame(width: 420, height: 46)
                            .padding(.bottom, 44)
                    }
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Color(red: 0.25, green: 0.85, blue: 0.45))
                            .frame(width: 36, height: 36)
                            .padding(.top, 40).padding(.trailing, 56)
                    }
            }
            .offset(y: 120)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render(size: Int) -> Data {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = CGFloat(size) / 1024.0
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
MainActor.assumeIsolated {
    for (name, px) in sizes {
        try! render(size: px).write(to: iconset.appendingPathComponent("\(name).png"))
    }
    try! render(size: 1024).write(to: URL(fileURLWithPath: "docs/images/icon.png"))
}

try fm.createDirectory(atPath: "app/Resources", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "app/Resources/AppIcon.icns"]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote app/Resources/AppIcon.icns" : "iconutil failed")
