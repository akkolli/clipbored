import Foundation
import ServiceManagement

final class AppLifecycleService {
  enum LaunchAtLoginResult: Equatable {
    case success
    case noChange
    case failure(String)
  }

  private let service = SMAppService.mainApp

  func applyLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginResult {
    do {
      if enabled {
        switch service.status {
        case .notRegistered:
          try service.register()
          return .success
        case .enabled:
          return .noChange
        default:
          try service.register()
          return .success
        }
      } else if service.status == .enabled {
        try service.unregister()
        return .success
      } else {
        return .noChange
      }
    } catch {
      return .failure(error.localizedDescription)
    }
  }

  func isEnabled() -> Bool {
    service.status == .enabled
  }
}
