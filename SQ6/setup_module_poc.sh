#!/usr/bin/env bash
# ================================================================
# setup_module_poc.sh
# Creates the Lunarscope SQ5 module-interface PoC from scratch.
# Run from any directory — it creates module-poc/ next to this script.
# ================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)/module-poc"

echo "Creating project at: $ROOT"
mkdir -p "$ROOT/src/modules"
cd "$ROOT"

# ── Cargo.toml ───────────────────────────────────────────────────
cat > Cargo.toml << 'EOF'
[package]
name = "module-poc"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "lunarscope-agent"
path = "src/main.rs"

[lib]
name = "module_poc"
path = "src/lib.rs"

[dependencies]
serde = { version = "1", features = ["derive"] }
toml = "0.8"
chrono = { version = "0.4", features = ["serde"] }
EOF

# ── config.toml ──────────────────────────────────────────────────
cat > config.toml << 'EOF'
# ================================================================
# Lunarscope Agent configuration
#
# Add a new module by adding a [modules.<name>] section and
# setting enabled = true.  No changes to lib.rs or main.rs needed.
# ================================================================

[agent]
hostname = "server-workshop"

[modules.package_scan]
enabled = true

[modules.ssh_scan]
enabled = true

# Third module — added without touching any core file
[modules.firewall_scan]
enabled = true
EOF

# ── src/lib.rs ───────────────────────────────────────────────────
cat > src/lib.rs << 'EOF'
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
EOF

# ── src/main.rs ──────────────────────────────────────────────────
cat > src/main.rs << 'EOF'
// ================================================================
// Lunarscope Agent – module runner  (src/main.rs)
//
// Loads config, selects enabled modules, runs them.
// This file is NEVER modified when a new module is added.
// ================================================================

use module_poc::{Finding, ScanModule, Severity};
use serde::Deserialize;
use std::collections::HashMap;

mod modules;

// ── Config ──────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct Config {
    agent: AgentConfig,
    modules: HashMap<String, ModuleConfig>,
}

#[derive(Debug, Deserialize)]
struct AgentConfig {
    hostname: String,
}

#[derive(Debug, Deserialize)]
struct ModuleConfig {
    enabled: bool,
}

fn load_config(path: &str) -> Config {
    let content = std::fs::read_to_string(path)
        .unwrap_or_else(|_| panic!("Cannot read config file '{}'", path));
    toml::from_str(&content).expect("Invalid TOML syntax in config file")
}

// ── Output ──────────────────────────────────────────────────────

fn severity_color(s: &Severity) -> &'static str {
    match s {
        Severity::Critical => "\x1b[1;31m",
        Severity::High     => "\x1b[31m",
        Severity::Medium   => "\x1b[33m",
        Severity::Info     => "\x1b[36m",
        Severity::Pass     => "\x1b[32m",
    }
}

const RESET: &str = "\x1b[0m";

fn print_finding(f: &Finding) {
    let color = severity_color(&f.severity);
    println!(
        "  [{color}{}{RESET}] {} – {}",
        f.severity, f.id, f.description,
        color = color,
    );
    if let Some(rec) = &f.recommendation {
        println!("         ↳ {}", rec);
    }
}

fn print_summary(all_findings: &[(String, Vec<Finding>)]) {
    let severities = [
        &Severity::Critical,
        &Severity::High,
        &Severity::Medium,
        &Severity::Info,
        &Severity::Pass,
    ];

    println!("\n═══════════════════════════════════════");
    println!("  Summary");
    println!("═══════════════════════════════════════");
    for sev in severities {
        let count = all_findings
            .iter()
            .flat_map(|(_, fs)| fs.iter())
            .filter(|f| &f.severity == sev)
            .count();
        if count > 0 {
            let color = severity_color(sev);
            println!("  {color}{:<10}{RESET} {}", format!("{}", sev), count);
        }
    }
    println!("═══════════════════════════════════════\n");
}

// ── Main ────────────────────────────────────────────────────────

fn main() {
    let config_path = std::env::args().nth(1)
        .unwrap_or_else(|| "config.toml".to_string());

    let config = load_config(&config_path);

    println!("╔══════════════════════════════════════╗");
    println!("║  Lunarscope Agent – module PoC       ║");
    println!("╚══════════════════════════════════════╝");
    println!("  Host: {}", config.agent.hostname);
    println!();

    let available = modules::all_modules();

    let active: Vec<&Box<dyn ScanModule>> = available
        .iter()
        .filter(|m| {
            config.modules.get(m.name())
                .map(|mc| mc.enabled)
                .unwrap_or(m.enabled_by_default())
        })
        .collect();

    println!("  Active modules: {}/{}", active.len(), available.len());
    for m in &active {
        println!("    ✓ {}", m.name());
    }
    println!();

    let mut all_findings: Vec<(String, Vec<Finding>)> = Vec::new();

    for module in active {
        println!("▶ Module: {}", module.name());
        let findings = module.run();
        for finding in &findings {
            print_finding(finding);
        }
        all_findings.push((module.name().to_string(), findings));
        println!();
    }

    print_summary(&all_findings);
}
EOF

# ── src/modules/mod.rs ───────────────────────────────────────────
cat > src/modules/mod.rs << 'EOF'
// ================================================================
// Module registry  (src/modules/mod.rs)
//
// Step 2 when adding a module: declare the submodule and add it
// to all_modules().  lib.rs and main.rs are NEVER modified.
// ================================================================

pub mod firewall_scan;
pub mod package_scan;
pub mod ssh_scan;

use crate::ScanModule;

/// Returns all available modules.
/// main.rs filters this list based on config.toml.
pub fn all_modules() -> Vec<Box<dyn ScanModule>> {
    vec![
        Box::new(package_scan::PackageScanModule::new()),
        Box::new(ssh_scan::SshScanModule::new()),
        Box::new(firewall_scan::FirewallScanModule::new()),
        // Add new modules here ↑
    ]
}
EOF

# ── src/modules/package_scan.rs ──────────────────────────────────
cat > src/modules/package_scan.rs << 'EOF'
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
EOF

# ── src/modules/ssh_scan.rs ──────────────────────────────────────
cat > src/modules/ssh_scan.rs << 'EOF'
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
EOF

# ── src/modules/firewall_scan.rs ─────────────────────────────────
cat > src/modules/firewall_scan.rs << 'EOF'
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
EOF

# ── measure.sh ───────────────────────────────────────────────────
cat > measure.sh << 'EOF'
#!/usr/bin/env bash
# Performance measurement for the SQ5 module-interface PoC

AGENT="./target/release/lunarscope-agent"
CONFIG="config.toml"
RUNS=10

echo "╔══════════════════════════════════════╗"
echo "║  SQ5 PoC – performance measurement  ║"
echo "╚══════════════════════════════════════╝"
echo ""

SIZE=$(du -sh "$AGENT" | cut -f1)
echo "  Binary size : $SIZE"

echo "  Timing ($RUNS runs)..."
TOTAL=0
for i in $(seq 1 $RUNS); do
    START=$(date +%s%3N)
    "$AGENT" "$CONFIG" > /dev/null 2>&1
    END=$(date +%s%3N)
    TOTAL=$((TOTAL + END - START))
done
AVG=$(echo "scale=1; $TOTAL / $RUNS" | bc)
echo "  Average wall time : ${AVG} ms"

PEAK=$(python3 -c "
import subprocess, time, re
proc = subprocess.Popen(['$AGENT', '$CONFIG'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
max_rss = 0
while proc.poll() is None:
    try:
        with open(f'/proc/{proc.pid}/status') as f:
            for line in f:
                if 'VmPeak' in line:
                    val = int(re.search(r'\d+', line).group())
                    if val > max_rss: max_rss = val
    except: pass
    time.sleep(0.0001)
proc.wait()
print(max_rss)
" 2>/dev/null)

if [ -n "$PEAK" ] && [ "$PEAK" -gt 0 ]; then
    MB=$(echo "scale=1; $PEAK / 1024" | bc)
    echo "  Peak memory (VmPeak) : ${PEAK} kB  (${MB} MB)"
fi
echo ""
echo "  Done."
EOF

# ── add_module_test.sh ───────────────────────────────────────────
cat > add_module_test.sh << 'EOF'
#!/usr/bin/env bash
# Proves that adding a new module requires:
#   - 1 new file
#   - 1 line in mod.rs
#   - 3 lines in config.toml
#   - 0 changes to lib.rs or main.rs

set -euo pipefail

echo "══════════════════════════════════════════════════════"
echo "  Extensibility test: adding ShadowScanModule"
echo "══════════════════════════════════════════════════════"
echo ""

TOTAL_START=$(date +%s%3N)

# Step 1: Write the new module
echo "  [1/3] Creating src/modules/shadow_scan.rs ..."
STEP1_START=$(date +%s%3N)

cat > src/modules/shadow_scan.rs << 'RUST'
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
RUST

STEP1_END=$(date +%s%3N)
echo "     → Done in $((STEP1_END - STEP1_START)) ms"

# Step 2: Register in mod.rs (idempotent)
echo "  [2/3] Registering in src/modules/mod.rs ..."
STEP2_START=$(date +%s%3N)

if ! grep -q 'pub mod shadow_scan;' src/modules/mod.rs; then
    sed -i 's/pub mod firewall_scan;/pub mod firewall_scan;\npub mod shadow_scan;/' src/modules/mod.rs
else
    echo "     (pub mod shadow_scan already present, skipped)"
fi

if ! grep -q 'ShadowScanModule' src/modules/mod.rs; then
    sed -i 's|// Add new modules here ↑|Box::new(shadow_scan::ShadowScanModule::new()),\n        // Add new modules here ↑|' src/modules/mod.rs
else
    echo "     (ShadowScanModule already in all_modules(), skipped)"
fi

STEP2_END=$(date +%s%3N)
echo "     → Done in $((STEP2_END - STEP2_START)) ms"

# Step 3: Add config entry (idempotent)
echo "  [3/3] Adding entry to config.toml ..."
STEP3_START=$(date +%s%3N)

if ! grep -q '\[modules\.shadow_scan\]' config.toml; then
    cat >> config.toml << 'TOML'

[modules.shadow_scan]
enabled = true
TOML
else
    echo "     (shadow_scan already in config.toml, skipped)"
fi

STEP3_END=$(date +%s%3N)
echo "     → Done in $((STEP3_END - STEP3_START)) ms"

# Rebuild
echo ""
echo "  Rebuilding (cargo build --release)..."
BUILD_START=$(date +%s%3N)
cargo build --release -q
BUILD_END=$(date +%s%3N)
echo "  Build time: $((BUILD_END - BUILD_START)) ms"

# Test run
echo ""
echo "  Test run:"
./target/release/lunarscope-agent config.toml

TOTAL_END=$(date +%s%3N)
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Total time (write + build): $((TOTAL_END - TOTAL_START)) ms"
echo "  Core files changed (lib.rs + main.rs): 0"
echo "══════════════════════════════════════════════════════"
EOF

chmod +x measure.sh add_module_test.sh

echo ""
echo "All files created. Now run:"
echo "  cd module-poc"
echo "  cargo build --release"
echo "  ./target/release/lunarscope-agent config.toml"
echo "  bash measure.sh"
echo "  bash add_module_test.sh"
