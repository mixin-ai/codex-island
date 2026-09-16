import Foundation
import Combine

@MainActor
final class CodexTaskStore: ObservableObject {
    static let shared = CodexTaskStore()

    @Published private(set) var items: [CodexTaskItem] = []
    @Published private(set) var unavailable = false
    private let reader = CodexTaskReader()
    private let queue = DispatchQueue(label: "CodexIsland.tasks", qos: .utility)
    private var timer: Timer?
    private var refreshing = false

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.5
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let reader = self.reader
        queue.async { [weak self] in
            let result = Result { try reader.read() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                switch result {
                case .success(let items):
                    if self.items != items { self.items = items }
                    self.unavailable = false
                case .failure:
                    self.items = []
                    self.unavailable = true
                }
            }
        }
    }
}
