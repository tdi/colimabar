import Foundation

enum ColimaStatus: Equatable {
    case running
    case stopped
    case checking
    case starting
    case stopping

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .checking: return "Checking..."
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        }
    }
}

@MainActor
final class ColimaManager: ObservableObject {
    @Published private(set) var status: ColimaStatus = .checking

    private let colimaPath: String
    private var statusCheckTimer: Timer?

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
        checkStatus()
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkStatusIfIdle()
            }
        }
    }

    private func checkStatusIfIdle() async {
        guard status == .running || status == .stopped || status == .checking else {
            return
        }
        checkStatus()
    }

    func checkStatus() {
        Task {
            let result = await runCommand([colimaPath, "status"])
            if result.exitCode == 0 {
                status = .running
            } else {
                status = .stopped
            }
        }
    }

    func start() {
        guard status == .stopped else { return }
        status = .starting

        Task {
            let result = await runCommand([colimaPath, "start"])
            if result.exitCode == 0 {
                status = .running
            } else {
                status = .stopped
            }
        }
    }

    func stop() {
        guard status == .running else { return }
        status = .stopping

        Task {
            let result = await runCommand([colimaPath, "stop"])
            if result.exitCode == 0 {
                status = .stopped
            } else {
                status = .running
            }
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

                // Set PATH to include homebrew
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
