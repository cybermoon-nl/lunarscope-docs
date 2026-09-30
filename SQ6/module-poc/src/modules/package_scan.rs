// ================================================================
// Module: PackageScanModule  (src/modules/package_scan.rs)
//
// Reads /var/lib/dpkg/status and checks installed package versions
// against a simulated CVE database (in production: NVD feed or
// Debian Security Tracker).
// ================================================================

use crate::{Finding, ScanModule, Severity};
use std::collections::HashMap;

pub struct PackageScanModule;

impl PackageScanModule {
    pub fn new() -> Self { Self }

    /// Simulated CVE database: package → (vulnerable version, CVE id, severity)
    fn known_vulnerabilities() -> HashMap<&'static str, (&'static str, &'static str, Severity)> {
        let mut db = HashMap::new();
        db.insert("openssl",        ("3.0.2",   "CVE-2023-0464",  Severity::High));
        db.insert("curl",           ("7.81.0",  "CVE-2023-23916", Severity::Medium));
        db.insert("openssh-server", ("1:8.9p1", "CVE-2023-38408", Severity::Critical));
        db.insert("libssl3",        ("3.0.2",   "CVE-2023-2650",  Severity::High));
        db
    }

    /// Parses /var/lib/dpkg/status into a package → version map.
    fn parse_dpkg_status() -> HashMap<String, String> {
        let mut packages = HashMap::new();
        let content = match std::fs::read_to_string("/var/lib/dpkg/status") {
            Ok(c) => c,
            Err(_) => return packages,
        };
        let mut pkg = String::new();
        let mut ver = String::new();
        for line in content.lines() {
            if let Some(name) = line.strip_prefix("Package: ") {
                pkg = name.trim().to_string();
                ver.clear();
            } else if let Some(v) = line.strip_prefix("Version: ") {
                ver = v.trim().to_string();
            } else if line.is_empty() && !pkg.is_empty() && !ver.is_empty() {
                packages.insert(pkg.clone(), ver.clone());
                pkg.clear();
                ver.clear();
            }
        }
        packages
    }
}

impl ScanModule for PackageScanModule {
    fn name(&self) -> &str { "package_scan" }
    fn enabled_by_default(&self) -> bool { true }

    fn run(&self) -> Vec<Finding> {
        let mut findings = Vec::new();
        let installed = Self::parse_dpkg_status();
        let vuln_db   = Self::known_vulnerabilities();

        for (pkg, (vuln_ver, cve_id, severity)) in &vuln_db {
            if let Some(inst_ver) = installed.get(*pkg) {
                if inst_ver == vuln_ver {
                    findings.push(Finding::new(
                        format!("PKG-{}", cve_id),
                        format!("Package '{}' version {} is vulnerable ({})", pkg, inst_ver, cve_id),
                        severity.clone(),
                        Some("Run 'apt upgrade' to update all vulnerable packages."),
                    ));
                }
            }
        }

        if findings.is_empty() {
            findings.push(Finding::new(
                "PKG-000",
                "No known vulnerable packages found in the simulated CVE database",
                Severity::Pass,
                None,
            ));
        }
        findings
    }
}
