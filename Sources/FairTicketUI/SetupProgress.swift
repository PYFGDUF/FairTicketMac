import Foundation
import FairTicketKit

/// Which of the first-run steps are done, and which one is next.
///
/// The sidebar lists six destinations, but only three of them are steps — the rest is
/// optional tuning and a runtime readout, and nothing in the list says which is which.
/// The app's answer used to be prose ("尚未加入备选", "未填写（仅监控）"), which is
/// information a first-time user has to read and then translate into an order of work.
/// A tick and a dot do the same job without a sentence: what is finished, and where to go
/// next.
///
/// Every answer is derived from state the app already has — the cart it can see, the same
/// date and passenger fields its sidebar summaries read — so the mark can never disagree
/// with the summary line underneath it.
struct SetupProgress: Equatable {

    /// The run-up, in the order a first run should take it.
    static let steps: [ConfigSection] = [.cart, .trip, .passengers]

    enum State: Equatable {
        case done
        /// The next thing to do.
        case next
        /// Not done, but not the next thing either.
        case pending
        /// Optional tuning or a runtime readout: not part of the run-up.
        case notAStep
    }

    private let done: Set<ConfigSection>

    /// The rule on its own, without a model: the order and the ends of the run-up are
    /// what `FirstRunTests` pins down.
    init(done: Set<ConfigSection>) {
        self.done = done
    }

    /// The first step still outstanding, or nil when the draft is ready to attempt.
    var next: ConfigSection? {
        Self.steps.first { !done.contains($0) }
    }

    func state(for section: ConfigSection) -> State {
        guard Self.steps.contains(section) else { return .notAStep }
        if done.contains(section) { return .done }
        return section == next ? .next : .pending
    }

    @MainActor
    init(model: AppModel) {
        var done: Set<ConfigSection> = []
        // The cart is the app's own precondition for an attempt, so it is the first step.
        if !model.cartItems.isEmpty { done.insert(.cart) }
        // The engine ships a date; an empty one means the user cleared it.
        if !model.string("train_date").isEmpty { done.insert(.trip) }
        // Passengers are optional *to the engine* — leaving them empty is how 仅监控 works —
        // but they are not optional to someone who expects a ticket, and the row's own
        // summary already says 未填写（仅监控）.
        if !model.listItems("passenger_names").isEmpty { done.insert(.passengers) }
        self.done = done
    }
}

/// What the 「添加备选」 row still needs before 加入购物车 can do its job.
enum CartDraftField: String, CaseIterable, Identifiable {
    case fromStation
    case toStation
    case trainCode
    case seat

    var id: String { rawValue }

    /// The same words as the field's own label, so the chip and the control it refers to
    /// are visibly the same thing.
    var label: String {
        switch self {
        case .fromStation: return "出发站"
        case .toStation: return "到达站"
        case .trainCode: return "指定车次"
        case .seat: return "席别"
        }
    }
}

enum CartDraftRequirements {

    /// The outstanding fields, in the order the row reads.
    ///
    /// A cart entry added without any of these is one the app already calls 不完整 — and a
    /// cart row cannot be edited afterwards, only removed and typed again.  Making the
    /// button wait for them is what keeps a first-time user out of that dead end, and it
    /// turns a greyed-out button into a two-word answer instead of a mystery.
    @MainActor
    static func missing(in draft: AppModel.CartDraft) -> [CartDraftField] {
        var missing: [CartDraftField] = []
        if draft.fromStation.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append(.fromStation)
        }
        if draft.toStation.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append(.toStation)
        }
        if draft.trainScope == CartItem.scopeSpecific,
           AppModel.splitTrainCodes(draft.trainCode).isEmpty {
            missing.append(.trainCode)
        }
        if draft.seatTypes.isEmpty {
            missing.append(.seat)
        }
        return missing
    }
}
