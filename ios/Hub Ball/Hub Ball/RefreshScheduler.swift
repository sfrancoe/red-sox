import Foundation

/// All automatic refreshes use this clock. Views only register their visibility.
@MainActor
final class RefreshScheduler {
    private final class Job {
        let isLive: () -> Bool
        let refresh: () async -> Bool
        var observers = Set<String>()
        var lastSuccess: Date?
        var lastAttempt: Date?
        var task: Task<Void, Never>?
        var generation = 0
        init(isLive: @escaping () -> Bool, refresh: @escaping () async -> Bool) {
            self.isLive = isLive
            self.refresh = refresh
        }
    }
    private var jobs: [String: Job] = [:]
    private var background = false
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func register(_ key: String, isLive: @escaping () -> Bool = { false },
                  refresh: @escaping () async -> Bool) {
        guard jobs[key] == nil else { return }
        jobs[key] = Job(isLive: isLive, refresh: refresh)
    }

    func setVisible(_ visible: Bool, observer: String, jobs keys: [String]) {
        for key in keys {
            guard let job = jobs[key] else { continue }
            if visible { job.observers.insert(observer) }
            else { job.observers.remove(observer) }
            if job.observers.isEmpty { cancel(job) }
            else if !background { start(job) }
        }
    }

    /// Inactive (Control Center, permission prompts) deliberately does not call this.
    func setBackground(_ value: Bool) {
        guard background != value else { return }
        background = value
        for job in jobs.values {
            if value { cancel(job) }
            else if !job.observers.isEmpty {
                let stale = job.lastSuccess.map { now().timeIntervalSince($0) > 30 } ?? true
                start(job, refreshImmediately: stale)
            }
        }
    }

    func stop() { for job in jobs.values { job.observers.removeAll(); cancel(job) } }

    private func cancel(_ job: Job) {
        job.generation += 1
        job.task?.cancel()
        job.task = nil
    }

    private func start(_ job: Job, refreshImmediately: Bool = false) {
        guard job.task == nil else { return }
        job.generation += 1
        let generation = job.generation
        job.task = Task { [weak self, weak job] in
            guard let self, let job else { return }
            var immediate = refreshImmediately
            while !Task.isCancelled, !background, !job.observers.isEmpty {
                let interval: TimeInterval = job.isLive() ? 20 : 60
                let elapsed = job.lastAttempt.map { self.now().timeIntervalSince($0) } ?? .infinity
                if !immediate, elapsed < interval {
                    do { try await Task.sleep(for: .seconds(interval - elapsed)) }
                    catch { break }
                }
                immediate = false
                guard !Task.isCancelled, job.generation == generation else { break }
                job.lastAttempt = now()
                let succeeded = await job.refresh()
                guard !Task.isCancelled, job.generation == generation else { break }
                job.lastAttempt = now()
                if succeeded { job.lastSuccess = now() }
            }
            if job.generation == generation { job.task = nil }
        }
    }
}
