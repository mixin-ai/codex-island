import Foundation
import Combine

@MainActor
final class TaskSidebarPreferences: ObservableObject {
    static let shared = TaskSidebarPreferences()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "MacIsland.taskSidebar") }
    }

    @Published var glowEnabled: Bool {
        didSet { UserDefaults.standard.set(glowEnabled, forKey: "MacIsland.outerGlow") }
    }

    private init() {
        enabled = Pref.seededBool(key: "MacIsland.taskSidebar", default: true)
        glowEnabled = Pref.seededBool(key: "MacIsland.outerGlow", default: false)
    }
}
