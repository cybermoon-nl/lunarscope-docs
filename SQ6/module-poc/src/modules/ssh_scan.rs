// ================================================================
// Module: SshScanModule  (src/modules/ssh_scan.rs)
//
// Parses /etc/ssh/sshd_config and checks for insecure settings
// per CIS Ubuntu 24.04 LTS Benchmark §5.1.
// ================================================================

use crate::{Finding, ScanModule, Severity};
use std::collections::HashMap;

pub struct SshScanModule;

impl SshScanModule {
    pub fn new() -> Self { Self }

    fn parse_sshd_config() -> HashMap<String, String> {
        let mut config = HashMap::new();
        let content = match std::fs::read_to_string("/etc/ssh/sshd_config") {
            Ok(c) => c,
            Err(_) => return config,
        };
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') { continue; }
            let parts: Vec<&str> = line.splitn(2, char::is_whitespace).collect();
            if parts.len() == 2 {
                config.insert(parts[0].to_lowercase(), parts[1].trim().to_string());
            }
        }
        config
    }
}

impl ScanModule for SshScanModule {
    fn name(&self) -> &str { "ssh_scan" }
    fn enabled_by_default(&self) -> bool { true }

    fn run(&self) -> Vec<Finding> {
        let mut findings = Vec::new();
        let cfg = Self::parse_sshd_config();

        if cfg.is_empty() {
            findings.push(Finding::new(
                "SSH-000",
                "Could not read /etc/ssh/sshd_config",
                Severity::Info,
                Some("Check whether OpenSSH is installed."),
            ));
            return findings;
        }

        // SSH-001: PermitRootLogin must be 'no' or 'prohibit-password'
        match cfg.get("permitrootlogin").map(String::as_str) {
            Some("no") | Some("prohibit-password") => {}
            Some(val) => findings.push(Finding::new(
                "SSH-001",
                format!("PermitRootLogin is set to '{}' (expected: no)", val),
                Severity::High,
                Some("Set 'PermitRootLogin no' in /etc/ssh/sshd_config and restart sshd."),
            )),
            None => findings.push(Finding::new(
                "SSH-001",
                "PermitRootLogin is not configured (default: yes)",
                Severity::High,
                Some("Add 'PermitRootLogin no' to /etc/ssh/sshd_config."),
            )),
        }

        // SSH-002: PasswordAuthentication must be 'no'
        match cfg.get("passwordauthentication").map(String::as_str) {
            Some("no") => {}
            Some(val) => findings.push(Finding::new(
                "SSH-002",
                format!("PasswordAuthentication is '{}' – password login is active", val),
                Severity::Medium,
                Some("Use SSH keys only: set 'PasswordAuthentication no'."),
            )),
            None => findings.push(Finding::new(
                "SSH-002",
                "PasswordAuthentication is not configured (default: yes)",
                Severity::Medium,
                Some("Add 'PasswordAuthentication no' to /etc/ssh/sshd_config."),
            )),
        }

        // SSH-003: Protocol key (only present in old configs)
        if let Some(proto) = cfg.get("protocol") {
            if proto != "2" {
                findings.push(Finding::new(
                    "SSH-003",
                    format!("Protocol is set to '{}' instead of 2", proto),
                    Severity::Critical,
                    Some("Set 'Protocol 2'; SSH-1 has serious vulnerabilities."),
                ));
            }
        }

        // SSH-004: MaxAuthTries must not exceed 4
        if let Some(tries) = cfg.get("maxauthtries") {
            if let Ok(n) = tries.parse::<u32>() {
                if n > 4 {
                    findings.push(Finding::new(
                        "SSH-004",
                        format!("MaxAuthTries is {} (recommended: ≤ 4)", n),
                        Severity::Medium,
                        Some("Set 'MaxAuthTries 4' to limit brute-force attempts."),
                    ));
                }
            }
        }

        // SSH-005: X11Forwarding should be disabled
        if let Some("yes") = cfg.get("x11forwarding").map(String::as_str) {
            findings.push(Finding::new(
                "SSH-005",
                "X11Forwarding is enabled (increases attack surface)",
                Severity::Info,
                Some("Set 'X11Forwarding no' unless GUI forwarding is required."),
            ));
        }

        if findings.is_empty() {
            findings.push(Finding::new(
                "SSH-000",
                "SSH configuration passes all checked CIS guidelines",
                Severity::Pass,
                None,
            ));
        }
        findings
    }
}
