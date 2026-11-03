import SkeletonCore
import SwiftUI

enum AppTab: Hashable { case home, body, history }

/// Pages pushed onto a tab's navigation stack (standard back button and swipe-back).
enum Route: Hashable {
    case pain(UUID)
    case pattern(String)
    case devices
}

/// Signed-in app: Home, Body and History tabs, each with its own navigation stack.
/// Logging and describing stay quick modal sheets, available from any tab.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var model: BodyViewModel
    @State private var tab: AppTab = .home
    @State private var homePath: [Route] = []
    @State private var bodyPath: [Route] = []
    @State private var historyPath: [Route] = []
    private let profile: Profile

    init(app: AppModel, profile: Profile) {
        self.profile = profile
        _model = State(initialValue: BodyViewModel(data: app.data, pain: app.pain, insights: app.insights,
                                                   painInsights: app.painInsights,
                                                   parser: app.parser, health: app.health,
                                                   healthConnected: app.isHealthConnected(profile.userID),
                                                   profile: profile))
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView(model: model, profile: profile)
                        .navigationDestination(for: Route.self, destination: destination)
                }
            }
            Tab("Body", systemImage: "figure.stand", value: AppTab.body) {
                NavigationStack(path: $bodyPath) {
                    BodyScreen(model: model, profile: profile)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Route.self, destination: destination)
                }
            }
            Tab("History", systemImage: "list.bullet", value: AppTab.history) {
                NavigationStack(path: $historyPath) {
                    HistoryView(model: model)
                        .navigationDestination(for: Route.self, destination: destination)
                }
            }
        }
        .tint(Theme.Color.text)
        .task {
            async let bodyLoad: Void = model.load(morph: profile.morph)
            async let historyLoad: Void = model.loadEntries()
            _ = await (bodyLoad, historyLoad)
            await model.loadHealth()
        }
        .onChange(of: model.requestedTab) { _, requested in
            guard let requested else { return }
            if requested == .body { bodyPath = [] }
            tab = requested
            model.requestedTab = nil
        }
        .onChange(of: model.requestedRoute) { _, route in
            guard let route else { return }
            switch tab {
            case .home: homePath.append(route)
            case .body: bodyPath.append(route)
            case .history: historyPath.append(route)
            }
            model.requestedRoute = nil
        }
        .sheet(isPresented: Bindable(model).isDescribeSheetPresented) {
            DescribePainSheet(model: model)
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(Theme.Radius.large)
        }
        .sheet(isPresented: Bindable(model).isLogSheetPresented, onDismiss: {
            // Swiping the sheet away cancels, unless it closed to let the user pick more spots.
            if !model.isPickingSpots { model.cancelLogging() }
        }) {
            LogPainSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(Theme.Radius.large)
        }
    }

    /// Tapping the current tab again goes back to its first screen.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { tab }, set: { new in
            if new == tab {
                switch new {
                case .home: homePath = []
                case .body: bodyPath = []
                case .history: historyPath = []
                }
            }
            tab = new
        })
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .pain(let id): PainInsightPage(model: model, entryID: id)
        case .pattern(let id): PatternPage(model: model, episodeID: id)
        case .devices: DevicesView(model: model, profile: profile)
        }
    }
}

/// A pain's insight as a page.
struct PainInsightPage: View {
    let model: BodyViewModel
    let entryID: UUID

    var body: some View {
        PainInsightView(model: model)
            .background(GlowBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            // Re-opens when revealed again by Back, so the page always shows its own pain.
            .onAppear { if model.painInsightEntryID != entryID || model.painInsight == nil { model.openPainInsight(entryID) } }
    }
}

/// A pain pattern's insight as a page, with a button to watch it on the body.
struct PatternPage: View {
    let model: BodyViewModel
    let episodeID: String

    var body: some View {
        ScrollView {
            if let ep = model.episodes.first(where: { $0.id == episodeID }) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ep.title).font(.system(size: 28, weight: .bold)).tracking(-0.7)
                        Text("\(ep.entryIDs.count) pains · \(ep.startedAt.formatted(.dateTime.month(.abbreviated).day())) – \(ep.isActive ? "now" : ep.lastEntryAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 14)).foregroundStyle(Theme.Color.secondaryText)
                    }
                    Button { model.watch(ep) } label: {
                        Label("Watch it move", systemImage: "play.fill")
                    }
                    .buttonStyle(.primaryPill)
                    InsightCard(model: model, episode: ep, inPage: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .onAppear { if model.selectedEpisode?.id != ep.id || model.insight == nil { model.open(ep) } }
            } else {
                Text("This pattern changed. Go back and open it again.")
                    .font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText).padding(20)
            }
        }
        .background(GlowBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
