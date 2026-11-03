import SkeletonCore
import SwiftUI

/// Your body at a glance: every current pain as a network (pains linked through the causes or
/// structures they share), what that may mean, and one plan for working on it.
struct OverviewPage: View {
    let model: BodyViewModel
    @State private var selected: Node?

    enum Node: Hashable {
        case area(String)
        case hub(String)
    }

    private var overview: BodyOverview {
        BodyOverview.build(entries: model.entries, data: model.data, metrics: model.metrics)
    }

    var body: some View {
        let o = overview
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your body").font(.system(size: 30, weight: .bold)).tracking(-0.7)
                    Text(o.summary).font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
                }
                ForEach(model.activeRedFlags) { flag in
                    RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                isEmergency: flag.urgency == .emergency)
                }
                if o.isEmpty {
                    GlassCard {
                        Text("Log a pain and it shows up here, connected to anything related.")
                            .font(Theme.Font.callout)
                    }
                } else {
                    PainNetwork(model: model, overview: o, selected: $selected)
                        .frame(height: 420)
                    detail(o)
                    meaning(o)
                    plan(o)
                    Text("Patterns, not a diagnosis. Not medical advice.")
                        .font(.system(size: 11)).foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(GlowBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    @ViewBuilder private func detail(_ o: BodyOverview) -> some View {
        switch selected {
        case .area(let id):
            if let a = o.areas.first(where: { $0.id == id }) {
                GlassCard(rainbow: true) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(a.name).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(a.intensity)/10").font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.Color.pain(intensity: a.intensity))
                    }
                    Text(trendText(a)).font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
                    let hubs = o.hubs.filter { $0.areaIDs.contains(a.id) }
                    if !hubs.isEmpty {
                        Text("Connected through " + hubs.map { $0.name.lowercasedFirstLetter }.joined(separator: " and ") + ".")
                            .font(Theme.Font.callout)
                    }
                    Button("See insight") { model.show(.pain(a.latestEntryID)) }
                        .buttonStyle(.primaryPill)
                        .padding(.top, 4)
                }
            }
        case .hub(let id):
            if let h = o.hubs.first(where: { $0.id == id }) {
                GlassCard(rainbow: true) {
                    Text(h.name).font(.system(size: 17, weight: .semibold))
                    Text(h.mechanism.plainName.uppercased())
                        .font(Theme.Font.label).tracking(1).foregroundStyle(Theme.Color.secondaryText)
                    Text(h.explanation).font(Theme.Font.callout)
                    if !h.contributors.isEmpty {
                        Text("Often linked to " + h.contributors.joined(separator: ", ").lowercased() + ".")
                            .font(Theme.Font.callout).foregroundStyle(Color(hex: 0x2A2A2E))
                    }
                    Text("Who can help: \(h.specialist)")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                }
            }
        case nil:
            Text("Tap a pain or a connection to see more.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
        }
    }

    @ViewBuilder private func meaning(_ o: BodyOverview) -> some View {
        if !o.hubs.isEmpty || !o.healthPatterns.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("What it may mean")
                ForEach(o.hubs) { h in
                    Button { withAnimation(.spring(response: 0.35)) { selected = .hub(h.id) } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.name).font(.system(size: 15, weight: .semibold))
                            Text(h.explanation.firstSentences(1)).font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(o.healthPatterns, id: \.self) { p in
                    Label(p, systemImage: "waveform.path.ecg").font(Theme.Font.callout)
                }
                let alone = o.unlinkedAreaIDs.compactMap { id in o.areas.first { $0.id == id }?.name }
                if !alone.isEmpty && !o.hubs.isEmpty {
                    Text("Not linked to your other pains: " + alone.joined(separator: ", ") + ".")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private func plan(_ o: BodyOverview) -> some View {
        if !o.selfCare.isEmpty || !o.seeSomeoneIf.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Your plan")
                if !o.selfCare.isEmpty {
                    GlassCard(label: "What may help") {
                        ForEach(o.selfCare, id: \.self) { Label($0, systemImage: "checkmark").font(Theme.Font.callout) }
                    }
                }
                if !o.seeSomeoneIf.isEmpty {
                    GlassCard(label: "See someone if") {
                        ForEach(o.seeSomeoneIf, id: \.self) { Label($0, systemImage: "stethoscope").font(Theme.Font.callout) }
                        if !o.specialists.isEmpty {
                            Text("Who can help: " + o.specialists.joined(separator: ", "))
                                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func trendText(_ a: BodyOverview.Area) -> String {
        let when = a.lastOnset.formatted(.relative(presentation: .named))
        switch a.trend {
        case .new: return "First logged \(when)."
        case .worse: return "Getting worse · \(a.entryCount) entries, last \(when)."
        case .better: return "Easing · \(a.entryCount) entries, last \(when)."
        case .steady: return "About the same · \(a.entryCount) entries, last \(when)."
        }
    }
}

extension String {
    var lowercasedFirstLetter: String { prefix(1).lowercased() + dropFirst() }
}

/// The network: pains where they are on the body, causes they share as hubs at the sides,
/// with small pulses travelling along each connection.
struct PainNetwork: View {
    let model: BodyViewModel
    let overview: BodyOverview
    @Binding var selected: OverviewPage.Node?

    private struct Layout {
        var areas: [String: CGPoint] = [:]
        var hubs: [String: CGPoint] = [:]
        var bodyRect: CGRect = .zero
    }

    var body: some View {
        GeometryReader { geo in
            let layout = makeLayout(geo.size)
            ZStack {
                if let map = model.bodyMaps[.front] {
                    Image(decorative: map.image, scale: 1)
                        .resizable()
                        .frame(width: layout.bodyRect.width, height: layout.bodyRect.height)
                        .position(x: layout.bodyRect.midX, y: layout.bodyRect.midY)
                        .opacity(0.55)
                }
                TimelineView(.animation) { tl in
                    Canvas { ctx, _ in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for h in overview.hubs {
                            guard let hp = layout.hubs[h.id] else { continue }
                            for a in h.areaIDs {
                                guard let ap = layout.areas[a] else { continue }
                                let active = selected == nil || selected == .hub(h.id) || selected == .area(a)
                                let c = control(ap, hp)
                                var path = Path()
                                path.move(to: ap)
                                path.addQuadCurve(to: hp, control: c)
                                ctx.stroke(path, with: .color(Theme.Color.text.opacity(active ? 0.55 : 0.12)),
                                           style: StrokeStyle(lineWidth: active ? 1.6 : 1, lineCap: .round, dash: [3, 4]))
                                guard active else { continue }
                                // Pulses: the pain travelling to (and from) the shared cause.
                                for k in 0..<2 {
                                    let u = (t * 0.35 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                                    let p = quad(ap, c, hp, CGFloat(u))
                                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                                             with: .color(Color(hex: 0xFF4D3D).opacity(0.9)))
                                }
                            }
                        }
                    }
                }
                ForEach(overview.areas) { a in
                    if let p = layout.areas[a.id] { areaNode(a).position(p) }
                }
                ForEach(overview.hubs) { h in
                    if let p = layout.hubs[h.id] { hubNode(h).position(p) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.35)) { selected = nil } }
        }
    }

    private func areaNode(_ a: BodyOverview.Area) -> some View {
        let isSel = selected == .area(a.id)
        return Button { withAnimation(.spring(response: 0.35)) { selected = isSel ? nil : .area(a.id) } } label: {
            ZStack {
                Circle().fill(Theme.Color.pain(intensity: a.intensity).opacity(0.25)).frame(width: 34, height: 34)
                Circle().fill(Theme.Color.pain(intensity: a.intensity)).frame(width: isSel ? 20 : 16, height: isSel ? 20 : 16)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .overlay(alignment: .bottom) {
                Text(a.name)
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                    .offset(y: 16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(a.name), \(a.intensity) out of 10")
    }

    private func hubNode(_ h: BodyOverview.Hub) -> some View {
        let isSel = selected == .hub(h.id)
        return Button { withAnimation(.spring(response: 0.35)) { selected = isSel ? nil : .hub(h.id) } } label: {
            Text(h.name)
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(width: 104)
                .padding(.vertical, 7).padding(.horizontal, 6)
                .foregroundStyle(isSel ? .white : Theme.Color.text)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSel ? Theme.Color.text : Color.white.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(h.isRedFlag ? Theme.Color.redFlag : Theme.Color.text.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func makeLayout(_ size: CGSize) -> Layout {
        var l = Layout()
        guard let map = model.bodyMaps[.front], let body = model.stockBody else { return l }
        let h = size.height - 20
        let w = h * map.aspect
        l.bodyRect = CGRect(x: (size.width - w) / 2, y: 10, width: w, height: h)
        for a in overview.areas {
            guard let p3 = body.anchor(ofRegion: a.id) else { continue }
            let p = BodyMapImage.point(BodyProjection.project(p3, view: .front), map.map, l.bodyRect.size)
            l.areas[a.id] = CGPoint(x: p.x + l.bodyRect.minX, y: p.y + l.bodyRect.minY)
        }
        // Hubs sit beside the body on the side of their pains, spread so they don't overlap.
        var left: [(String, CGFloat)] = [], right: [(String, CGFloat)] = []
        for hub in overview.hubs {
            let pts = hub.areaIDs.compactMap { l.areas[$0] }
            guard !pts.isEmpty else { continue }
            let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            if cx < size.width / 2 { left.append((hub.id, cy)) } else { right.append((hub.id, cy)) }
        }
        if left.isEmpty && right.count > 1 { left.append(right.removeLast()) }
        func place(_ items: [(String, CGFloat)], x: CGFloat) {
            var lastY = -CGFloat.infinity
            for (id, y) in items.sorted(by: { $0.1 < $1.1 }) {
                let yy = min(max(y, lastY + 64, 34), size.height - 34)
                l.hubs[id] = CGPoint(x: x, y: yy)
                lastY = yy
            }
        }
        place(left, x: 58)
        place(right, x: size.width - 58)
        return l
    }

    private func control(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 24)
    }

    private func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
}
