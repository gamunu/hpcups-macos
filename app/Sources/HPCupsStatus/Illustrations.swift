import SwiftUI

/// Friendly, front-on drawings of an all-in-one inkjet (DeskJet 2300 style). Everything is
/// drawn with shapes and SF Symbols on a 300 x 200 canvas, so it follows light and dark mode
/// and needs no image files.
enum IllustrationScene: Equatable {
    case loadPaper, printing, working, liftLid, placePage, closeLid
    case pressColorCopy, closeDoor, done, cleanContacts
}

/// One picture. The canvas scales to whatever space it gets (3:2).
struct Illustration: View {
    let scene: IllustrationScene
    var animated = true
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let scale = min(g.size.width / 300, g.size.height / 200)
            ZStack {
                Rectangle().fill(Pal(scheme).stage)
                art
                    .animation(animated ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil, value: phase)
                    .frame(width: 300, height: 200)
                    .scaleEffect(scale)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.banner))
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .task {
            // Start after the sheet or window has settled, and keep the animation inside the art.
            guard animated else { return }
            try? await Task.sleep(for: .milliseconds(600))
            phase = 1
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var art: some View {
        switch scene {
        case .loadPaper:
            ZStack {
                PrinterArt()
                SheetStack(count: 3).box(104, 2 + 22 * phase, 92, 54)
                Arrow(symbol: "arrow.down.to.line").at(236, 44 + 5 * phase)
            }
        case .printing:
            PrinterArt(outPage: 0.35 + 0.65 * phase)
        case .working:
            ZStack {
                PrinterArt()
                Image(systemName: "sparkles").font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.yellow).scaleEffect(0.85 + 0.25 * phase).at(238, 44)
            }
        case .liftLid:
            ZStack {
                PrinterArt(lidOpen: true)
                Arrow(symbol: "arrow.up").at(276, 44 - 6 * phase)
            }
        case .placePage:
            GlassTopDown(phase: phase)
        case .closeLid:
            ZStack {
                PrinterArt(lidOpen: true)
                Arrow(symbol: "arrow.down").at(276, 38 + 8 * phase)
            }
        case .pressColorCopy:
            PrinterArt(glow: true, pulse: phase)
        case .closeDoor:
            ZStack {
                PrinterArt(doorOpen: true)
                Arrow(symbol: "arrow.down").at(232, 40 + 8 * phase)
            }
        case .done:
            ZStack {
                PrinterArt()
                ZStack {
                    Circle().fill(Color.green).frame(width: 52, height: 52)
                    Image(systemName: "checkmark").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .scaleEffect(0.94 + 0.06 * phase)
                .at(236, 40)
            }
        case .cleanContacts:
            ContactsArt(phase: phase)
        }
    }
}

// MARK: palette

private struct Pal {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var stage: Color { dark ? Color(white: 0.16) : Color(red: 0.93, green: 0.95, blue: 0.98) }
    var bodyTop: Color { dark ? Color(white: 0.46) : Color(white: 0.97) }
    var bodyBottom: Color { dark ? Color(white: 0.34) : Color(white: 0.82) }
    var lid: Color { dark ? Color(white: 0.40) : Color(white: 0.90) }
    var edge: Color { dark ? Color(white: 0.72) : Color(white: 0.50) }
    var glass: Color { dark ? Color(red: 0.20, green: 0.34, blue: 0.48) : Color(red: 0.62, green: 0.80, blue: 0.92) }
    var recess: Color { dark ? Color(white: 0.08) : Color(white: 0.22) }
    var trayBack: Color { dark ? Color(white: 0.30) : Color(white: 0.76) }
    var line: Color { Color(white: 0.55) }
    var marker: Color { Color.orange }
}

private extension View {
    /// Places a view by its top-left corner and size on the canvas.
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }
    /// Places a view by its center on the canvas.
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { position(x: x, y: y) }
}

// MARK: parts

private struct Arrow: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .heavy))
            .foregroundStyle(Color.accentColor)
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
    }
}

private struct Sheet: View {
    var lines = true
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(Color.white)
            RoundedRectangle(cornerRadius: 2).strokeBorder(Color(white: 0.6), lineWidth: 0.8)
            if lines {
                VStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill(Color(white: 0.8)).frame(height: 2.5)
                            .padding(.trailing, i == 4 ? 30 : 0)
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct SheetStack: View {
    let count: Int
    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Sheet(lines: i == count - 1)
                    .offset(x: CGFloat(i - count + 1) * 2, y: CGFloat(i - count + 1) * 3)
            }
        }
    }
}

/// The printer from the front. Draw order: back tray, raised lid, glass or closed lid, body.
private struct PrinterArt: View {
    @Environment(\.colorScheme) private var scheme
    var lidOpen = false
    var doorOpen = false
    var outPage: CGFloat?
    var glow = false
    var pulse: CGFloat = 0

    var body: some View {
        let p = Pal(scheme)
        ZStack {
            // paper tray at the back
            RoundedRectangle(cornerRadius: 8).fill(p.trayBack).box(96, 16, 108, 58)
            RoundedRectangle(cornerRadius: 8).strokeBorder(p.edge.opacity(0.6), lineWidth: 1).box(96, 16, 108, 58)
            SheetStack(count: 3).box(104, 12, 92, 56)

            if lidOpen {
                // lid standing up at the back, with its hinges
                RoundedRectangle(cornerRadius: 8).fill(p.lid).box(54, 2, 192, 46)
                RoundedRectangle(cornerRadius: 8).strokeBorder(p.edge, lineWidth: 1.2).box(54, 2, 192, 46)
                RoundedRectangle(cornerRadius: 5).fill(p.bodyBottom).box(62, 10, 176, 30)
                Rectangle().fill(p.recess).box(80, 46, 18, 16)
                Rectangle().fill(p.recess).box(202, 46, 18, 16)
                // scanner glass seen at an angle
                glassShape.fill(p.glass)
                glassShape.stroke(p.edge, lineWidth: 1.5)
                CornerMarker().fill(p.marker).box(68, 64, 18, 14)
            }

            // body
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [p.bodyTop, p.bodyBottom], startPoint: .top, endPoint: .bottom))
                .box(26, 92, 248, 82)
            RoundedRectangle(cornerRadius: 16).strokeBorder(p.edge, lineWidth: 1.4).box(26, 92, 248, 82)

            if !lidOpen {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [p.bodyTop, p.lid], startPoint: .top, endPoint: .bottom))
                    .box(38, 56, 224, 40)
                RoundedRectangle(cornerRadius: 10).strokeBorder(p.edge, lineWidth: 1.4).box(38, 56, 224, 40)
                Capsule().fill(Color.white.opacity(p.dark ? 0.25 : 0.7)).box(54, 62, 192, 3)
            }

            door(p)

            // output slot and front tray
            RoundedRectangle(cornerRadius: 6).fill(p.recess).box(62, 132, 148, 24)
            RoundedRectangle(cornerRadius: 5).fill(p.trayBack).box(56, 154, 160, 16)
            RoundedRectangle(cornerRadius: 5).strokeBorder(p.edge, lineWidth: 1).box(56, 154, 160, 16)
            if let out = outPage {
                let h = 14 + 30 * out
                ZStack(alignment: .top) {
                    Sheet()
                    HStack(spacing: 4) {
                        Circle().fill(inkCyan); Circle().fill(inkMagenta); Circle().fill(inkYellow)
                    }
                    .frame(height: 5).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10)
                    .padding(.top, 38)
                }
                .frame(width: 100, height: 60)
                .mask(alignment: .top) { Rectangle().frame(height: h) }
                .box(86, 140, 100, 60)
            }

            controls(p)
        }
        .offset(y: 12)
    }

    private var glassShape: Path {
        Path { path in
            path.move(to: CGPoint(x: 66, y: 62))
            path.addLine(to: CGPoint(x: 234, y: 62))
            path.addLine(to: CGPoint(x: 258, y: 96))
            path.addLine(to: CGPoint(x: 42, y: 96))
            path.closeSubpath()
        }
    }

    @ViewBuilder private func door(_ p: Pal) -> some View {
        if doorOpen {
            RoundedRectangle(cornerRadius: 6).fill(p.recess).box(66, 99, 128, 30)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.12)).overlay(
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            ).box(84, 103, 28, 22)
            HStack(spacing: 0) { inkCyan; inkMagenta; inkYellow }
                .clipShape(RoundedRectangle(cornerRadius: 3)).box(120, 103, 30, 22)
            Path { path in
                path.move(to: CGPoint(x: 62, y: 98))
                path.addLine(to: CGPoint(x: 198, y: 98))
                path.addLine(to: CGPoint(x: 188, y: 62))
                path.addLine(to: CGPoint(x: 72, y: 62))
                path.closeSubpath()
            }
            .fill(p.lid)
            Path { path in
                path.move(to: CGPoint(x: 62, y: 98))
                path.addLine(to: CGPoint(x: 198, y: 98))
                path.addLine(to: CGPoint(x: 188, y: 62))
                path.addLine(to: CGPoint(x: 72, y: 62))
                path.closeSubpath()
            }
            .stroke(p.edge, lineWidth: 1.2)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(p.lid).box(62, 100, 136, 28)
            RoundedRectangle(cornerRadius: 6).strokeBorder(p.edge.opacity(0.7), lineWidth: 1).box(62, 100, 136, 28)
            Capsule().fill(p.edge.opacity(0.5)).box(110, 120, 40, 3)
        }
    }

    @ViewBuilder private func controls(_ p: Pal) -> some View {
        RoundedRectangle(cornerRadius: 8).fill(p.recess.opacity(p.dark ? 0.7 : 0.18)).box(214, 102, 54, 28)
        // power button
        Circle().fill(p.bodyTop).overlay(Circle().strokeBorder(p.edge, lineWidth: 1)).frame(width: 20, height: 20).at(230, 116)
        Image(systemName: "power").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(white: 0.3)).at(230, 116)
        // Color Copy button
        if glow {
            Circle().fill(Color.accentColor.opacity(0.28)).frame(width: 42, height: 42).at(254, 116)
            Circle().strokeBorder(Color.accentColor, lineWidth: 3).frame(width: 30 + 22 * pulse, height: 30 + 22 * pulse)
                .opacity(1 - 0.8 * pulse).at(254, 116)
        }
        Circle().fill(Color.white).overlay(Circle().strokeBorder(glow ? Color.accentColor : p.edge, lineWidth: glow ? 2.5 : 1))
            .frame(width: 22, height: 22).at(254, 116)
        HStack(spacing: 1.5) {
            Circle().fill(inkCyan); Circle().fill(inkMagenta); Circle().fill(inkYellow)
        }
        .frame(width: 15, height: 4.5).at(254, 116)
        if glow {
            Image(systemName: "hand.point.up.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color(red: 0.97, green: 0.78, blue: 0.62))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1.5)
                .at(258, 148 - 6 * pulse)
        }
    }
}

/// Small orange corner bracket that marks where the page goes.
private struct CornerMarker: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// The scanner glass from above: page outline, corner marker, back and front of the printer.
private struct GlassTopDown: View {
    let phase: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Pal(scheme)
        let label = Color.secondary
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [p.bodyTop, p.bodyBottom], startPoint: .top, endPoint: .bottom))
                .box(78, 12, 144, 178)
            RoundedRectangle(cornerRadius: 12).strokeBorder(p.edge, lineWidth: 1.4).box(78, 12, 144, 178)
            RoundedRectangle(cornerRadius: 4).fill(p.glass).box(86, 22, 128, 160)
            RoundedRectangle(cornerRadius: 4).strokeBorder(p.edge, lineWidth: 1.2).box(86, 22, 128, 160)
            // dashed target outline
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .box(92, 28, 112, 146)
            // the page, face down
            ZStack {
                Sheet(lines: false)
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .heavy))
                    Text("TOP").font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(Color(white: 0.45))
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
                Text("FACE\nDOWN").font(.system(size: 14, weight: .heavy)).multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.55))
            }
            .frame(width: 112, height: 146)
            .opacity(0.94)
            .offset(x: -(1 - phase) * 8, y: -(1 - phase) * 8)
            .at(148, 101)
            // marker in the back left corner
            CornerMarker().fill(p.marker).box(86, 22, 24, 24)
            Text("Marker").font(.system(size: 13, weight: .bold)).foregroundStyle(p.marker).at(40, 90)
            Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .heavy)).foregroundStyle(p.marker).at(66, 62)
            Text("BACK").font(.system(size: 11, weight: .bold)).foregroundStyle(label).at(40, 136)
            Text("FRONT").font(.system(size: 11, weight: .bold)).foregroundStyle(label).at(258, 170)
        }
    }
}

/// A cartridge with copper contacts and a cloth wiping them.
private struct ContactsArt: View {
    let phase: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Pal(scheme)
        let copper = LinearGradient(colors: [Color(red: 0.93, green: 0.62, blue: 0.36), Color(red: 0.74, green: 0.42, blue: 0.2)],
                                    startPoint: .top, endPoint: .bottom)
        ZStack {
            ZStack {
                // cartridge body
                RoundedRectangle(cornerRadius: 12).fill(Color(white: p.dark ? 0.85 : 0.97)).box(56, 20, 100, 120)
                RoundedRectangle(cornerRadius: 12).strokeBorder(p.edge, lineWidth: 1.5).box(56, 20, 100, 120)
                HStack(spacing: 0) { inkCyan; inkMagenta; inkYellow }
                    .clipShape(RoundedRectangle(cornerRadius: 6)).box(70, 32, 72, 34)
                Text("HP").font(.system(size: 22, weight: .heavy)).foregroundStyle(Color(white: 0.35)).at(106, 90)
                // copper contact strip
                RoundedRectangle(cornerRadius: 6).fill(copper).box(66, 108, 80, 42)
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(red: 0.5, green: 0.28, blue: 0.12), lineWidth: 1).box(66, 108, 80, 42)
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 1.0, green: 0.82, blue: 0.6))
                        .box(74 + CGFloat(i % 3) * 22, 114 + CGFloat(i / 3) * 18, 16, 12)
                }
            }
            .rotationEffect(.degrees(-6), anchor: .center)

            // cloth
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.white)
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color(white: 0.65), lineWidth: 1.2)
                Path { q in
                    q.move(to: CGPoint(x: 14, y: 22)); q.addQuadCurve(to: CGPoint(x: 94, y: 22), control: CGPoint(x: 54, y: 36))
                    q.move(to: CGPoint(x: 14, y: 46)); q.addQuadCurve(to: CGPoint(x: 94, y: 46), control: CGPoint(x: 54, y: 60))
                }
                .stroke(Color(white: 0.82), lineWidth: 2)
            }
            .frame(width: 108, height: 70)
            .rotationEffect(.degrees(10))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .at(198 - 40 * phase, 136)

            Image(systemName: "arrow.left.and.right").font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.accentColor).at(214, 86)
            Image(systemName: "sparkle").font(.system(size: 22, weight: .bold)).foregroundStyle(.yellow)
                .opacity(0.4 + 0.6 * phase).at(112, 156)
        }
    }
}

// MARK: picture cards

/// One numbered picture card with a short caption. Used in rows for multi-step actions.
struct StepPicture: View {
    enum Mode { case normal, current, done }
    let number: Int
    let scene: IllustrationScene
    let caption: String
    var mode: Mode = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Illustration(scene: scene, animated: mode == .current)
                .overlay(alignment: .topLeading) { badge.padding(Space.s) }
                .opacity(mode == .done ? 0.6 : 1)
            Text(caption)
                .font(TypeScale.secondary.weight(.medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(Space.s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Radius.card)
            .fill(mode == .current ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(mode == .current ? Color.accentColor : Color(nsColor: .separatorColor),
                          lineWidth: mode == .current ? 2 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number): \(caption)")
    }

    private var badge: some View {
        ZStack {
            Circle().fill(mode == .done ? Color.green : Color.accentColor).frame(width: 26, height: 26)
            if mode == .done {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
            } else {
                Text("\(number)").font(.callout.bold()).foregroundStyle(.white)
            }
        }
    }
}
