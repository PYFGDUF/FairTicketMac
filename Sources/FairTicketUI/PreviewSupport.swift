import Foundation
import FairTicketKit

/// The engine's own capabilities payload, captured once from a real handshake.
///
/// Previews and the component gallery need a fully populated window — every field
/// spec, the seat table and the group order — and launching Python for that would
/// make every preview a process spawn with a handshake delay.  The snapshot stands
/// in, so previews render the real form offline and instantly.
///
/// Paths in the snapshot are placeholders; nothing in the interface displays them.
///
/// Re-capture after a backend field change:
///
///     cd 12306FairTicket
///     printf '%s\n' '{"id":1,"cmd":"shutdown"}' \
///       | ./.venv/bin/python -m ticket_app.sidecar | head -1 \
///       > ../FairTicketMac/Sources/FairTicketUI/Resources/capabilities.json
enum CapabilitiesSnapshot {

    static func load() -> Capabilities? {
        guard
            let url = Bundle.module.url(forResource: "capabilities", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Capabilities.self, from: data)
    }
}

extension AppModel {

    /// A model backed by the snapshot instead of the engine.
    ///
    /// `scenario` replays one of the scripted timelines synchronously, because a
    /// preview has to render the finished state rather than animate into it.
    static func preview(
        scenario: DemoScenario? = nil,
        engineReady: Bool = true
    ) -> AppModel {
        let model = AppModel()
        model.loadSnapshot(scenario: scenario, engineReady: engineReady)
        return model
    }
}

// MARK: - Preview conveniences

extension UIState {
    /// Presentation state pre-set for a preview of one page.
    static func preview(section: ConfigSection = .trip, inspector: Bool = true) -> UIState {
        let ui = UIState()
        ui.selectedSection = section
        ui.showInspector = inspector
        return ui
    }
}