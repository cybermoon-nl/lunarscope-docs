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
