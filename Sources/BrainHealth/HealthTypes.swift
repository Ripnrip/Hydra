import Foundation
import BrainCore

// MARK: - Health Check

/// A single health check result.
public struct HealthCheck: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var status: HealthStatus
    public var message: String
    public var affectedCount: Int
    public var severity: GapSeverity
    public var checkedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        status: HealthStatus,
        message: String,
        affectedCount: Int = 0,
        severity: GapSeverity = .info,
        checkedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.message = message
        self.affectedCount = affectedCount
        self.severity = severity
        self.checkedAt = checkedAt
    }
}

public enum HealthStatus: String, Sendable, Equatable {
    case healthy    // no issues found
    case warning    // potential issue
    case critical   // definite issue
}

// MARK: - Health Report

/// A complete vault health snapshot.
public struct HealthReport: Sendable {
    public var vaultRoot: String
    public var checks: [HealthCheck]
    public var generatedAt: Date

    public var overallStatus: HealthStatus {
        if checks.contains(where: { $0.status == .critical }) { return .critical }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        return .healthy
    }

    public var summary: String {
        let critical = checks.filter { $0.status == .critical }.count
        let warning = checks.filter { $0.status == .warning }.count
        let healthy = checks.filter { $0.status == .healthy }.count
        return "\(healthy) healthy, \(warning) warnings, \(critical) critical"
    }

    public init(vaultRoot: String, checks: [HealthCheck], generatedAt: Date = Date()) {
        self.vaultRoot = vaultRoot
        self.checks = checks
        self.generatedAt = generatedAt
    }
}
