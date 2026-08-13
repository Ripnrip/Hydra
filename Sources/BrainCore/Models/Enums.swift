import Foundation

// MARK: - Artifact Kind

/// What type of source artifact this is. Drives classification heuristics and vault projection paths.
public enum ArtifactKind: Sendable, Equatable {
    case plan
    case session
    case decision
    case changelog
    case incident
    case note
    case recap
    case handoff
    case audit
    case other(String)

    public var vaultSubpath: String {
        switch self {
        case .plan:     return "wiki/plans"
        case .session:  return "wiki/recaps/sessions"
        case .decision: return "wiki/decisions"
        case .changelog: return "wiki/changelogs"
        case .incident: return "wiki/incidents"
        case .recap:    return "wiki/recaps"
        case .handoff:  return "wiki/handoffs"
        case .audit:    return "wiki/audits"
        case .note:     return "wiki/notes"
        case .other(let label): return "wiki/other/\(label)"
        }
    }
}

// MARK: - Lifecycle State

/// Content lifecycle — where this artifact is in its editorial journey.
/// From the artifact-lifecycle-policy.json content lifecycle states.
public enum LifecycleState: String, Sendable, CaseIterable, Equatable {
    case draft
    case accepted
    case active
    case completed
    case superseded
    case abandoned
    case archived
}

// MARK: - Delivery State

/// Delivery lifecycle — the 8-state pipeline from submission to certification.
/// From artifact-lifecycle-policy.json delivery states.
/// Only 3 are mechanically tracked in the Python outbox today (pending/applied/blocked);
/// the other 5 are policy-defined but not yet enforced in code.
public enum DeliveryState: String, Sendable, CaseIterable, Equatable {
    case submitted
    case validated
    case canonicalCommitted = "canonical-committed"
    case canonicalReachable = "canonical-reachable"
    case projectionCommitted = "projection-committed"
    case gitlinkPinned = "gitlink-pinned"
    case certified
    case blocked

    /// Whether this state is mechanically enforced in the current outbox, or aspirational (policy-only).
    public var isMechanicallyTracked: Bool {
        switch self {
        case .submitted, .blocked:
            return true  // maps to pending / blocked in store.py
        case .canonicalCommitted, .canonicalReachable, .projectionCommitted,
             .gitlinkPinned, .validated, .certified:
            return false  // policy-defined only, not enforced in outbox code
        }
    }
}
