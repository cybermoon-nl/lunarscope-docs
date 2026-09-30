// Module: ShadowScanModule – checks /etc/shadow for empty passwords
use crate::{Finding, ScanModule, Severity};

pub struct ShadowScanModule;

impl ShadowScanModule {
    pub fn new() -> Self { Self }
}

impl ScanModule for ShadowScanModule {
    fn name(&self) -> &str { "shadow_scan" }

    fn run(&self) -> Vec<Finding> {
        let mut findings = Vec::new();

        let content = match std::fs::read_to_string("/etc/shadow") {
            Ok(c) => c,
            Err(_) => {
                findings.push(Finding::new(
                    "SHAD-000",
                    "Could not read /etc/shadow (insufficient permissions or file missing)",
                    Severity::Info,
                    None,
                ));
                return findings;
            }
        };

        for line in content.lines() {
            let parts: Vec<&str> = line.splitn(3, ':').collect();
            if parts.len() >= 2 && parts[1].is_empty() {
                findings.push(Finding::new(
                    "SHAD-001",
                    format!("Account '{}' has an empty password in /etc/shadow", parts[0]),
                    Severity::Critical,
                    Some("Set a strong password or lock the account: 'passwd -l <user>'."),
                ));
            }
        }

        if findings.is_empty() {
            findings.push(Finding::new(
                "SHAD-000",
                "No empty passwords found in /etc/shadow",
                Severity::Pass,
                None,
            ));
        }
        findings
    }
}
