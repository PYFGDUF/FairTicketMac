import Foundation

/// Works out how to start the Python engine.
///
/// Three shapes are supported, checked in this order, so the same SwiftUI app runs
/// against a frozen bundle in a shipped build and against a checkout during
/// development without a rebuild:
///
///   1. `FAIRTICKET_ENGINE` — path to a frozen engine executable.
///   2. `Contents/Resources/engine/run-sidecar` inside the app bundle, which is
///      where the PyInstaller output is copied when packaging.
///   3. A development checkout, run with its own interpreter.
///
/// Anything that fails here must say exactly which paths were tried: a silent
/// "engine missing" is the hardest failure to diagnose from inside a GUI app.
public enum EngineLocator {

    public struct LaunchSpec: Equatable, Sendable {
        public enum Shape: String, Sendable {
            case frozenExecutable = "frozen"
            case developmentCheckout = "development"
        }

        public let executableURL: URL
        public let arguments: [String]
        public let workingDirectoryURL: URL
        public let shape: Shape
        /// Where the engine package lives, for diagnostics.
        public let sourceDescription: String
    }

    public struct LookupFailure: LocalizedError {
        public let attempted: [String]

        public var errorDescription: String? {
            "找不到 Python 引擎。已尝试：\n" + attempted.map { "  · \($0)" }.joined(separator: "\n")
        }
    }

    // MARK: Entry point

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) throws -> LaunchSpec {
        var attempted: [String] = []

        // 1. Explicit frozen engine.
        if let raw = environment["FAIRTICKET_ENGINE"], !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            if fileManager.isExecutableFile(atPath: url.path) {
                return LaunchSpec(
                    executableURL: url,
                    arguments: [],
                    workingDirectoryURL: url.deletingLastPathComponent(),
                    shape: .frozenExecutable,
                    sourceDescription: "FAIRTICKET_ENGINE=\(url.path)"
                )
            }
            attempted.append("FAIRTICKET_ENGINE 指向的文件不可执行: \(url.path)")
        } else {
            attempted.append("FAIRTICKET_ENGINE 未设置")
        }

        // 2. Frozen engine shipped inside the bundle.
        let bundled = bundleURL
            .appendingPathComponent("Contents/Resources/engine/run-sidecar")
        if fileManager.isExecutableFile(atPath: bundled.path) {
            return LaunchSpec(
                executableURL: bundled,
                arguments: [],
                workingDirectoryURL: bundled.deletingLastPathComponent(),
                shape: .frozenExecutable,
                sourceDescription: "应用内置引擎 \(bundled.path)"
            )
        }
        attempted.append("应用内置引擎不存在: \(bundled.path)")

        // 3. Development checkout.
        let repo = locateCheckout(
            environment: environment,
            bundleURL: bundleURL,
            fileManager: fileManager,
            attempted: &attempted
        )
        if let repo {
            if let interpreter = locateInterpreter(in: repo, fileManager: fileManager) {
                return LaunchSpec(
                    executableURL: interpreter,
                    arguments: ["-m", "ticket_app.sidecar"],
                    workingDirectoryURL: repo,
                    shape: .developmentCheckout,
                    sourceDescription: "开发检出 \(repo.path)（解释器 \(interpreter.path)）"
                )
            }
            attempted.append("在 \(repo.path) 下未找到 .venv/bin/python 或 python3.12/python3")
        }

        throw LookupFailure(attempted: attempted)
    }

    // MARK: Checkout search

    /// Walk up from the bundle looking for a sibling checkout, then fall back to a
    /// few conventional locations.
    private static func locateCheckout(
        environment: [String: String],
        bundleURL: URL,
        fileManager: FileManager,
        attempted: inout [String]
    ) -> URL? {
        if let raw = environment["FAIRTICKET_REPO"], !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            if isCheckout(url, fileManager: fileManager) { return url }
            attempted.append("FAIRTICKET_REPO 不是有效检出: \(url.path)")
        }

        var candidates: [URL] = []
        // The bundle lives in <project>/build/<app>.app, so the checkout is a
        // sibling two or three levels up.
        var directory = bundleURL
        for _ in 0..<5 {
            directory = directory.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("12306FairTicket"))
            candidates.append(directory)
        }
        candidates.append(
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/12306/12306FairTicket")
        )

        for candidate in candidates {
            if isCheckout(candidate, fileManager: fileManager) { return candidate }
        }
        attempted.append("在上述 \(candidates.count) 个候选路径中均未找到 ticket_app/sidecar.py")
        return nil
    }

    private static func isCheckout(_ url: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(
            atPath: url.appendingPathComponent("ticket_app/sidecar.py").path
        )
    }

    private static func locateInterpreter(in repo: URL, fileManager: FileManager) -> URL? {
        let relative = [
            ".venv/bin/python",
            "venv/bin/python",
            ".venv/bin/python3",
        ]
        for path in relative {
            let url = repo.appendingPathComponent(path)
            if fileManager.isExecutableFile(atPath: url.path) { return url }
        }
        // Fall back to a system interpreter that satisfies the project's >= 3.12
        // requirement; the engine uses modern union syntax at class scope.
        for name in ["python3.12", "python3.13", "python3.11"] {
            if let url = which(name) { return url }
        }
        if let url = which("python3") { return url }
        return nil
    }

    private static func which(_ name: String) -> URL? {
        let searchPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ]
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}