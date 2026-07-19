import SwiftUI

enum AppMode: Equatable {
    case workspace
    case dealSync
    case externalSync
}

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case activity
    case settings

    var id: String { rawValue }

    var localizedTitle: String {
        NSLocalizedString("tab.\(rawValue)", comment: "Primary tab title")
    }

    var systemImage: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var mode: AppMode = .workspace
    @Published var selectedTab: AppTab = .overview

    func open(_ program: NativeProgramID) {
        mode = program == .dealSync ? .dealSync : .externalSync
    }

    func closeProgram() {
        mode = .workspace
    }
}
