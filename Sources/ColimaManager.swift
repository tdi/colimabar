import Foundation

enum ColimaStatus: String, Equatable {
    case running = "Running"
    case stopped = "Stopped"
    case starting = "Starting..."
    case stopping = "Stopping..."
    case unknown = "Unknown"

    var isRunning: Bool { self == .running }
    var isStopped: Bool { self == .stopped }
    var isTransitioning: Bool { self == .starting || self == .stopping }
}

struct ColimaInstance: Identifiable, Equatable {
    let id: String
    let name: String
    var status: ColimaStatus
    let arch: String
    let cpus: Int
    let memory: UInt64
    let disk: UInt64

    var memoryFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)
    }

    var diskFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(disk), countStyle: .file)
    }
}

enum LoadState: Equatable {
    case loading
    case loaded
    case error(String)
}

@MainActor
final class ColimaManager: ObservableObject {
    @Published private(set) var instances: [ColimaInstance] = []
    @Published private(set) var loadState: LoadState = .loading
    /// Set when a start/stop command fails; cleared on the next successful
    /// action or refresh. Surfaced in the menu so failures are not silent.
    @Published private(set) var actionError: String?

    private let colimaPath: String
    private var statusCheckTimer: Timer?

    var hasRunningInstance: Bool {
        instances.contains { $0.status.isRunning }
    }

    init() {
        self.colimaPath = Self.findColimaPath()
        startStatusChecking()
    }

    deinit {
        statusCheckTimer?.invalidate()
    }

    private static func findColimaPath() -> String {
        let possiblePaths = [
            "/opt/homebrew/bin/colima",
            "/usr/local/bin/colima",
            "/usr/bin/colima"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return "colima"
    }

    func startStatusChecking() {
        refreshInstances()
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIfIdle()
            }
        }
    }

    private func refreshIfIdle() {
        let hasTransitioning = instances.contains { $0.status.isTransitioning }
        if !hasTransitioning {
            refreshInstances()
        }
    }

    func refreshInstances() {
        Task {
            let result = await runCommand([colimaPath, "ls", "--json"])
            if result.exitCode == 0 {
                instances = merge(parsed: parseInstancesJSON(result.output))
                loadState = .loaded
                actionError = nil
            } else {
                loadState = .error(Self.friendlyError(from: result.output))
            }
        }
    }

    /// Turn raw command output into a short, user-facing message. `colima ls`
    /// failing usually means colima is missing from PATH or not installed.
    private static func friendlyError(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().contains("no such file")
            || trimmed.lowercased().contains("not found") {
            return "Colima not found. Install with: brew install colima"
        }
        return trimmed
    }

    /// Preserve in-flight transition status when replacing the instance list.
    /// colima reports the pre-transition status (Stopped/Running) while a
    /// start/stop is running, so a refresh mid-transition would otherwise wipe
    /// the .starting/.stopping overlay the UI depends on.
    private func merge(parsed: [ColimaInstance]) -> [ColimaInstance] {
        parsed.map { instance in
            if let existing = instances.first(where: { $0.name == instance.name }),
               existing.status.isTransitioning {
                var updated = instance
                updated.status = existing.status
                return updated
            }
            return instance
        }
    }

    private func parseInstancesJSON(_ output: String) -> [ColimaInstance] {
        var results: [ColimaInstance] = []

        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String,
                  let statusStr = json["status"] as? String else {
                continue
            }

            let status: ColimaStatus
            switch statusStr.lowercased() {
            case "running": status = .running
            case "stopped": status = .stopped
            default: status = .unknown
            }

            let instance = ColimaInstance(
                id: name,
                name: name,
                status: status,
                arch: json["arch"] as? String ?? "unknown",
                cpus: (json["cpus"] as? NSNumber)?.intValue ?? 0,
                memory: (json["memory"] as? NSNumber)?.uint64Value ?? 0,
                disk: (json["disk"] as? NSNumber)?.uint64Value ?? 0
            )
            results.append(instance)
        }

        return results
    }

    func start(profile: String) {
        guard let index = instances.firstIndex(where: { $0.name == profile }),
              instances[index].status.isStopped else { return }

        instances[index].status = .starting

        Task {
            let result = await runCommand([colimaPath, "start", "-p", profile])
            if let idx = instances.firstIndex(where: { $0.name == profile }) {
                instances[idx].status = result.exitCode == 0 ? .running : .stopped
            }
            actionError = result.exitCode == 0 ? nil : "Failed to start \(profile)"
        }
    }

    func stop(profile: String) {
        guard let index = instances.firstIndex(where: { $0.name == profile }),
              instances[index].status.isRunning else { return }

        instances[index].status = .stopping

        Task {
            let result = await runCommand([colimaPath, "stop", "-p", profile])
            if let idx = instances.firstIndex(where: { $0.name == profile }) {
                instances[idx].status = result.exitCode == 0 ? .stopped : .running
            }
            actionError = result.exitCode == 0 ? nil : "Failed to stop \(profile)"
        }
    }

    private func runCommand(_ arguments: [String]) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                process.environment = environment

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    continuation.resume(returning: (output, process.terminationStatus))
                } catch {
                    continuation.resume(returning: ("Error: \(error.localizedDescription)", 1))
                }
            }
        }
    }
}
