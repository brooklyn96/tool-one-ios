import Foundation

enum DeploymentEnvironment: String, CaseIterable, Equatable {
    case development
    case staging
    case production
}

enum AppEnvironmentError: Error, Equatable {
    case invalidBaseURL
    case insecureBaseURL
}

struct AppEnvironment: Equatable {
    let deployment: DeploymentEnvironment
    let baseURL: URL

    init(deployment: DeploymentEnvironment, baseURL: URL) throws {
        guard baseURL.host != nil else {
            throw AppEnvironmentError.invalidBaseURL
        }
        guard baseURL.scheme == "https" else {
            throw AppEnvironmentError.insecureBaseURL
        }

        self.deployment = deployment
        self.baseURL = baseURL
    }

    static var current: AppEnvironment {
        let deploymentValue = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String
        let deployment = DeploymentEnvironment(rawValue: deploymentValue ?? "production") ?? .production
        let urlValue = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        let fallbackURL = URL(string: "https://admin-api.beyondk.live")!
        let baseURL = urlValue.flatMap(URL.init(string:)) ?? fallbackURL

        return (try? AppEnvironment(deployment: deployment, baseURL: baseURL))
            ?? (try! AppEnvironment(deployment: .production, baseURL: fallbackURL))
    }
}
