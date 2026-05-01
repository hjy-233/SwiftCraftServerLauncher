import Foundation

@MainActor
final class DownloadCenter: ObservableObject {
    static let shared = DownloadCenter()

    struct TaskItem: Identifiable {
        enum Status {
            case running
            case success
            case failed
        }

        let id: UUID
        var title: String
        var iconSystemName: String
        var progress: Double?
        var status: Status
        var startedAt: Date
    }

    @Published private(set) var tasks: [TaskItem] = []
    private var cancelHandlers: [UUID: () -> Void] = [:]
    private var cancelledTaskIds = Set<UUID>()

    var activeTasks: [TaskItem] {
        tasks.filter { $0.status == .running }
    }

    var hasActiveTasks: Bool {
        !activeTasks.isEmpty
    }

    var averageProgress: Double? {
        let progressValues = activeTasks.compactMap { $0.progress }
        guard !progressValues.isEmpty else { return nil }
        let total = progressValues.reduce(0, +)
        return total / Double(progressValues.count)
    }

    @discardableResult
    func startTask(
        title: String,
        iconSystemName: String,
        progress: Double? = nil
    ) -> UUID {
        let id = UUID()
        let item = TaskItem(
            id: id,
            title: title,
            iconSystemName: iconSystemName,
            progress: progress,
            status: .running,
            startedAt: Date()
        )
        tasks.insert(item, at: 0)
        return id
    }

    func registerCancel(id: UUID, handler: @escaping () -> Void) {
        cancelHandlers[id] = handler
    }

    func cancelTask(id: UUID) {
        cancelledTaskIds.insert(id)
        cancelHandlers[id]?()
        cancelHandlers[id] = nil
    }

    func updateProgress(id: UUID, progress: Double?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = progress
    }

    func finishTask(id: UUID, success: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = success ? .success : .failed
        tasks[index].progress = success ? 1.0 : tasks[index].progress
        cancelHandlers[id] = nil
        cancelledTaskIds.remove(id)
    }

    func removeFinishedTasks() {
        tasks.removeAll { $0.status != .running }
        let runningIds = Set(tasks.map(\.id))
        cancelHandlers = cancelHandlers.filter { runningIds.contains($0.key) }
        cancelledTaskIds = cancelledTaskIds.filter { runningIds.contains($0) }
    }

    func wasCancelled(id: UUID) -> Bool {
        cancelledTaskIds.contains(id)
    }
}
