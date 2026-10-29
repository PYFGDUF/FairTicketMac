import Foundation

/// Drives the Python engine as a child process over a JSON-Lines pipe.
///
/// Responsibilities are deliberately narrow: locate the engine, keep the process
/// alive, correlate replies with requests, and fan events and log batches out to
/// subscribers.  It holds no booking state, so it can be exercised from a CLI probe
/// without a window.
///
/// Threading: every mutable field is guarded by one lock, and continuations and
/// stream continuations are always resumed *after* the lock is released, so a
/// resumption can never re-enter this object while it is held.
public final class SidecarClient {

    // MARK: Errors

    public enum ClientError: LocalizedError {
        case notRunning
        case terminated(exitCode: Int32, stderr: String)
        case timedOut(command: String, seconds: TimeInterval)
        case remote(errorType: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .notRunning:
                return "引擎进程未运行。"
            case .terminated(let exitCode, let stderr):
                let detail = stderr.isEmpty ? "（stderr 为空）" : "\n\(stderr)"
                return "引擎进程已退出（退出码 \(exitCode)）。\(detail)"
            case .timedOut(let command, let seconds):
                return "指令 \(command) 在 \(Int(seconds)) 秒内没有响应。"
            case .remote(let errorType, let message):
                return "\(message)（\(errorType)）"
            }
        }
    }

    public struct Configuration {
        /// Generous by default: `update_stations` fetches the full station list.
        public var requestTimeout: TimeInterval = 60
        public var handshakeTimeout: TimeInterval = 30
        /// Extra environment for the child, e.g. `FAIRTICKET_DATA_DIR` in tests.
        public var environment: [String: String] = [:]
        public init() {}
    }

    // MARK: State

    private let configuration: Configuration
    /// Serial queue for stdin writes, so a full pipe never blocks the caller.
    private let writeQueue = DispatchQueue(label: "fairticket.sidecar.stdin")
    private let lock = NSRecursiveLock()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrTail: [String] = []

    private var nextRequestID = 0
    private var pending: [Int: CheckedContinuation<Reply, Error>] = [:]
    private var handshake: CheckedContinuation<Capabilities, Error>?
    private var eventStreams: [UUID: AsyncStream<RuntimeEvent>.Continuation] = [:]
    private var logStreams: [UUID: AsyncStream<[LogEntry]>.Continuation] = [:]

    public private(set) var capabilities: Capabilities?
    public private(set) var launchSpec: EngineLocator.LaunchSpec?
    public private(set) var isRunning = false

    /// Called on an arbitrary queue when the child exits, for whatever reason.
    public var onTermination: ((Int32) -> Void)?

    private static let newline = Data([0x0A])
    private static let stderrTailLimit = 40

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Locking helper

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Lifecycle

    /// Start the engine and complete the handshake.
    @discardableResult
    public func launch(spec: EngineLocator.LaunchSpec? = nil) async throws -> Capabilities {
        let resolved = try spec ?? EngineLocator.resolve()
        launchSpec = resolved

        let process = Process()
        process.executableURL = resolved.executableURL
        process.arguments = resolved.arguments
        process.currentDirectoryURL = resolved.workingDirectoryURL
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environment { environment[key] = value }
        // Keep the child's own diagnostics out of the frame stream and make its
        // output deterministic regardless of the parent's locale.
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        withLock {
            self.process = process
            stdinHandle = stdinPipe.fileHandleForWriting
            stdoutHandle = stdoutPipe.fileHandleForReading
            stderrHandle = stderrPipe.fileHandleForReading
            stdoutBuffer.removeAll()
            stderrTail.removeAll()
            // A retry must answer for *this* child.  `awaitHandshake` returns the stored
            // value as soon as it sees one, because a fast engine can say hello before the
            // caller gets there — so leaving the previous process's capabilities in place
            // made the retry of a crashed engine come back instantly with a dead engine's
            // answer, and the app went on to treat that as the new one's.
            capabilities = nil
            isRunning = true
        }

        startReading()
        process.terminationHandler = { [weak self] finished in
            self?.handleTermination(exitCode: finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            withLock { isRunning = false }
            throw ClientError.terminated(exitCode: -1, stderr: "无法启动引擎: \(error.localizedDescription)")
        }

        return try await awaitHandshake(timeout: configuration.handshakeTimeout)
    }

    private func awaitHandshake(timeout: TimeInterval) async throws -> Capabilities {
        // A fast engine may already have produced the hello frame before we get
        // here, so check the stored value first.
        if let existing = withLock({ capabilities }) { return existing }

        return try await withCheckedThrowingContinuation { continuation in
            let installed = withLock { () -> Bool in
                guard isRunning else { return false }
                handshake = continuation
                return true
            }
            guard installed else {
                continuation.resume(
                    throwing: ClientError.terminated(
                        exitCode: -1,
                        stderr: withLock { stderrTail.joined(separator: "\n") }
                    )
                )
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self else { return }
                let waiter = self.withLock { () -> CheckedContinuation<Capabilities, Error>? in
                    defer { self.handshake = nil }
                    return self.handshake
                }
                waiter?.resume(throwing: ClientError.timedOut(command: "handshake", seconds: timeout))
            }
        }
    }

    /// Ask the engine to shut down, then make sure the process is gone.
    public func shutdown() async {
        if withLock({ isRunning }) {
            _ = try? await send("shutdown", timeout: 8)
        }
        let process = withLock { self.process }
        guard let process, process.isRunning else { return }
        // The bridge exits on its own after draining; terminate only if it lingers.
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate() }
    }

    // MARK: Reading

    private func startReading() {
        guard let stdoutHandle, let stderrHandle else { return }

        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.ingest(stdout: data)
        }

        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.ingest(stderr: data)
        }
    }

    private func ingest(stdout data: Data) {
        var frames: [SidecarFrame] = []
        withLock {
            stdoutBuffer.append(data)
            while let range = stdoutBuffer.range(of: Self.newline) {
                let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<range.lowerBound)
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<range.upperBound)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let frame = SidecarFrame.decode(line: trimmed) {
                    frames.append(frame)
                }
                // An undecodable line is dropped rather than fatal: the bridge
                // redirects stray output to stderr, so this should never happen,
                // and one bad byte must not kill a running task.
            }
        }
        for frame in frames { deliver(frame) }
    }

    private func ingest(stderr data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        withLock {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                stderrTail.append(String(line))
            }
            if stderrTail.count > Self.stderrTailLimit {
                stderrTail.removeFirst(stderrTail.count - Self.stderrTailLimit)
            }
        }
    }

    private func deliver(_ frame: SidecarFrame) {
        switch frame {
        case .hello(let capabilities):
            withLock { self.capabilities = capabilities }
            let waiter = withLock { () -> CheckedContinuation<Capabilities, Error>? in
                defer { handshake = nil }
                return handshake
            }
            waiter?.resume(returning: capabilities)

        case .reply(let reply):
            let waiter = withLock { () -> CheckedContinuation<Reply, Error>? in
                guard let id = reply.id else { return nil }
                return pending.removeValue(forKey: id)
            }
            waiter?.resume(returning: reply)

        case .event(let event):
            let streams = withLock { Array(eventStreams.values) }
            for stream in streams { stream.yield(event) }

        case .log(let entries):
            let streams = withLock { Array(logStreams.values) }
            for stream in streams { stream.yield(entries) }
        }
    }

    private func handleTermination(exitCode: Int32) {
        // Drain everything that needs resuming while holding the lock, then
        // release it before touching any continuation: resuming must never
        // re-enter this object with the lock held.
        let drained = withLock {
            () -> (
                orphans: [CheckedContinuation<Reply, Error>],
                waiter: CheckedContinuation<Capabilities, Error>?,
                events: [AsyncStream<RuntimeEvent>.Continuation],
                logs: [AsyncStream<[LogEntry]>.Continuation],
                stderrText: String
            ) in
            let orphans = Array(pending.values)
            pending.removeAll()
            let waiter = handshake
            handshake = nil
            let events = Array(eventStreams.values)
            let logs = Array(logStreams.values)
            eventStreams.removeAll()
            logStreams.removeAll()
            let stderrText = stderrTail.joined(separator: "\n")
            isRunning = false
            process = nil
            stdinHandle = nil
            stdoutHandle?.readabilityHandler = nil
            stderrHandle?.readabilityHandler = nil
            stdoutHandle = nil
            stderrHandle = nil
            return (orphans, waiter, events, logs, stderrText)
        }

        let error = ClientError.terminated(exitCode: exitCode, stderr: drained.stderrText)
        for orphan in drained.orphans { orphan.resume(throwing: error) }
        drained.waiter?.resume(throwing: error)
        for stream in drained.events { stream.finish() }
        for stream in drained.logs { stream.finish() }
        onTermination?(exitCode)
    }

    // MARK: Streams

    /// Runtime events.  Buffers the newest 10 000 frames, so a stalled consumer
    /// loses old progress events but never the terminal `exit` frame.
    public func events() -> AsyncStream<RuntimeEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(10_000)) { continuation in
            withLock { eventStreams[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.withLock { _ = self.eventStreams.removeValue(forKey: id) }
            }
        }
    }

    /// Already-redacted log batches.  The engine only emits one batch per ~100 ms,
    /// so a small buffer is plenty.
    public func logs() -> AsyncStream<[LogEntry]> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(500)) { continuation in
            withLock { logStreams[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.withLock { _ = self.logStreams.removeValue(forKey: id) }
            }
        }
    }

    // MARK: Commands

    @discardableResult
    private func send(
        _ command: String,
        _ payload: [String: JSONValue] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> Reply {
        let id = withLock { () -> Int in
            nextRequestID += 1
            return nextRequestID
        }

        var frame: [String: JSONValue] = [
            "id": .number(Double(id)),
            "cmd": .string(command),
        ]
        for (key, value) in payload { frame[key] = value }
        var line = try JSONEncoder().encode(JSONValue.object(frame))
        line.append(contentsOf: Self.newline)

        let seconds = timeout ?? configuration.requestTimeout

        let reply = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, Error>) in
            let registered = withLock { () -> Bool in
                guard isRunning, stdinHandle != nil else { return false }
                pending[id] = continuation
                return true
            }
            guard registered else {
                continuation.resume(throwing: ClientError.notRunning)
                return
            }

            writeQueue.async { [weak self] in
                guard let self else { return }
                let handle = self.withLock { self.stdinHandle }
                guard let handle else {
                    let orphan = self.withLock { self.pending.removeValue(forKey: id) }
                    orphan?.resume(throwing: ClientError.notRunning)
                    return
                }
                do {
                    try handle.write(contentsOf: line)
                } catch {
                    let orphan = self.withLock { self.pending.removeValue(forKey: id) }
                    orphan?.resume(
                        throwing: ClientError.remote(
                            errorType: "WriteFailed",
                            message: "写入引擎失败: \(error.localizedDescription)"
                        )
                    )
                }
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard let self else { return }
                let orphan = self.withLock { self.pending.removeValue(forKey: id) }
                orphan?.resume(throwing: ClientError.timedOut(command: command, seconds: seconds))
            }
        }

        guard reply.ok else {
            throw ClientError.remote(
                errorType: reply.errorType ?? "Error",
                message: reply.error ?? "引擎返回了未说明的错误"
            )
        }
        return reply
    }

    // MARK: Typed wrappers

    public func refreshCapabilities() async throws -> Capabilities {
        let reply = try await send("capabilities")
        let capabilities: Capabilities = try reply.decode(Capabilities.self)
        withLock { self.capabilities = capabilities }
        return capabilities
    }

    public func validate(_ settings: [String: JSONValue]) async throws -> ValidationResult {
        let reply = try await send("validate", ["settings": .object(settings)])
        return try reply.decode(ValidationResult.self)
    }

    /// The engine's own description of the attempt scope and order.
    public func preview(_ settings: [String: JSONValue]) async throws -> CartPreview {
        let reply = try await send("preview", ["settings": .object(settings)])
        return try reply.decode(CartPreview.self)
    }

    public func stations() async throws -> [String] {
        struct Payload: Decodable { let names: [String]; let count: Int }
        let reply = try await send("stations")
        return try reply.decode(Payload.self).names
    }

    /// Network call; can take a while on a slow link.
    @discardableResult
    public func updateStations() async throws -> Int {
        struct Payload: Decodable { let count: Int }
        let reply = try await send("update_stations", timeout: 120)
        return try reply.decode(Payload.self).count
    }

    public func loadSettings(path: String) async throws -> [String: JSONValue] {
        struct Payload: Decodable { let settings: [String: JSONValue] }
        let reply = try await send("load_settings", ["path": .string(path)])
        return try reply.decode(Payload.self).settings
    }

    public func saveSettings(path: String, settings: [String: JSONValue]) async throws {
        try await send("save_settings", [
            "path": .string(path),
            "settings": .object(settings),
        ])
    }

    /// Starts a run.  A rejected start comes back as field errors, not an error,
    /// which is how the desktop form reports every problem at once.
    public func startTask(_ settings: [String: JSONValue]) async throws -> StartResult {
        let reply = try await send("start", ["settings": .object(settings)])
        return try reply.decode(StartResult.self)
    }

    @discardableResult
    public func stopTask() async throws -> Bool {
        struct Payload: Decodable { let stopping: Bool }
        let reply = try await send("stop")
        return try reply.decode(Payload.self).stopping
    }

    /// Forget the in-memory login so the next run must scan a fresh QR code.
    public func resetSession() async throws {
        try await send("reset_session")
    }

    /// Ask the running task for a new QR code, without stopping it.
    ///
    /// Returns false when no task is live, which is the caller's cue to forget the
    /// login instead: an expired code in a running task is replaced in place, so the
    /// user keeps the clock correction and the queue position they already waited for.
    @discardableResult
    public func refreshQR() async throws -> Bool {
        struct Payload: Decodable { let refreshing: Bool }
        let reply = try await send("refresh_qr")
        return try reply.decode(Payload.self).refreshing
    }
}

// Every mutable field is guarded by `lock`, and continuations are only ever
// resumed after it is released, so sharing an instance across tasks is safe.  The
// compiler cannot see that through the lock, hence the unchecked conformance.
extension SidecarClient: @unchecked Sendable {}