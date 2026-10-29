import Foundation
import SwiftUI
import FairTicketKit

/// Application state and the single place that talks to the engine.
///
/// The form is generated from the engine's own `field_specs`, so this type holds
/// settings as a canonical-key dictionary rather than a struct with one property per
/// field.  List-valued fields keep the raw text the user typed: the backend already
/// splits on every separator it accepts, and duplicating that rule here would let the
/// two drift apart.  The one exception is the cart, which is modelled as `CartItem`
/// because the editor has to add, reorder and remove entries rather than show text.
@MainActor
public final class AppModel: ObservableObject {

    // MARK: Engine connection

    enum EngineState: Equatable {
        case idle
        case connecting
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    // MARK: Run state

    enum RunState: Equatable {
        case idle
        /// A start was requested but the engine has not reported a phase yet.
        case starting
        case running
        case finished(RunOutcome)
    }

    @Published private(set) var engineState: EngineState = .idle
    @Published private(set) var capabilities: Capabilities?
    @Published private(set) var engineDescription = ""
    /// One-line origin of the engine for the sidebar footer; the full path stays in
    /// the tooltip, because a wrapped absolute path in a 200pt column reads as an
    /// error message.
    @Published private(set) var engineSourceLabel = ""
    @Published private(set) var stationNames: [String] = []

    @Published var settings: [String: JSONValue] = [:]
    /// The half-filled「添加备选」row.  On the model rather than in a view's own state so
    /// switching sidebar pages does not throw away a station pair just typed — the
    /// desktop window deliberately preserves the same draft when it resets the
    /// advanced parameters.
    @Published var cartDraft = CartDraft()
    @Published private(set) var fieldErrors: [String: String] = [:]
    @Published private(set) var isValidating = false
    /// True once the user has asked for a check.  Gates the red marks: the engine
    /// validates on every edit, but accusing a half-typed station name is noise.
    @Published private(set) var showsFieldErrors = false
    /// The engine's own description of the cart, its scope and its attempt order.
    @Published private(set) var preview: CartPreview?

    @Published private(set) var runState: RunState = .idle
    /// A finished run whose result panel the user has not read yet.
    ///
    /// Held here rather than as a "which outcome did they close" value on `UIState`
    /// because that comparison could not survive contact with reality: `RunOutcome` is
    /// five fields, so two runs stopped the same way are *equal*, and a dismissal left
    /// over from the first swallowed the second one's panel — the screen the app must
    /// never let the user miss.  It also let ⌘↩ queue a start behind the panel, which
    /// then popped up unasked when the panel was closed.  One boolean owned by the run
    /// itself has no such failure mode, and it is what the start command is gated on.
    @Published private(set) var outcomeNeedsReview = false
    @Published private(set) var phase: RuntimeEvent.Phase?
    @Published private(set) var phaseMessage = ""
    @Published private(set) var targetTimestamp: Double?
    /// When the engine entered its high-frequency query window.  Paired with
    /// `targetTimestamp` it gives the hero panel a real progress value instead of a
    /// decorative one.
    @Published private(set) var queryStartTimestamp: Double?
    @Published private(set) var clockOffsetSeconds: Double?
    @Published private(set) var clockRTTMilliseconds: Double?
    @Published private(set) var queryCount = 0
    @Published private(set) var currentQueryInterval: Double?
    @Published private(set) var qrImageData: Data?
    @Published private(set) var qrStatus: RuntimeEvent.QRStatus?
    @Published private(set) var qrExpiresAt: Double?
    @Published private(set) var orderID: String?
    /// Contacts the 12306 account holds, as the engine counted them during this run.
    @Published private(set) var availablePassengerCount: Int?
    @Published private(set) var latestCandidate: String?
    /// The captured ticket source, split out so the running view can lay it out rather
    /// than re-parse the one-line summary.
    @Published private(set) var candidateTrain: String?
    @Published private(set) var candidateSeat: String?
    @Published private(set) var candidateStock: String?
    @Published private(set) var candidateDepartureTime: String?
    /// The cart entry the engine is working through, in the engine's own words.
    @Published private(set) var attemptLine: String?
    /// The round ceiling the engine reported with the last query, when it reports one.
    @Published private(set) var queryRoundLimit: Int?
    /// Soft-preference downgrades reported by the engine.
    @Published private(set) var preferenceWarnings: [String] = []
    /// Set when the engine stopped because the server may already hold the
    /// reservation.  The UI must block and send the user to the order page.
    @Published private(set) var safeStopMessage: String?
    @Published private(set) var serverClockReady = false

    /// Content of the pre-start confirmation, and the reason a start was refused.
    /// A task is never launched straight from a button: the desktop form always
    /// shows what the draft would attempt, and that is the last chance to catch a
    /// wrong date or a missing passenger.
    @Published private(set) var pendingStart: StartSummary?
    @Published private(set) var startBlockedMessage: String?

    @Published private(set) var logEntries: [LogEntry] = []
    @Published private(set) var isUpdatingStations = false

    /// Seconds until the release moment, recomputed on a display timer.
    @Published private(set) var remainingSeconds: Double?

    /// Whether the engine will accept a maintenance request — a fresh QR code, a
    /// session reset — at this moment.
    ///
    /// True until the engine says otherwise, which is what keeps a client paired with
    /// an engine that predates the frame working exactly as before: the control stays
    /// offered and the engine answers the request itself.  Once the frame does arrive,
    /// the answer is the engine's, not a guess made from `isRunning`.
    @Published private(set) var maintenanceEnabled = true
    @Published private(set) var maintenanceBusy = false
    /// The engine is waiting for a scan and has paused the run for it.
    @Published private(set) var maintenanceLoginRequired = false

    /// When the current run left `.starting`, and how long the last one lasted.
    ///
    /// Measured here rather than in the view: the result panel is rebuilt from state, and
    /// a clock started in its `onAppear` would read zero for however long the panel was
    /// closed and reopened.  The duration is an outcome of the run, so it is recorded
    /// when the run ends.
    private var runStartedAt: Date?
    /// Whether the engine's `initialState` has already seeded the draft.  Guards the
    /// reseed on a reconnect; see `connect()`.
    private var seededDraft = false
    /// True when the last validation request did not complete, so `fieldErrors` is a
    /// verdict about some earlier draft.  See `requestStart()`.
    private var validationIsStale = false
    @Published private(set) var lastRunDuration: TimeInterval?

    /// True when this model was filled from the captured capabilities snapshot
    /// rather than a live engine, so the interface can label itself honestly.
    private(set) var isPreviewSnapshot = false

    private let client = SidecarClient()
    private var eventTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    /// What the clock-driven readouts showed at the last published tick.  See
    /// `tickCountdown()` for why the ticker is not allowed to publish every time it
    /// wakes up.
    private var lastTickKey: Double?

    private static let logLimit = 3000
    private static let validationDebounce = Duration.milliseconds(250)

    public init() {}

    // MARK: - Connecting

    func connect() async {
        guard engineState == .idle || isFailed else { return }
        engineState = .connecting

        let events = client.events()
        let logs = client.logs()
        client.onTermination = { [weak self] code in
            Task { @MainActor in self?.handleEngineExit(code: code) }
        }

        do {
            let spec = try EngineLocator.resolve()
            engineDescription = spec.sourceDescription
            engineSourceLabel = switch spec.shape {
            case .frozenExecutable: "内置引擎（随 App 分发）"
            case .developmentCheckout: "开发检出（使用本地 Python）"
            }
            let capabilities = try await client.launch(spec: spec)
            self.capabilities = capabilities
            // The window opens on the backend's declared initial state, which is
            // deliberately not `defaults`: it clears the seat selection and the
            // train restriction so an empty train list is a valid draft.
            //
            // Once, and only once.  A reconnect after a crash comes through here again,
            // and reseeding replaced the whole draft with the engine's empty starting
            // point — the cart and the passengers gone at the exact moment the user was
            // trying to get the app working again.  A reconnect keeps what is there and
            // has the new engine check it.
            let resumingDraft = seededDraft
            if !seededDraft {
                settings = capabilities.initialState
                normalizeJourneyDate()
                seededDraft = true
            }
            engineState = .ready
            if resumingDraft { scheduleValidation() }
            consume(events: events, logs: logs)
            startTicker()
            await loadStations()
            await startDemoScenarioIfRequested()
        } catch {
            engineState = .failed(error.localizedDescription)
        }
    }

    /// Seed the journey date when the draft has none.
    ///
    /// The picker falls back to showing today, so leaving the stored value empty
    /// would show a date the form then reports as missing.  The desktop form avoids
    /// this by always reading the displayed date back, which amounts to the same
    /// default.
    private func normalizeJourneyDate() {
        let raw = string("train_date")
        if ISO8601Day.date(from: raw) == nil {
            settings["train_date"] = .string(ISO8601Day.string(from: Date()))
        }
    }

    private var isFailed: Bool {
        if case .failed = engineState { return true }
        return false
    }

    private func consume(events: AsyncStream<RuntimeEvent>, logs: AsyncStream<[LogEntry]>) {
        eventTask?.cancel()
        logTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.apply(event)
            }
        }
        logTask = Task { [weak self] in
            for await batch in logs {
                guard let self else { return }
                await self.append(logs: batch)
            }
        }
    }

    func loadStations() async {
        guard engineState.isReady, stationNames.isEmpty else { return }
        stationNames = (try? await client.stations()) ?? []
    }

    func updateStations() async {
        guard engineState.isReady, !isUpdatingStations else { return }
        isUpdatingStations = true
        defer { isUpdatingStations = false }
        do {
            _ = try await client.updateStations()
            stationNames = (try? await client.stations()) ?? stationNames
        } catch {
            appendSystemLog("更新站点失败：\(error.localizedDescription)", level: .warning)
        }
    }

    private func handleEngineExit(code: Int32) {
        switch runState {
        case .running, .starting:
            finishRun(RunOutcome(event: RuntimeEvent.terminated(exitCode: Int(code))))
        case .idle, .finished:
            break
        }
        if engineState.isReady {
            engineState = .failed("引擎进程已退出（退出码 \(code)）。请重新连接。")
        }
    }

    // MARK: - Event reduction

    /// Reduce one engine frame into the model.
    ///
    /// Internal rather than private so the test suite can replay frame sequences:
    /// `swift test` asserts on state instead of comparing screenshots.
    func apply(_ event: RuntimeEvent) {
        switch event.kind {
        case .phase:
            if let phase = event.phase {
                self.phase = phase
                if phase == .cancelled || phase == .stopped || phase == .failed {
                    phaseMessage = event.message
                } else {
                    phaseMessage = event.message.isEmpty ? phase.title : event.message
                }
            }
            // The engine reports the release moment and the warm-up start here, on the
            // `waiting` phase frame — and *only* there (`runner.py::_waiting_phase`).
            // These are the countdown's and the warm-up track's only time sources; the
            // `query` frame carries an attempt number and an interval, never a timestamp.
            if let target = event.targetTimestamp { targetTimestamp = target }
            if let start = event.queryStartTimestamp { queryStartTimestamp = start }
            if case .starting = runState {
                runState = .running
                // The one place a run begins, so the one place its clock starts.
                runStartedAt = Date()
            }

        case .clockSync:
            if let offset = event.clockOffsetSeconds { clockOffsetSeconds = offset }
            if let rtt = event.clockRTTMilliseconds { clockRTTMilliseconds = rtt }
            serverClockReady = clockOffsetSeconds != nil

        case .query:
            if let attempt = event.queryAttempt { queryCount = attempt }
            if let limit = event.queryMaxRetries { queryRoundLimit = limit }
            if let interval = event.queryIntervalSeconds { currentQueryInterval = interval }
            if let start = event.queryStartTimestamp { queryStartTimestamp = start }

        case .qrReady:
            if let data = event.qrImageData { qrImageData = data }
            if let expires = event.qrExpiresAt { qrExpiresAt = expires }
            qrStatus = .waiting

        case .qrStatus:
            if let status = event.qrStatus {
                qrStatus = status
                // The engine emits `qr_ready` and then `qr_status: waiting` back to
                // back, so clearing the image on anything that is not `logged_in`
                // made the code flash and vanish.  Drop it only when the code can no
                // longer be scanned; `waiting` and `scanned` must keep showing it.
                switch status {
                case .confirmed, .loggedIn, .expired:
                    qrImageData = nil
                case .waiting, .scanned:
                    break
                }
            }

        case .candidate:
            var parts: [String] = []
            if let train = event.candidateTrain { parts.append(train) }
            if let seat = event.candidateSeatLabel { parts.append(seat) }
            parts.append(StockToken.summary(event.candidateStock))
            latestCandidate = parts.joined(separator: " · ")
            candidateTrain = event.candidateTrain
            candidateSeat = event.candidateSeatLabel
            candidateStock = event.candidateStock
            candidateDepartureTime = event.candidateStartTime

        case .cartItem:
            // Which of the alternatives the engine is on, in the engine's own sentence.
            attemptLine = event.message

        case .queryEmpty, .queryFailed, .queryRouteMismatch, .sessionChecked:
            // Real per-round outcomes that arrive on no other channel: without this the
            // run's log would show the queries that found something and nothing else.
            // `query_failed` carries no reason — the engine writes that to the log
            // stream itself — so the message is reproduced, never expanded on.
            appendSystemLog(event.message, level: event.kind == .queryFailed || event.kind == .queryRouteMismatch ? .warning : .debug)

        case .orderWait:
            if let wait = event.waitSeconds, wait >= 0 {
                phaseMessage = "排队中，预计等待 \(Int(wait)) 秒"
            }

        case .passengers:
            // How many contacts the account actually holds — the engine's answer, read
            // off its own event rather than inferred from what was typed in.
            if let count = event.availablePassengerCount { availablePassengerCount = count }

        case .stations:
            // `count` and `cached` say whether the run is working off the bundled
            // snapshot or a refreshed cache, which is the fact a station-name error
            // turns on.
            if !event.message.isEmpty { appendSystemLog(event.message, level: .debug) }

        case .orderSuccess:
            orderID = event.orderID
            qrImageData = nil

        case .preferenceApplied, .preferenceFallback:
            if !event.message.isEmpty { preferenceWarnings.append(event.message) }

        // The engine's own answer to "may I take a maintenance request now".  It
        // refuses a code refresh while it is mid-submission and says so on every change
        // of state, so the button follows the engine rather than guessing from
        // `isRunning` — which is a different question and gives a different answer
        // during the warm-up window.
        case .maintenanceAvailability:
            if let enabled = event.maintenanceEnabled { maintenanceEnabled = enabled }
            if let busy = event.maintenanceBusy { maintenanceBusy = busy }
            if let required = event.maintenanceLoginRequired { maintenanceLoginRequired = required }

        case .error:
            if let type = event.exceptionType {
                appendSystemLog("任务异常（\(type)）：\(event.message)", level: .error)
            }

        case .exit:
            let outcome = RunOutcome(event: event)
            finishRun(outcome)
            if outcome.safeStop { safeStopMessage = event.message }
            if outcome.succeeded || outcome.safeStop { qrImageData = nil }

        default:
            break
        }
    }

    private func append(logs batch: [LogEntry]) async {
        guard !batch.isEmpty else { return }
        logEntries.append(contentsOf: batch)
        if logEntries.count > Self.logLimit {
            logEntries.removeFirst(logEntries.count - Self.logLimit)
        }
    }

    private func appendSystemLog(_ text: String, level: LogEntry.Level) {
        let stamp = Self.logTimestampFormatter.string(from: Date())
        logEntries.append(LogEntry(text: "\(stamp)  \(level.rawValue)  \(text)", levelTag: level.rawValue))
    }

    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Countdown

    /// The engine computes `offset_seconds` as *server time minus local wall-clock
    /// time*, so adding it to the local clock reproduces the server clock.  Using
    /// `Date()` alone would reintroduce exactly the skew the engine removed, which
    /// is the whole point of the tool.
    var serverNow: Double {
        Date().timeIntervalSince1970 + (clockOffsetSeconds ?? 0)
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tickCountdown()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// Advance the clock-driven readouts, but publish only when one of them would
    /// actually look different.
    ///
    /// `@Published` fires on *assignment*, not on change, so the naive version of this
    /// — assign `countdownToRelease` ten times a second — re-evaluated the entire
    /// window ten times a second forever.  With the app sitting idle and no task
    /// running, that measured at ~100% of one core, because each pass rebuilt a form
    /// of thirty fields, two columns of cards and a mesh-and-glass hero to advance a
    /// countdown that was not even on screen.
    ///
    /// One hertz is now enough for everything that reads `remainingSeconds`: the menu
    /// bar prints whole seconds, and the hero's tenths run off their own clock (see
    /// `InspectorView.heroCard`) precisely so this ticker does not have to.
    ///
    /// Internal rather than private so the publish rate can be asserted directly: the
    /// rate is invisible on screen, so nothing else would catch it regressing.
    func tickCountdown() {
        let next = countdownToRelease
        let key = tickKey(countdown: next)
        guard key != lastTickKey else { return }
        lastTickKey = key
        remainingSeconds = next
    }

    /// Everything the ticker feeds, quantised to the precision the interface prints.
    ///
    /// `nil` means no readout depends on the model's clock, which is the normal state of
    /// an idle window *and* of one waiting for a QR scan — the ticker then publishes
    /// nothing at all.  The only readout left here is the countdown; the QR code's own
    /// expiry has a clock inside the card that shows it, so the model never has to
    /// publish just to make one label tick.
    func tickKey(countdown: Double?) -> Double? {
        countdown?.rounded(.down)
    }

    /// Seconds until the release moment, from the engine's own clock.
    ///
    /// Pure, so the ticker and the tests read the same arithmetic: `offset_seconds`
    /// is "server time minus local wall clock", so the offset has to be added — a
    /// countdown built on `Date()` alone would reintroduce the skew the engine just
    /// removed.
    ///
    /// Takes its reading time as an argument so the hero can drive its own ten-hertz
    /// clock without asking the model to publish ten times a second.
    func countdown(at date: Date) -> Double? {
        guard let target = targetTimestamp else { return nil }
        return max(0, target - (date.timeIntervalSince1970 + (clockOffsetSeconds ?? 0)))
    }

    /// Seconds until the release moment, as of now.
    var countdownToRelease: Double? { countdown(at: Date()) }

    var isRunning: Bool {
        switch runState {
        case .starting, .running: return true
        case .idle, .finished: return false
        }
    }

    // MARK: - Validation

    /// Debounced field check, mirroring the desktop form's 250 ms behaviour.
    func scheduleValidation() {
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.validationDebounce)
            guard !Task.isCancelled else { return }
            await self?.validate()
        }
    }

    func validate(byRequest: Bool = false) async {
        guard engineState.isReady else { return }
        isValidating = true
        defer { isValidating = false }
        do {
            let result = try await client.validate(settings)
            validationIsStale = false
            applyValidation(result.errors, byRequest: byRequest)
        } catch {
            // The verdict from the last *completed* check is all that is left, and it is
            // not a verdict about the draft as it now stands.
            validationIsStale = true
            appendSystemLog("配置检查失败：\(error.localizedDescription)", level: .warning)
        }
        // Shown next to the train fields and reused verbatim by the start
        // confirmation, so both describe the same order.
        preview = try? await client.preview(settings)
    }

    /// Record a validation reply.
    ///
    /// Separate from the request so the presentation rules can be asserted without an
    /// engine, and so "the engine checked" stays distinct from "the user asked for a
    /// check" — only the latter makes the red marks appear.
    func applyValidation(_ errors: [String: String], byRequest: Bool) {
        fieldErrors = errors
        if byRequest { showsFieldErrors = true }
    }

    /// The inline error for a field, or nil while the user has not asked for a check.
    ///
    /// The engine validates the whole draft on every edit (debounced), but marking a
    /// station name the user is still typing reads as an accusation.  Errors appear
    /// once the user asks — the toolbar's 检查配置, an import, or a start attempt —
    /// which is also when the desktop form begins marking fields.
    func visibleFieldError(_ key: String) -> String? {
        showsFieldErrors ? fieldErrors[key] : nil
    }

    /// Fields flagged on one page, for the sidebar's warning dot.  Same gate, so the
    /// sidebar cannot accuse a draft the form is still showing as clean.
    func visibleErrorCount(in section: ConfigSection) -> Int {
        guard showsFieldErrors else { return 0 }
        return fieldErrors.keys.filter { ConfigSection.owning($0) == section }.count
    }

    /// Every problem the engine reported, behind the same gate as the inline marks.
    ///
    /// The gate is the point: the interface does not accuse a half-typed form, so any
    /// count shown to the user has to be a count the user has actually been shown.
    var visibleErrorTotal: Int { showsFieldErrors ? fieldErrors.count : 0 }

    // MARK: Running

    /// Validate the draft, then ask the user to confirm what it would attempt.
    ///
    /// The desktop form validates first and reports the offending fields instead of
    /// opening a dialog; doing the same here keeps a single entry point, so the
    /// toolbar, the menu bar command and ⌘↩ cannot start a task by different rules.
    func requestStart() async {
        guard engineState.isReady, !isRunning else { return }
        await validate(byRequest: true)
        // A check that never completed is not a verdict on the draft as it now stands.
        // The fields may already be fixed, and `start` re-validates and refuses with the
        // engine's own words — so blocking here is how a good draft gets pinned to an
        // error about a check that did not run.
        guard fieldErrors.isEmpty || validationIsStale else {
            let count = fieldErrors.count
            let first = firstFieldErrorMessage()
            startBlockedMessage = "请先修改标红的 \(count) 项参数。"
                + (first.map { "\n\n\($0)" } ?? "")
            return
        }
        pendingStart = makeStartSummary()
    }

    /// Preview only: build the pre-start briefing without an engine to validate against.
    ///
    /// `requestStart` refuses to open the briefing unless the engine has just validated
    /// the draft, which is correct — but it also makes the app's most load-bearing
    /// confirmation the one screen a screenshot cannot reach.  This builds the same
    /// payload from the same `makeStartSummary`, so what is reviewed is the real view
    /// with real values.
    func presentStartSummaryForPreview() {
        var summary = makeStartSummary()
        // Without an engine there is no `preview` payload, so the candidate list — the
        // section that carries the attempt order — would render empty.  Built here from
        // the cart itself, using the same labels the cards show.
        if summary.cartRows.isEmpty {
            summary.cartRows = cartItems.map { item in
                let train = item.trainScope == CartItem.scopeSpecific && !item.trainCode.isEmpty
                    ? item.trainCode
                    : item.scopeLabel
                return "\(train) · \(item.fromStation) → \(item.toStation) · \(item.seatType)"
            }
        }
        pendingStart = summary
    }

    /// Proceed from the confirmation dialog.
    func confirmStart() async {
        pendingStart = nil
        await startTask()
    }

    func cancelStart() {
        pendingStart = nil
    }

    func clearStartBlock() {
        startBlockedMessage = nil
    }

    /// The first reported error, read in the backend's own field order, wording
    /// included so the message matches the inline one verbatim.
    private func firstFieldErrorMessage() -> String? {
        guard let capabilities else { return fieldErrors.values.first }
        for key in capabilities.editableKeys {
            guard let message = fieldErrors[key] else { continue }
            let label = capabilities.spec(for: key)?.label ?? key
            return "\(label)：\(message)"
        }
        return fieldErrors.values.first
    }

    /// Section holding the first bad field, so the window can navigate to it.
    var firstErrorSection: ConfigSection? {
        guard let capabilities else { return nil }
        for key in capabilities.editableKeys where fieldErrors[key] != nil {
            return ConfigSection.owning(key)
        }
        return nil
    }

    /// A rendering of the draft plus the engine's own scope and attempt order.
    ///
    /// Nothing that decides the outcome is recomputed here: the cart rows, the scope
    /// and the ordering rule are the engine's own strings, so the dialog cannot
    /// promise an attempt the engine would not make.
    private func makeStartSummary() -> StartSummary {
        var summary = StartSummary()
        let items = cartItems
        summary.route = items.isEmpty ? "购物车为空" : routeLine(for: items)
        summary.date = string("train_date")

        let passengers = listItems("passenger_names")
        summary.passengers = passengers.isEmpty ? "仅监控" : passengers.joined(separator: "、")

        summary.cartRows = preview?.cartRows ?? []
        summary.scopeSummary = preview?.scopeSummary ?? ""
        summary.attemptOrder = preview?.priorityPreview ?? ""
        summary.position = positionSummary()
        summary.mode = bool("auto_submit") ? "自动提交" : "仅监控"
        summary.submitWindow = submitWindowLine
        // The seats the run would actually order, taken from the cart rather than parsed
        // back out of the engine's prose.  The dialog used to scrape these words out of
        // `cartRows`, which silently produced nothing whenever the engine reworded a row.
        summary.seatLabels = cartSeatLabels()
        return summary
    }

    /// When the run starts and when it will stop, in the terms the page uses.
    ///
    /// Both times are optional and mean different things when empty — no start means
    /// "go now", no stop means "run until the retry limit" — so each half says which it
    /// is rather than printing a blank.
    private var submitWindowLine: String {
        let start = string("start_at").trimmingCharacters(in: .whitespaces)
        let stop = string("stop_at").trimmingCharacters(in: .whitespaces)
        let from = start.isEmpty ? "立即开始" : start
        let to = stop.isEmpty ? "不设停止时间" : stop
        return "\(from) – \(to)" + (bool("auto_submit") ? " · 命中即停" : "")
    }

    /// The headline for the confirmation: the station pairs the cart covers.
    ///
    /// Deliberately built from the cart rather than from a single station pair, which
    /// no longer exists — a cart may span several routes, and printing only the first
    /// one would describe a smaller attempt than the engine is about to make.
    private func routeLine(for items: [CartItem]) -> String {
        var pairs: [String] = []
        for item in items {
            let pair = "\(item.fromStation) → \(item.toStation)"
            if !pairs.contains(pair) { pairs.append(pair) }
        }
        if pairs.count == 1 { return pairs[0] }
        return "\(pairs[0]) 等 \(pairs.count) 组站对"
    }

    /// Mirrors the desktop dialog's position line.  The seat families come from the
    /// engine's seat groups, so a seat added on the Python side is classified
    /// correctly without a Swift change; the seat list itself is derived from the
    /// cart, because version 5 has no separate seat field.
    private func positionSummary() -> String {
        guard let capabilities else { return "无启用的偏好" }
        let selected = Set(cartSeatLabels())
        let seated = Set(capabilities.seatGroups.seated)
        let berths = Set(capabilities.seatGroups.berth)
        var parts: [String] = []

        let positions = seatPositions()
        if !positions.isEmpty, selected.contains(where: seated.contains) {
            parts.append("座位关系 " + positions.joined(separator: "/"))
        }
        let counts = berthCounts()
        if counts.lower + counts.middle + counts.upper > 0,
           selected.contains(where: berths.contains) {
            parts.append("下/中/上铺 \(counts.lower)/\(counts.middle)/\(counts.upper)")
        }
        if bool("quiet_carriage_preference"), selected.contains("二等座") {
            parts.append("优先静音车厢")
        }
        return parts.isEmpty ? "无启用的偏好" : parts.joined(separator: "；")
    }

    func startTask() async {
        guard engineState.isReady, !isRunning else { return }
        resetRunState()

        do {
            let result = try await client.startTask(settings)
            if !result.started {
                // A rejected start is a request by definition: show every problem.
                applyValidation(result.errors, byRequest: true)
                runState = .idle
                phase = nil
                phaseMessage = ""
            }
        } catch {
            runState = .idle
            phase = .failed
            phaseMessage = error.localizedDescription
            appendSystemLog("启动失败：\(error.localizedDescription)", level: .error)
        }
    }

    func stopTask() async {
        guard isRunning else { return }
        phaseMessage = "正在停止…"
        do {
            // The engine's answer is the only evidence that the running task heard this.
            // Discarding it left the window reading 正在停止… over a task that was still
            // querying, with the form unreachable behind it and nothing in the log.
            if try await client.stopTask() == false {
                phaseMessage = "引擎未接受停止请求，任务仍在继续"
                appendSystemLog("引擎未接受停止请求（stopping:false），任务仍在继续。", level: .warning)
            }
        } catch {
            phaseMessage = "停止请求未送达"
            appendSystemLog("停止请求失败：\(error.localizedDescription)", level: .warning)
        }
    }

    /// The one way a run ends.
    ///
    /// Both terminal paths — the engine's `exit` frame and the child process dying
    /// without one — used to record the ending separately, and only the first of them
    /// closed the clock.  A crash therefore left the *previous* run's 本轮用时 in place,
    /// and the result panel printed it as a fact about the run that just died.
    private func finishRun(_ outcome: RunOutcome) {
        runState = .finished(outcome)
        if let started = runStartedAt {
            lastRunDuration = max(0, Date().timeIntervalSince(started))
        }
        runStartedAt = nil
        outcomeNeedsReview = true
    }

    /// The user has read the result panel.
    func acknowledgeOutcome() {
        outcomeNeedsReview = false
    }

    /// Put the model into the state a start would produce, without touching the
    /// engine.  Shared by `startTask` and the scripted demo timelines so the two
    /// cannot drift apart.
    func resetRunState() {
        safeStopMessage = nil
        preferenceWarnings.removeAll()
        latestCandidate = nil
        candidateTrain = nil
        candidateSeat = nil
        candidateStock = nil
        candidateDepartureTime = nil
        attemptLine = nil
        queryRoundLimit = nil
        queryCount = 0
        runState = .starting
        phase = .preparing
        phaseMessage = "正在准备任务"
        // Clear the previous run's clock so a stale countdown cannot linger.
        targetTimestamp = nil
        queryStartTimestamp = nil
        // And its login card: the code on screen belongs to a previous attempt, and
        // leaving it up showed an expired QR with "有效期剩余 0:00" over a run that had
        // not asked for a scan yet.
        clearLoginState()
        outcomeNeedsReview = false
    }

    /// Replay a scripted timeline through the same reducer the engine's frames use.
    ///
    /// No-op unless `FAIRTICKET_DEMO` is set; see `DemoScenario` and
    /// `script/preview.sh`.  Exists because the running-state views otherwise cannot
    /// be reviewed without scanning a real 12306 QR code.
    func startDemoScenarioIfRequested() async {
        guard let scenario = DemoScenario.requested else { return }
        resetRunState()
        for event in scenario.events() {
            apply(event)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    /// Fill the model from the captured capabilities payload instead of an engine.
    ///
    /// Used by SwiftUI Previews and the component gallery: launching Python for every
    /// preview would make each one a process spawn with a handshake delay.  Lives
    /// inside the class rather than an extension because the properties it writes are
    /// `private(set)`.
    func loadSnapshot(scenario: DemoScenario?, engineReady: Bool) {
        guard let capabilities = CapabilitiesSnapshot.load() else { return }
        self.capabilities = capabilities
        settings = capabilities.initialState
        // A plausible draft is more useful to look at than an empty form.
        settings["cart_items"] = .array([
            CartItem(
                fromStation: "北京西",
                toStation: "郑州东",
                trainScope: CartItem.scopeSpecific,
                trainCode: "G79",
                seatType: "二等座"
            ).json,
            CartItem(
                fromStation: "北京西",
                toStation: "郑州东",
                trainScope: CartItem.scopeAll,
                trainCode: "",
                seatType: "一等座"
            ).json,
        ])
        settings["passenger_names"] = .string("张三，李四")
        cartDraft = CartDraft(fromStation: "北京西", toStation: "郑州东", trainScope: CartItem.scopeAll)
        engineDescription = "预览快照（未启动引擎进程）"
        engineSourceLabel = "预览快照"
        engineState = engineReady ? .ready : .idle
        isPreviewSnapshot = true

        guard let scenario else { return }
        resetRunState()
        for event in scenario.events() { apply(event) }
    }

    /// Preview/gallery only: a handful of synthetic, already-redacted log lines, so
    /// the log page and the floating strip have something to show.
    func seedPreviewLog() {
        let lines: [(String, LogEntry.Level)] = [
            ("15:03:41  INFO  已校准服务器时间，偏移 0.183s，RTT 42ms", .info),
            ("15:03:42  INFO  已载入 3365 个站名", .info),
            ("15:03:44  INFO  会话已复用，无需重新扫码", .info),
            ("15:03:47  DEBUG  第 1 次查询：北京西 → 郑州东 2026-09-28", .debug),
            ("15:03:51  WARNING  12306 未开放座位关系选择；订单仍会提交，位置由系统分配", .warning),
            ("15:03:53  INFO  G79 二等座 余票 有，进入提交", .info),
            ("15:03:54  INFO  排队中，预计等待 12 秒", .info),
        ]
        logEntries.append(contentsOf: lines.map { LogEntry(text: $0.0, levelTag: $0.1.rawValue) })
    }

    /// Forget the login so the next run scans a fresh QR code.
    func resetSession() async {
        guard engineState.isReady else { return }
        do {
            try await client.resetSession()
            clearLoginState()
        } catch {
            appendSystemLog("重新扫码失败：\(error.localizedDescription)", level: .warning)
        }
    }

    /// 重新扫码.
    ///
    /// Two different jobs depending on whether a task is live, because they need
    /// different engine commands: a running task gets a fresh code and carries on
    /// (the point being that a code the user could not scan in time must not cost
    /// them the run), while an idle app just forgets the login so the next run starts
    /// clean.
    func refreshLogin() async {
        guard engineState.isReady else { return }
        guard isRunning else {
            await resetSession()
            return
        }
        do {
            let refreshing = try await client.refreshQR()
            appendSystemLog(
                refreshing
                    ? "已请求新的二维码，任务继续运行"
                    : "引擎当前没有正在运行的任务；重新开始后会显示新的二维码",
                level: refreshing ? .info : .warning
            )
        } catch {
            appendSystemLog("刷新二维码失败：\(error.localizedDescription)", level: .warning)
        }
    }

    /// Drop the in-memory login state.  One place, so "重新扫码" and the tests cannot
    /// disagree about what forgetting a login means.
    func clearLoginState() {
        qrImageData = nil
        qrStatus = nil
        qrExpiresAt = nil
    }

    func clearLog() {
        logEntries.removeAll()
    }

    /// Dismiss the safe-stop notice.  The engine refused to continue because the
    /// server may already hold the reservation, so the only correct next step is
    /// checking the official order page — never retrying automatically.
    func clearSafeStop() {
        safeStopMessage = nil
    }

    /// Where the desktop form's "打开 12306 订单" button points.
    var orderURL: URL? {
        guard let raw = capabilities?.orderURL else { return nil }
        return URL(string: raw)
    }

    // MARK: - Login card

    /// Whether a phone-scannable code should be on screen.
    ///
    /// A named rule rather than an inline `qrImageData != nil`, because the wrong
    /// version of it — clearing the image on any status that was not `logged_in` —
    /// made the code disappear the instant it arrived: the engine sends
    /// `qr_ready` and `qr_status: waiting` back to back.  Tests assert this.
    var showsLoginCode: Bool { qrImageData != nil }

    /// What the empty slot says.  It has to explain *why* the code is gone, since
    /// disappearing is correct after a scan and after an expiry.
    var loginSlot: LoginSlot {
        switch qrStatus {
        case .loggedIn:
            return LoginSlot(systemImage: "checkmark.seal.fill", text: "已登录\n无需重新扫码")
        case .confirmed:
            return LoginSlot(systemImage: "checkmark.seal.fill", text: "登录成功")
        case .expired:
            return LoginSlot(systemImage: "arrow.clockwise", text: "二维码已过期\n正在获取新二维码")
        case .waiting, .scanned, nil:
            return LoginSlot(systemImage: "qrcode", text: "开始任务后\n显示二维码")
        }
    }

    // MARK: - Settings helpers

    func string(_ key: String) -> String {
        settings[key]?.stringValue ?? ""
    }

    func setString(_ key: String, _ value: String) {
        settings[key] = .string(value)
        scheduleValidation()
    }

    func bool(_ key: String) -> Bool {
        settings[key]?.boolValue ?? false
    }

    func setBool(_ key: String, _ value: Bool) {
        settings[key] = .bool(value)
        scheduleValidation()
    }

    func double(_ key: String) -> Double {
        settings[key]?.doubleValue ?? 0
    }

    func setDouble(_ key: String, _ value: Double) {
        settings[key] = .number(value)
        scheduleValidation()
    }

    func int(_ key: String) -> Int {
        settings[key]?.intValue ?? 0
    }

    func setInt(_ key: String, _ value: Int) {
        settings[key] = .number(Double(value))
        scheduleValidation()
    }

    func stringList(_ key: String) -> [String] {
        settings[key]?.stringArrayValue ?? []
    }

    func setStringList(_ key: String, _ value: [String]) {
        settings[key] = .array(value.map { .string($0) })
        scheduleValidation()
    }

    /// One line of text for a list-valued field.
    ///
    /// The form keeps what the user typed, including the separators, because the
    /// backend splits on every separator it accepts.  After an import the value is
    /// already an array, so it has to render too — the desktop form does the same
    /// with "，".joined(...).
    func listText(_ key: String) -> String {
        if let raw = settings[key]?.stringValue { return raw }
        if let items = settings[key]?.stringArrayValue { return items.joined(separator: "，") }
        return ""
    }

    func setListText(_ key: String, _ value: String) {
        settings[key] = .string(value)
        // Ticket-type overrides are keyed by passenger name, so editing the list can
        // strand one on a name that no longer exists.
        if key == "passenger_names" { pruneTicketTypes() }
        scheduleValidation()
    }

    /// Items of a list-valued field, split the way the desktop form does.
    ///
    /// Display only: the raw text is what gets submitted, and the backend performs
    /// its own split.  Reusing one helper keeps the sidebar summary, the start
    /// confirmation and the passenger count from disagreeing about how many were
    /// typed.
    func listItems(_ key: String) -> [String] {
        listText(key)
            .split(whereSeparator: { ",，、;；\n\t".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Import / export

    func saveSettings(to url: URL) async {
        do {
            try await client.saveSettings(path: url.path, settings: settings)
            appendSystemLog("已保存 version 5 JSON 配置：\(url.path)", level: .info)
        } catch {
            appendSystemLog("保存失败：\(error.localizedDescription)", level: .error)
        }
    }

    /// Import goes through the backend, so the version-5 contract lives in exactly
    /// one place: an older file describes a single-route world the engine no longer
    /// accepts, and the engine's own message says so.
    func importSettings(from url: URL) async {
        do {
            let loaded = try await client.loadSettings(path: url.path)
            settings = loaded
            // The user asked for this file, so report what is wrong with it.
            await validate(byRequest: true)
            appendSystemLog("已导入 JSON 配置：\(url.path)", level: .info)
        } catch {
            appendSystemLog("导入失败：\(error.localizedDescription)", level: .error)
        }
    }

    /// Restore the packaged defaults for the advanced page only.
    func resetAdvancedDefaults() {
        guard let capabilities else { return }
        for key in capabilities.editableKeys {
            guard let spec = capabilities.spec(for: key), spec.page == "advanced" else { continue }
            if let value = capabilities.defaults[key] { settings[key] = value }
        }
        scheduleValidation()
    }

    // MARK: - Cart

    /// The ordered alternatives the engine will attempt, in cart order.
    ///
    /// Version 5 keeps every journey choice inside `cart_items`: there is no separate
    /// station pair or `seat_types` list any more, so this is the single source of
    /// truth for the route, the trains and the seats alike.  Rendered as a real type
    /// rather than poked at as nested `JSONValue` so the editor can add, reorder and
    /// delete entries without every view re-deriving the shape.
    var cartItems: [CartItem] {
        (settings["cart_items"]?.arrayValue ?? []).compactMap(CartItem.init(json:))
    }

    func setCart(_ items: [CartItem]) {
        settings["cart_items"] = .array(items.map(\.json))
        scheduleValidation()
    }

    /// Seat products the cart would attempt, in cart order and without repeats.
    ///
    /// The engine derives `seat_types` from the cart, so deriving it the same way
    /// here is what keeps the seat map and the berth editor gated on exactly the
    /// seats that will actually be tried.
    func cartSeatLabels() -> [String] {
        var labels: [String] = []
        for item in cartItems where !item.seatType.isEmpty {
            if !labels.contains(item.seatType) { labels.append(item.seatType) }
        }
        return labels
    }

    func removeCartItem(_ id: String) {
        setCart(cartItems.filter { $0.id != id })
    }

    /// Reorder without re-validating: the attempt order cannot make a form invalid,
    /// and a drag produces a burst of these.
    func moveCartItem(_ id: String, to targetID: String) {
        var items = cartItems
        guard
            let from = items.firstIndex(where: { $0.id == id }),
            let to = items.firstIndex(where: { $0.id == targetID }),
            from != to
        else { return }
        let moved = items.remove(at: from)
        items.insert(moved, at: to)
        settings["cart_items"] = .array(items.map(\.json))
    }

    /// Split a train list the way the engine's `normalize_train_codes` does: every
    /// separator the desktop form accepts, trimmed, upper-cased, de-duplicated.
    ///
    /// Display and drafting only — the raw text is what gets submitted, and the
    /// backend performs its own split and normalisation.
    static func splitTrainCodes(_ text: String) -> [String] {
        var codes: [String] = []
        for piece in text.split(whereSeparator: { ",，、;；\n\t ".contains($0) }) {
            let code = piece.trimmingCharacters(in: .whitespaces).uppercased()
            if !code.isEmpty, !codes.contains(code) { codes.append(code) }
        }
        return codes
    }

    /// The entries the draft row would add: one per chosen seat and train.
    ///
    /// Mirrors the desktop window's expansion rule — seats outer, trains inner — so
    /// the add button's「N 项」count and what actually lands in the cart cannot
    /// disagree.  An entry with no seat chosen yields nothing at all rather than a
    /// half-formed item the validator would reject.
    func cartDraftEntries() -> [CartItem] {
        let seats = cartDraft.seatTypes
        guard !seats.isEmpty else { return [] }
        let trains: [String]
        if cartDraft.trainScope == CartItem.scopeSpecific {
            trains = Self.splitTrainCodes(cartDraft.trainCode)
            guard !trains.isEmpty else { return [] }
        } else {
            trains = [""]
        }

        let from = cartDraft.fromStation.trimmingCharacters(in: .whitespaces)
        let to = cartDraft.toStation.trimmingCharacters(in: .whitespaces)
        var seen: Set<String> = []
        var entries: [CartItem] = []
        for seat in seats {
            for train in trains {
                let item = CartItem(
                    fromStation: from,
                    toStation: to,
                    trainScope: cartDraft.trainScope,
                    trainCode: train,
                    seatType: seat
                )
                guard seen.insert(item.id).inserted else { continue }
                entries.append(item)
            }
        }
        return entries
    }

    /// Entries the draft would add that are not already in the cart.  The engine
    /// rejects an exact duplicate outright, so the button adds only the difference.
    func pendingCartAdditions() -> [CartItem] {
        let existing = Set(cartItems.map(\.id))
        return cartDraftEntries().filter { !existing.contains($0.id) }
    }

    /// Add the draft's entries and clear the seats, so a second seat can be added to
    /// the same route without retyping the stations.  Returns false when there was
    /// nothing to add.
    @discardableResult
    func commitCartDraft() -> Bool {
        let additions = pendingCartAdditions()
        guard !additions.isEmpty else { return false }
        setCart(cartItems + additions)
        cartDraft.seatTypes = []
        return true
    }

    // MARK: Draft entry

    /// The「添加备选」row: one station pair, one train scope, any number of seats.
    struct CartDraft: Equatable {
        var fromStation = ""
        var toStation = ""
        var trainScope = CartItem.scopeAll
        var trainCode = ""
        var seatTypes: [String] = []
    }

    func toggleDraftSeat(_ label: String) {
        if let index = cartDraft.seatTypes.firstIndex(of: label) {
            cartDraft.seatTypes.remove(at: index)
        } else {
            cartDraft.seatTypes.append(label)
        }
    }

    func swapDraftStations() {
        let from = cartDraft.fromStation
        cartDraft.fromStation = cartDraft.toStation
        cartDraft.toStation = from
    }

    /// Reset the composer back to its opening state.
    ///
    /// The stations go too, unlike after a successful add: 清空 is the button for
    /// "I am starting over", whereas adding keeps the route so a second seat can be
    /// added to the same pair without retyping it.
    func clearCartDraft() {
        cartDraft = CartDraft()
    }

    /// The draft's train codes, in the order they were entered.
    ///
    /// The field stores one string because that is what a text field gives back; the
    /// composer shows it as chips, so the split lives here rather than in the view.
    var draftTrainCodes: [String] {
        Self.splitTrainCodes(cartDraft.trainCode)
    }

    func removeDraftTrainCode(_ code: String) {
        cartDraft.trainCode = draftTrainCodes.filter { $0 != code }.joined(separator: "，")
    }

    // MARK: - Passenger ticket types

    /// Explicit ticket-type overrides, keyed by passenger name.
    func ticketTypes() -> [String: String] {
        (settings["passenger_ticket_types"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
    }

    /// One passenger's override, or "" for「跟随 12306 联系人记录」.
    func ticketType(for passenger: String) -> String {
        ticketTypes()[passenger] ?? ""
    }

    func setTicketType(_ value: String, for passenger: String) {
        var overrides = ticketTypes()
        if value.isEmpty {
            overrides.removeValue(forKey: passenger)
        } else {
            overrides[passenger] = value
        }
        settings["passenger_ticket_types"] = .object(overrides.mapValues { .string($0) })
        scheduleValidation()
    }

    /// Drop overrides for names no longer in the passenger list.
    ///
    /// The engine rejects an override naming an unselected passenger, so leaving one
    /// behind after a name is edited would fail validation with a message about a
    /// passenger the form no longer shows.
    private func pruneTicketTypes() {
        let names = Set(listItems("passenger_names"))
        let kept = ticketTypes().filter { names.contains($0.key) }
        settings["passenger_ticket_types"] = .object(kept.mapValues { .string($0) })
    }

    // MARK: - Soft preference helpers

    func seatPositions() -> [String] {
        settings["seat_position_preferences"]?.stringArrayValue ?? []
    }

    func toggleSeatPosition(_ position: String) {
        var positions = seatPositions()
        if let index = positions.firstIndex(of: position) {
            positions.remove(at: index)
        } else {
            positions.append(position)
            positions.sort()
        }
        settings["seat_position_preferences"] = .array(positions.map { .string($0) })
        scheduleValidation()
    }

    func berthCounts() -> (lower: Int, middle: Int, upper: Int) {
        let object = settings["berth_preference"]?.objectValue ?? [:]
        return (
            object["lower"]?.intValue ?? 0,
            object["middle"]?.intValue ?? 0,
            object["upper"]?.intValue ?? 0
        )
    }

    func setBerth(lower: Int, middle: Int, upper: Int) {
        settings["berth_preference"] = .object([
            "lower": .number(Double(max(0, lower))),
            "middle": .number(Double(max(0, middle))),
            "upper": .number(Double(max(0, upper))),
        ])
        scheduleValidation()
    }

    /// Seat product currently driving the seat map's available letters.
    func selectedSeatProducts() -> [SeatSpec] {
        guard let capabilities else { return [] }
        return cartSeatLabels().compactMap { label in
            capabilities.seats.first { $0.label == label }
        }
    }

    /// Berth products the user selected, e.g. 硬卧 or 一等卧.
    func selectedBerthProducts() -> [SeatSpec] {
        guard let capabilities else { return [] }
        let berthLabels = Set(capabilities.seatGroups.berth)
        return selectedSeatProducts().filter { berthLabels.contains($0.label) }
    }

    /// Seat products whose layout can express ABCDF relations.
    func selectedSeatableProducts() -> [SeatSpec] {
        guard let capabilities else { return [] }
        let choosable = Set(capabilities.seatLayouts.choosableCodes)
        return selectedSeatProducts().filter { choosable.contains($0.submitCode) }
    }

    /// Letters the seat map may offer, taken from the engine's layout table rather
    /// than hard-coded, because 一等座 is ACDF and 特等座 is ACF on the same train.
    func seatMapLetters() -> [String] {
        guard let capabilities else { return [] }
        var letters: Set<String> = []
        for product in selectedSeatableProducts() {
            let allowed = capabilities.seatLayouts.lettersByCode[product.submitCode] ?? []
            letters.formUnion(allowed)
        }
        // Business class is selected separately by `dw_flag` and is only resolved
        // at order time, so use the safe intersection the engine documents.
        if selectedSeatableProducts().contains(where: { $0.submitCode == capabilities.seatLayouts.businessCode }) {
            letters.formUnion(["A", "F"])
        }
        // Mirror the backend's documented letter order so the grid reads A B C | D F
        // regardless of which seat products are selected.
        return letters.sorted { lhs, rhs in
            let left = Self.seatLetterOrder.firstIndex(of: Character(lhs)) ?? .max
            let right = Self.seatLetterOrder.firstIndex(of: Character(rhs)) ?? .max
            return left < right
        }
    }

    /// Matches `SEAT_LETTER_ORDER` in the engine's preference module.
    private static let seatLetterOrder = Array("ABCDF")

    /// Passenger count for UI affordances only.
    ///
    /// The backend remains authoritative — it splits the raw text itself and
    /// rejects a mismatch — but the seat map needs a count to decide whether the
    /// second row is selectable.
    func passengerCountForDisplay() -> Int {
        listItems("passenger_names").count
    }
}

/// What 12306 reports for remaining seats.
///
/// Not a number. The server's stock column is a *display token*: a digit when it deigns
/// to give one, and otherwise `有`, `无`, `*` (not on sale for this train), `--` (no such
/// seat product) or empty. The engine passes the token through untouched
/// (`helpers.py::_display_stock`), and its own availability test is a set membership
/// check, not a comparison — `""`, `--`, `无`, `*` and `0` all mean "nothing to take".
///
/// So only a numeric token may be printed with a 张 unit. Rendering `有` as "有 张" is the
/// mistake this guards, and it is not merely cosmetic: a user who reads "有 张" as a
/// truncated number believes the server counted something it did not.
enum StockToken {
    /// "余票 7 张" / "有余票" / "无票" / "余票状态未知".
    static func summary(_ token: String?) -> String {
        switch normalised(token) {
        case .number(let value): return "余票 \(value) 张"
        case .available: return "有余票"
        case .none: return "无票"
        case .unknown: return "余票状态未知"
        }
    }

    /// The bare form a stat cell needs: "7 张" / "有" / "无" / "--".
    static func short(_ token: String?) -> String {
        switch normalised(token) {
        case .number(let value): return "\(value) 张"
        case .available: return "有"
        case .none: return "无"
        case .unknown: return "--"
        }
    }

    /// True only when the server actually gave a count, so a view can say "N 张可提交"
    /// about that case alone.
    static func isCountable(_ token: String?) -> Bool {
        if case .number = normalised(token) { return true }
        return false
    }

    private enum Reading {
        case number(String)
        case available
        case none
        case unknown
    }

    private static func normalised(_ token: String?) -> Reading {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "--" { return .unknown }
        if trimmed == "无" || trimmed == "*" || trimmed == "0" { return .none }
        if trimmed == "有" { return .available }
        return trimmed.allSatisfy(\.isNumber) ? .number(trimmed) : .unknown
    }
}

/// What the login card's empty slot shows.
struct LoginSlot: Equatable {
    var systemImage: String
    var text: String
}

/// Content of the start confirmation.
///
/// `cartRows`, `scopeSummary` and `attemptOrder` are the engine's own strings; the
/// rest is a straight rendering of the canonical settings, laid out the way the
/// desktop dialog lays it out.
struct StartSummary: Equatable {
    var route = ""
    var date = ""
    var passengers = ""
    /// One line per cart entry, worded by the engine.
    var cartRows: [String] = []
    var scopeSummary = ""
    var attemptOrder = ""
    var position = ""
    var mode = ""
    /// 提交时间窗: the start and stop times, each described rather than blank when unset.
    var submitWindow = ""
    /// Seat products the run would order, taken from the cart.
    ///
    /// The dialog reads this instead of scraping seat words out of `cartRows`: the cart
    /// is the authoritative list, and a scrape silently yields nothing the moment the
    /// engine rewords a row.
    var seatLabels: [String] = []
}

extension RuntimeEvent {
    /// Build a synthetic terminal event when the child dies without an `exit`
    /// frame, so the UI still leaves its running state.
    static func terminated(exitCode: Int) -> RuntimeEvent {
        RuntimeEvent(
            rawKind: "exit",
            message: "引擎进程已退出（退出码 \(exitCode)）",
            data: [
                "exit_code": .number(Double(exitCode)),
                "safe_stop": .bool(false),
                "cancelled": .bool(false),
            ],
            timestamp: Date().timeIntervalSince1970
        )
    }
}