import SwiftUI

struct ProgramsView: View {
    @ObservedObject var store: ProgramsStore
    let api: APIClient
    let cache: SnapshotCache?
    let externalSyncClient: ExternalSyncClient
    let dealSyncClient: DealSyncClient

    var body: some View {
        List {
            Section("programs.native") {
                ForEach(NativeProgramID.allCases) { id in
                    if id == .dealSync {
                        NavigationLink { DealSyncRootView(client: dealSyncClient, cache: cache, onBackToToolOne: {}) } label: {
                            Label {
                                VStack(alignment: .leading) { Text("Deal Sync").font(.headline); Text("Ứng dụng native đầy đủ").font(.caption).foregroundStyle(.secondary) }
                            } icon: { Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.tint) }
                        }.frame(minHeight: 52)
                    } else if id == .externalSync {
                        NavigationLink {
                            ExternalSyncRootView(
                                client: externalSyncClient,
                                cache: cache,
                                liveStore: ExternalSyncLiveStore(client: externalSyncClient, cache: cache),
                                onBackToToolOne: {}
                            )
                        } label: {
                            Label {
                                VStack(alignment: .leading) { Text("External Sync").font(.headline); Text("Ứng dụng native đầy đủ").font(.caption).foregroundStyle(.secondary) }
                            } icon: { Image(systemName: "arrow.up.arrow.down.circle.fill").foregroundStyle(.tint) }
                        }.frame(minHeight: 52)
                    }
                }
            }
            Section("programs.webFallback") {
                NavigationLink { DashboardCatalogView(api: api, cache: cache) } label: {
                    Label("programs.webFallback.detail", systemImage: "safari")
                }
            }
        }
        .navigationTitle("programs.title")
        .overlay { if store.isLoading && store.snapshots.isEmpty { ProgressView() } }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private func title(_ id: NativeProgramID) -> String { id == .dealSync ? "Deal Sync" : "External Sync" }
}

struct ProgramRow: View {
    let snapshot: ProgramSnapshot
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.id == .dealSync ? "arrow.triangle.2.circlepath" : "arrow.up.arrow.down.circle").font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title).font(.headline)
                Text(snapshot.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ProgramStateBadge(state: snapshot.state, stale: snapshot.stale)
        }
        .frame(minHeight: 52)
    }
}

private struct ProgramUnavailableRow: View {
    let id: NativeProgramID
    let error: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(id == .dealSync ? "Deal Sync" : "External Sync", systemImage: "exclamationmark.triangle")
            Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(minHeight: 44)
    }
}

struct ProgramDetailView: View {
    let snapshot: ProgramSnapshot
    let api: APIClient
    var body: some View {
        List {
            if snapshot.stale || snapshot.partial {
                Section { Label(snapshot.stale ? "programs.stale" : "programs.partial", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            Section("programs.summary") {
                ForEach(snapshot.summary) { metric in
                    LabeledContent(metric.label, value: metric.value).foregroundStyle(metricColor(metric.tone))
                }
            }
            Section("programs.data") {
                ForEach(snapshot.collections) { collection in
                    NavigationLink { ProgramCollectionView(programID: snapshot.id, collection: collection, api: api) } label: {
                        Label { LabeledContent(collection.title, value: "\(collection.total)") } icon: { Image(systemName: collection.symbolName) }
                    }
                    .frame(minHeight: 44)
                }
            }
            Section("Thao tác") {
                NavigationLink { CommandCatalogView(programID: snapshot.id, api: api) } label: {
                    Label("Quản lý \(snapshot.title)", systemImage: "wrench.and.screwdriver")
                }.frame(minHeight: 44)
            }
        }
        .navigationTitle(snapshot.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricColor(_ tone: ProgramMetric.Tone) -> Color {
        switch tone { case .neutral: return .primary; case .success: return .green; case .warning: return .orange; case .critical: return .red }
    }
}

struct ProgramCollectionView: View {
    let programID: NativeProgramID
    let api: APIClient
    @State private var collection: ProgramCollection
    @State private var isLoadingMore = false
    @State private var loadMoreError: String?

    init(programID: NativeProgramID, collection: ProgramCollection, api: APIClient) {
        self.programID = programID
        self.api = api
        _collection = State(initialValue: collection)
    }

    var body: some View {
        List {
            ForEach(collection.items) { item in
                NavigationLink { ProgramRecordView(record: item) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(item.title).font(.headline); Spacer(); Text(item.status).font(.caption).foregroundStyle(.secondary) }
                        if let subtitle = item.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        Text(item.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 52)
                }
            }
            if collection.nextCursor != nil || loadMoreError != nil {
                Section {
                    if let loadMoreError {
                        Text(loadMoreError).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await loadMore() } } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore { ProgressView() } else { Text("programs.loadMore") }
                            Spacer()
                        }
                    }
                    .disabled(isLoadingMore)
                }
            }
        }
        .overlay {
            if collection.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: collection.symbolName).font(.largeTitle).foregroundStyle(.secondary)
                    Text("programs.empty").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func loadMore() async {
        guard let cursor = collection.nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
            let path = "/v1/programs/" + programID.rawValue + "/collections/" + collection.id + "?cursor=" + encoded
            let page: ProgramCollection = try await api.send(path)
            let existing = Set(collection.items.map(\.id))
            let additions = page.items.filter { !existing.contains($0.id) }
            collection = ProgramCollection(id: collection.id, title: collection.title, symbolName: collection.symbolName, total: page.total, nextCursor: page.nextCursor, items: collection.items + additions)
        } catch {
            loadMoreError = error.localizedDescription
        }
    }
}

struct ProgramRecordView: View {
    let record: ProgramRecord
    var body: some View {
        List {
            Section("programs.status") { LabeledContent("programs.status", value: record.status); LabeledContent("programs.updated", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened)) }
            Section("programs.details") { ForEach(record.fields) { field in LabeledContent(field.label, value: field.value) } }
        }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProgramStateBadge: View {
    let state: ProgramState
    let stale: Bool
    var body: some View {
        Label(stale ? "programs.state.stale" : state.rawValue, systemImage: symbol).font(.caption).foregroundStyle(color).labelStyle(.titleAndIcon)
    }
    private var symbol: String { stale ? "clock.badge.exclamationmark" : state == .online ? "checkmark.circle.fill" : "exclamationmark.circle.fill" }
    private var color: Color { stale ? .orange : state == .online ? .green : state == .offline ? .red : .orange }
}
