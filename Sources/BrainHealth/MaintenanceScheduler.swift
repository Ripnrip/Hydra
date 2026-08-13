import Foundation

// MARK: - Maintenance Scheduler

/// Cron-style scheduler for periodic vault maintenance tasks.
/// All Swift — uses DispatchSourceTimer, no bash cron.
public actor MaintenanceScheduler {
    private var tasks: [String: ScheduledTask] = [:]

    public init() {}

    /// Register a maintenance task to run on an interval.
    public func register(
        name: String,
        interval: TimeInterval,
        task: @escaping @Sendable () async -> Void
    ) {
        let timer = DispatchSource.repeatingTimer(interval: interval)
        let scheduled = ScheduledTask(name: name, interval: interval)
        tasks[name] = scheduled

        timer.setEventHandler {
            Task { await task() }
        }
        timer.resume()
        scheduled.timer = timer
    }

    /// Unregister a task by name.
    public func unregister(_ name: String) {
        tasks[name]?.timer?.cancel()
        tasks.removeValue(forKey: name)
    }

    /// List all registered tasks.
    public func registeredTasks() -> [String] {
        Array(tasks.keys)
    }
}

// MARK: - DispatchSource Timer Extension

private extension DispatchSource {
    static func repeatingTimer(interval: TimeInterval) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .seconds(1)
        )
        return timer
    }
}

// MARK: - Scheduled Task

private final class ScheduledTask: @unchecked Sendable {
    let name: String
    let interval: TimeInterval
    var timer: DispatchSourceTimer?

    init(name: String, interval: TimeInterval) {
        self.name = name
        self.interval = interval
    }
}
