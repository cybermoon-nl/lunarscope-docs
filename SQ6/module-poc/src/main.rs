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
