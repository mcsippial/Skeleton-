import SkeletonCore
import SwiftUI
import UIKit

/// Health & devices: Apple Health, the wearables already feeding it, and how to add more.
struct DevicesView: View {
    @Environment(AppModel.self) private var app
    let model: BodyViewModel
    let profile: Profile

    @State private var sources: [HealthSource] = []
    @State private var direct: Set<Wearable> = []
    @State private var open: Wearable?
    @State private var busy = false

    private var found: Set<Wearable> { Set(sources.compactMap(\.wearable)).union(direct) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Health & devices")
                    .font(.system(size: 30, weight: .bold)).tracking(-0.7)
                appleHealth
                if model.healthConnected {
                    devices
                    addDevice
                }
                if let error = model.healthError {
                    Text(error).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(GlowBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    // MARK: Sections

    private var appleHealth: some View {
        GlassCard(rainbow: model.healthConnected) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF3B5C))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.health.sourceName).font(.system(size: 17, weight: .semibold))
                    Text(model.healthConnected ? "Connected" : "Sleep, HRV, heart rate, steps and workouts")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                }
                Spacer()
            }
            if model.healthConnected {
                Button("Disconnect") {
                    model.disconnectHealth()
                    app.setHealthConnected(false, userID: profile.userID)
                    sources = []
                }
                .buttonStyle(.secondaryPill)
                .padding(.top, 4)
            } else if model.health.isAvailable {
                Button(busy ? "Connecting…" : "Connect") {
                    busy = true
                    Task {
                        if await model.connectHealth() { app.setHealthConnected(true, userID: profile.userID) }
                        await refresh()
                        busy = false
                    }
                }
                .buttonStyle(.primaryPill)
                .disabled(busy)
                .padding(.top, 4)
            } else {
                Text("Apple Health isn't available on this device.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Your devices")
            if sources.isEmpty && direct.isEmpty {
                Text("None found in Apple Health yet.")
                    .font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
            }
            ForEach(sources) { s in
                deviceRow(name: s.wearable?.name ?? s.name, detail: s.kinds.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: " · "))
            }
            ForEach(direct.subtracting(sources.compactMap(\.wearable)).sorted { $0.name < $1.name }) { w in
                deviceRow(name: w.name, detail: "Connected directly")
            }
        }
    }

    private func deviceRow(name: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: 0x2BB673)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
        .accessibilityElement(children: .combine)
    }

    private var addDevice: some View {
        let missing = Wearable.allCases.filter { !found.contains($0) }
        return Group {
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Add a device")
                    ForEach(missing) { w in addRow(w) }
                }
            }
        }
    }

    private func addRow(_ w: Wearable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open = open == w ? nil : w }
            } label: {
                HStack {
                    Text(w.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(open == w ? 180 : 0))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open == w {
                ForEach(Array(w.syncSteps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 12, weight: .bold).monospacedDigit())
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.Color.track))
                        Text(step).font(Theme.Font.callout)
                    }
                }
                if app.wearables.isAvailable {
                    Button("Connect directly") {
                        Task {
                            if let url = try? await app.wearables.connect(w) { _ = await UIApplication.shared.open(url) }
                            await refresh()
                        }
                    }
                    .buttonStyle(.secondaryPill)
                } else {
                    Button("Open Apple Health") {
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.secondaryPill)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
    }

    private func refresh() async {
        direct = await app.wearables.connected()
        guard model.healthConnected else { sources = []; return }
        sources = (try? await model.health.sources()) ?? []
        await model.loadHealth()
    }
}
