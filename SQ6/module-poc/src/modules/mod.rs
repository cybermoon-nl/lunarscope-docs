// ================================================================
// Module registry  (src/modules/mod.rs)
//
// Step 2 when adding a module: declare the submodule and add it
// to all_modules().  lib.rs and main.rs are NEVER modified.
// ================================================================

pub mod firewall_scan;
pub mod shadow_scan;
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
        Box::new(shadow_scan::ShadowScanModule::new()),
        // Add new modules here ↑
    ]
}
