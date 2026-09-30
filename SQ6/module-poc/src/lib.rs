// ================================================================
// lunarscope – module interface  (src/lib.rs)
//
// Defines the public contract every scan module must implement.
// This file never needs to change when a new module is added.
// ================================================================

use chrono::{DateTime, Utc};
use serde::Serialize;

// ── Severity ────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Pass,
    Info,
    Medium,
    High,
    Critical,
}

impl std::fmt::Display for Severity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let label = match self {
            Severity::Pass     => "PASS",
            Severity::Info     => "INFO",
            Severity::Medium   => "MEDIUM",
            Severity::High     => "HIGH",
            Severity::Critical => "CRITICAL",
        };
        write!(f, "{label}")
    }
}

// ── Finding ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize)]
pub struct Finding {
    /// Short unique code, e.g. "SSH-001"
    pub id: String,
    /// Human-readable description of the issue
    pub description: String,
    pub severity: Severity,
    pub timestamp: DateTime<Utc>,
    pub recommendation: Option<String>,
}

impl Finding {
    pub fn new(
        id: impl Into<String>,
        description: impl Into<String>,
        severity: Severity,
        recommendation: Option<&str>,
    ) -> Self {
        Self {
            id: id.into(),
            description: description.into(),
            severity,
            timestamp: Utc::now(),
            recommendation: recommendation.map(str::to_string),
        }
    }
}

// ── ScanModule – the core contract ──────────────────────────────

/// Every scan module implements this trait.
///
/// To add a new module:
///   1. Create a new file in src/modules/
///   2. Implement this trait
///   3. Register in src/modules/mod.rs
///   4. Enable in config.toml
///
/// lib.rs and main.rs are NEVER modified.
pub trait ScanModule: Send + Sync {
    /// Unique module name (must match the config key).
    fn name(&self) -> &str;

    /// Whether the module is enabled when absent from config.
    fn enabled_by_default(&self) -> bool {
        false
    }

    /// Run the scan and return a list of findings.
    /// An empty list means everything is fine.
    fn run(&self) -> Vec<Finding>;
}
