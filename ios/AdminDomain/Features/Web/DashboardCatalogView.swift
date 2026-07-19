import SwiftUI

struct DashboardCatalogView: View {
    @StateObject private var model: DashboardCatalogViewModel

    init(api: APIClient, cache: SnapshotCache?) {
        _model = StateObject(wrappedValue: DashboardCatalogViewModel(api: api, cache: cache))
    }

    var body: some View {
        List {
            if model.isStale {
                Section { Label("dashboard.catalog.stale", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("common.retry") { Task { await model.load() } }
                }
            }
            Section {
                ForEach(model.entries) { entry in
                    NavigationLink { DashboardBrowserScreen(entry: entry) } label: { DashboardRow(entry: entry) }
                }
                if !model.isLoading && model.entries.isEmpty && model.errorMessage == nil {
                    Label("dashboard.catalog.empty", systemImage: "safari").foregroundStyle(.secondary)
                }
            } header: { Text("dashboard.catalog.approved") }
        }
        .overlay { if model.isLoading && model.entries.isEmpty { ProgressView() } }
        .navigationTitle("dashboards.title")
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

private struct DashboardRow: View {
    let entry: DashboardEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline)
                HStack(spacing: 8) {
                    Label(authenticationLabel, systemImage: "person.crop.circle.badge.checkmark")
                    Label(orientationLabel, systemImage: "iphone")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: entry.symbolName).foregroundStyle(healthColor) }
    }

    private var authenticationLabel: LocalizedStringKey { entry.authentication == .googleOAuth ? "dashboard.auth.google" : "dashboard.auth.existing" }
    private var orientationLabel: LocalizedStringKey { entry.orientation == .portrait ? "dashboard.orientation.portrait" : "dashboard.orientation.landscape" }
    private var healthColor: Color {
        switch entry.healthState { case .available: return .green; case .degraded: return .orange; case .unavailable: return .red }
    }
}
