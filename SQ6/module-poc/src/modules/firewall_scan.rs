// ================================================================
// Module: FirewallScanModule  (src/modules/firewall_scan.rs)
//
// THIRD MODULE – added without changing lib.rs or main.rs.
// Only required:
//   1. this file
//   2. one line in src/modules/mod.rs
//   3. three lines in config.toml
//
// Checks UFW firewall status per CIS Ubuntu 24.04 §4.1.
// ================================================================

use crate::{Finding, ScanModule, Severity};
use std::process::Command;

pub struct FirewallScanModule;

impl FirewallScanModule {
    pub fn new() -> Self { Self }

    fn ufw_installed() -> bool {
        Command::new("which").arg("ufw").output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    fn ufw_status() -> Option<String> {
        let output = Command::new("ufw").arg("status").output().ok()?;
        Some(String::from_utf8_lossy(&output.stdout).to_string())
    }
}

impl ScanModule for FirewallScanModule {
    fn name(&self) -> &str { "firewall_scan" }
    fn enabled_by_default(&self) -> bool { false }

    fn run(&self) -> Vec<Finding> {
        let mut findings = Vec::new();

        // FW-001: UFW installed?
        if !Self::ufw_installed() {
            findings.push(Finding::new(
                "FW-001",
                "UFW is not installed (CIS 4.1.1)",
                Severity::High,
                Some("Install UFW: 'apt install ufw'."),
            ));
            return findings;
        }

        // FW-002: UFW active?
        match Self::ufw_status() {
            None => {
                findings.push(Finding::new(
                    "FW-002",
                    "Could not retrieve UFW status",
                    Severity::Medium,
                    Some("Check that ufw is executable and has sufficient permissions."),
                ));
            }
            Some(ref status) => {
                if !status.contains("Status: active") {
                    findings.push(Finding::new(
                        "FW-002",
                        "UFW is installed but not active (CIS 4.1.2)",
                        Severity::High,
                        Some("Enable UFW: 'systemctl --now enable ufw && ufw enable'."),
                    ));
                } else {
                    // FW-003: default deny incoming?
                    let deny_ok = status.contains("deny (incoming)")
                        || status.contains("reject (incoming)");
                    if !deny_ok {
                        findings.push(Finding::new(
                            "FW-003",
                            "UFW default incoming policy is not 'deny' (CIS 4.1.3)",
                            Severity::High,
                            Some("Run: 'ufw default deny incoming'."),
                        ));
                    } else {
                        findings.push(Finding::new(
                            "FW-000",
                            "UFW is active with correct default policy (deny incoming)",
                            Severity::Pass,
                            None,
                        ));
                    }
                }
            }
        }
        findings
    }
}
