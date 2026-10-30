import PDFKit
import SkeletonCore
import SwiftUI

/// Everything the printed report shows, captured at the moment it's made.
struct DoctorReportData {
    var profile: Profile
    var entries: [PainEntry]
    var episodes: [Episode]
    var insights: [String: Insight]
    var redFlags: [RedFlagMatch]
    var pathways: PathwayLibrary
    var atlas: BodyAtlas
    var silhouettes: [BodyProjection.View: [SIMD2<Float>]]
    var anchors: [String: Vec3]
    var arcs: [FlowArc]
    var generatedAt = Date()

    var dateRange: String {
        guard let first = entries.first?.onsetAt, let last = entries.last?.onsetAt else { return "No entries" }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    func regionName(_ id: String) -> String { atlas.region(id)?.name ?? id }
}

/// Renders the report as a multi-page US Letter PDF (612 × 792 pt).
@MainActor
enum DoctorReportRenderer {
    static let pageSize = CGSize(width: 612, height: 792)
    static let rowsPerPage = 16

    static func render(_ data: DoctorReportData) throws -> URL {
        let entryPages = stride(from: 0, to: max(data.entries.count, 1), by: rowsPerPage).map {
            Array(data.entries.reversed().dropFirst($0).prefix(rowsPerPage))
        }
        var pages: [AnyView] = [AnyView(SummaryPage(data: data)), AnyView(EpisodesPage(data: data))]
        for (i, rows) in entryPages.enumerated() {
            pages.append(AnyView(EntriesPage(data: data, rows: rows, page: i + 1, of: entryPages.count)))
        }

        let stamp = data.generatedAt.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Skeleton pain report \(stamp).pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for page in pages {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height).background(Color.white))
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }
}

// MARK: - Pages

private struct PageFrame<Content: View>: View {
    let title: String
    let data: DoctorReportData
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Skeleton").font(.system(size: 13, weight: .bold))
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.Color.secondaryText)
                Spacer()
                Text("Generated \(data.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(Theme.Color.secondaryText)
            }
            Divider()
            content
            Spacer(minLength: 0)
            Text("Patient-logged pain diary with pattern hints from Skeleton's pathway library. Shows possible contributors, not a diagnosis. Not medical advice. Body diagrams use a stock body fitted to the patient's height and build; inner anatomy is reference anatomy.")
                .font(.system(size: 8))
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(36)
        .foregroundStyle(Theme.Color.text)
    }
}

private struct SummaryPage: View {
    let data: DoctorReportData

    var body: some View {
        PageFrame(title: "Pain report", data: data) {
            VStack(alignment: .leading, spacing: 4) {
                Text(data.profile.displayName ?? "Pain report").font(.system(size: 24, weight: .bold)).tracking(-0.4)
                Text(patientLine).font(.system(size: 11)).foregroundStyle(Theme.Color.secondaryText)
                Text("\(data.entries.count) entries · \(data.dateRange)").font(.system(size: 11)).foregroundStyle(Theme.Color.secondaryText)
                if !data.profile.medicalHistory.isEmpty {
                    Text("History noted by patient: " + data.profile.medicalHistory.joined(separator: ", "))
                        .font(.system(size: 10))
                }
            }

            ForEach(data.redFlags) { flag in
                VStack(alignment: .leading, spacing: 2) {
                    Text("⚠ \(flag.headline): \(flag.title)").font(.system(size: 11, weight: .bold))
                    Text(flag.message).font(.system(size: 10))
                }
                .foregroundStyle(Theme.Color.redFlag)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xFFE9E6)))
            }

            HStack(spacing: 16) {
                ForEach(BodyProjection.View.allCases, id: \.self) { view in
                    VStack(spacing: 4) {
                        BodyMapCanvas(data: data, view: view)
                            .frame(height: 360)
                        Text(view.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Color.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 6) {
                Text("Last 14 days of pain by area. Colour = intensity of the latest entry:").font(.system(size: 9))
                ForEach([2, 5, 8, 10], id: \.self) { i in
                    Circle().fill(Theme.Color.pain(intensity: i)).frame(width: 8, height: 8)
                    Text("\(i)").font(.system(size: 9))
                }
                Text("· Red lines connect pains linked by a known pathway.").font(.system(size: 9))
            }
            .foregroundStyle(Theme.Color.secondaryText)

            Text("Health apps: none connected yet.").font(.system(size: 10)).foregroundStyle(Theme.Color.secondaryText)
        }
    }

    private var patientLine: String {
        var parts: [String] = []
        if let age = data.profile.age() { parts.append("\(age) y") }
        if data.profile.sex != .unspecified { parts.append(data.profile.sex.rawValue.capitalized) }
        parts.append("\(Int(data.profile.heightCm.rounded())) cm")
        parts.append("\(Int(data.profile.weightKg.rounded())) kg")
        if let a = data.profile.activityLevel { parts.append("activity: \(a.label.lowercased())") }
        return parts.joined(separator: " · ")
    }
}

private struct EpisodesPage: View {
    let data: DoctorReportData

    var body: some View {
        PageFrame(title: "Episodes", data: data) {
            if data.episodes.isEmpty {
                Text("No linked episodes: none of the logged pains are connected by a known pathway.").font(.system(size: 11))
            }
            ForEach(data.episodes) { ep in
                VStack(alignment: .leading, spacing: 5) {
                    Text(ep.title).font(.system(size: 14, weight: .bold))
                    Text("\(ep.startedAt.formatted(date: .abbreviated, time: .omitted)) – \(ep.isActive ? "ongoing" : ep.lastEntryAt.formatted(date: .abbreviated, time: .omitted)) · \(ep.entryIDs.count) linked entries")
                        .font(.system(size: 10)).foregroundStyle(Theme.Color.secondaryText)
                    Text(path(ep)).font(.system(size: 10))
                    if let insight = data.insights[ep.id] {
                        Text(insight.summary).font(.system(size: 10.5))
                        if !insight.factors.isEmpty {
                            Text("Often linked to: " + insight.factors.map(\.title).joined(separator: "; ")).font(.system(size: 10))
                        }
                        if !insight.doctorQuestions.isEmpty {
                            Text("Patient's questions: " + insight.doctorQuestions.joined(separator: " ")).font(.system(size: 10))
                        }
                    } else {
                        ForEach(ep.pathwayIDs.prefix(2), id: \.self) { id in
                            if let p = data.pathways.pathway(id) {
                                Text("\(p.name): \(p.plainExplanation)").font(.system(size: 10.5))
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.Color.background))
            }
        }
    }

    private func path(_ ep: Episode) -> String {
        let ids = Set(ep.entryIDs)
        return data.entries.filter { ids.contains($0.id) }
            .map { "\($0.regionIDs.map(data.regionName).joined(separator: " + ")) (\($0.onsetAt.formatted(.dateTime.month(.abbreviated).day())))" }
            .joined(separator: " → ")
    }
}

private struct EntriesPage: View {
    let data: DoctorReportData
    let rows: [PainEntry]
    let page: Int
    let of: Int

    var body: some View {
        PageFrame(title: "Pain log \(page)/\(of)", data: data) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    ForEach(["Date", "Where", "Type", "/10", "Pattern", "Worse / better", "Notes"], id: \.self) {
                        Text($0).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Color.secondaryText)
                    }
                }
                Divider()
                ForEach(rows) { e in
                    GridRow(alignment: .top) {
                        Text(e.onsetAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        Text(e.regionIDs.map(data.regionName).joined(separator: ", "))
                        Text(e.painType.label)
                        Text("\(e.intensity)").bold().foregroundStyle(Theme.Color.pain(intensity: e.intensity))
                        Text(e.pattern?.label ?? "–")
                        Text([e.triggers.isEmpty ? nil : "↑ " + e.triggers.joined(separator: ", "),
                              e.relievers.isEmpty ? nil : "↓ " + e.relievers.joined(separator: ", ")]
                            .compactMap { $0 }.joined(separator: "\n"))
                        Text(e.notes ?? "")
                    }
                    .font(.system(size: 9))
                }
            }
            if rows.isEmpty { Text("No entries yet.").font(.system(size: 11)) }
        }
    }
}

/// 2D body diagram: silhouette, pain spots for the last 14 days, and pathway lines.
struct BodyMapCanvas: View {
    let data: DoctorReportData
    let view: BodyProjection.View

    var body: some View {
        Canvas { ctx, size in
            let tris = data.silhouettes[view] ?? []
            guard !tris.isEmpty else { return }
            let xs = tris.map(\.x), ys = tris.map(\.y)
            let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
            let scale = CGFloat(min(Float(size.width) / (maxX - minX), Float(size.height) / (maxY - minY))) * 0.95
            let cx = size.width / 2, base = size.height - (size.height - CGFloat(maxY - minY) * scale) / 2
            func pt(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: cx + CGFloat(p.x - (minX + maxX) / 2) * scale, y: base - CGFloat(p.y - minY) * scale)
            }

            var silhouette = Path()
            var i = 0
            while i + 2 < tris.count {
                silhouette.move(to: pt(tris[i]))
                silhouette.addLine(to: pt(tris[i + 1]))
                silhouette.addLine(to: pt(tris[i + 2]))
                silhouette.closeSubpath()
                i += 3
            }
            ctx.fill(silhouette, with: .color(Color(hex: 0xE4E4E9)))

            for arc in data.arcs {
                guard let a = data.anchors[arc.fromRegionID], let b = data.anchors[arc.toRegionID],
                      let ra = data.atlas.region(arc.fromRegionID), let rb = data.atlas.region(arc.toRegionID),
                      BodyProjection.shows(ra, on: view) || BodyProjection.shows(rb, on: view) else { continue }
                var line = Path()
                line.move(to: pt(BodyProjection.project(a, view: view)))
                line.addLine(to: pt(BodyProjection.project(b, view: view)))
                ctx.stroke(line, with: .color(Theme.Color.pain.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            }

            for spot in PainSpot.summarize(data.entries, now: data.generatedAt) {
                guard let region = data.atlas.region(spot.regionID), BodyProjection.shows(region, on: view),
                      let anchor = data.anchors[spot.regionID] else { continue }
                let c = pt(BodyProjection.project(anchor, view: view))
                let r: CGFloat = 4 + CGFloat(spot.intensity) * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.8, y: c.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                         with: .color(Theme.Color.pain(intensity: spot.intensity).opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.Color.pain(intensity: spot.intensity)))
            }
        }
    }
}

// MARK: - Sheet

struct DoctorReportSheet: View {
    let url: URL
    let links: (any ReportLinkService)?
    let userID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var link: URL?
    @State private var linkBusy = false
    @State private var linkError: String?

    static let linkDays = 7

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack {
                Text("Doctor report").font(Theme.Font.title).tracking(-0.4)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.secondaryPill)
            }
            PDFPreview(url: url)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            ShareLink(item: url) {
                Label("Share or print PDF", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primaryPill)
            if let links {
                if let link {
                    ShareLink(item: link, message: Text("My pain report from Skeleton (link expires in \(Self.linkDays) days)")) {
                        Label("Send link (expires in \(Self.linkDays) days)", systemImage: "link")
                    }
                    .buttonStyle(.secondaryPill)
                } else {
                    Button(linkBusy ? "Creating link…" : "Create a private link") {
                        linkBusy = true
                        linkError = nil
                        Task {
                            defer { linkBusy = false }
                            do {
                                link = try await links.link(for: url, userID: userID, validFor: Self.linkDays * 86_400)
                            } catch {
                                linkError = "Couldn't create the link. \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.secondaryPill)
                    .disabled(linkBusy)
                }
                if let linkError {
                    Text(linkError).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
                }
            }
            Text("Your health data. Only share it with people you trust, such as your doctor or physical therapist.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(Theme.Spacing.l)
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
