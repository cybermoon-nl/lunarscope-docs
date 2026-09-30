// Lunarscope Master Node PoC
//
// Three endpoints:
//   GET  /                  — HTML dashboard (rendered via Tera)
//   POST /api/scan-result   — receive a scan result from an agent (JSON)
//   GET  /api/results       — return all stored results as JSON
//
// Build:  cargo build --release
// Run:    ./target/release/master-poc  (from any directory)
// Then open http://localhost:8080 in your browser.

use axum::{
    extract::State,
    http::StatusCode,
    response::Html,
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::{sqlite::SqliteConnectOptions, FromRow, SqlitePool};
use std::{str::FromStr, sync::Arc};
use tera::{Context, Tera};
use tokio::net::TcpListener;

// ---------------------------------------------------------------------------
// Shared application state — cloned cheaply into every request handler
// ---------------------------------------------------------------------------
#[derive(Clone)]
struct AppState {
    db: SqlitePool,
    tera: Arc<Tera>,
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// JSON body sent by an agent via POST /api/scan-result
#[derive(Debug, Deserialize)]
struct ScanResultInput {
    agent_id: String,
    hostname: String,
    scan_type: String,
    severity: String, // "critical" | "high" | "medium" | "low" | "pass"
    finding: String,
}

/// Row returned from the database
#[derive(Debug, Serialize, FromRow)]
struct ScanResult {
    id: i64,
    agent_id: String,
    hostname: String,
    scan_type: String,
    severity: String,
    finding: String,
    created_at: String,
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
#[tokio::main]
async fn main() {
    // --- Database setup ---
    let opts = SqliteConnectOptions::from_str("sqlite:lunarscope.db")
        .expect("Invalid database URL")
        .create_if_missing(true);

    let db = SqlitePool::connect_with(opts)
        .await
        .expect("Could not connect to SQLite database");

    // Create table if it does not exist yet
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS scan_results (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            agent_id   TEXT NOT NULL,
            hostname   TEXT NOT NULL,
            scan_type  TEXT NOT NULL,
            severity   TEXT NOT NULL,
            finding    TEXT NOT NULL,
            created_at TEXT NOT NULL
        )",
    )
    .execute(&db)
    .await
    .expect("Could not create scan_results table");

    // --- Template engine setup ---
    // include_str! embeds the template at compile time so the binary is
    // fully self-contained and works from any directory.
    let mut tera = Tera::default();
    tera.add_raw_template("index.html", include_str!("../templates/index.html"))
        .expect("Failed to load template");

    let state = AppState {
        db,
        tera: Arc::new(tera),
    };

    // --- Router ---
    let app = Router::new()
        .route("/", get(dashboard))
        .route("/api/scan-result", post(receive_scan_result))
        .route("/api/results", get(get_results_json))
        .with_state(state);

    println!("Lunarscope master node running on http://0.0.0.0:8080");
    let listener = TcpListener::bind("0.0.0.0:8080")
        .await
        .expect("Could not bind to port 8080");

    axum::serve(listener, app).await.unwrap();
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// GET / — render the HTML dashboard
async fn dashboard(State(state): State<AppState>) -> Result<Html<String>, StatusCode> {
    // Fetch the 100 most recent findings
    let results = sqlx::query_as::<_, ScanResult>(
        "SELECT id, agent_id, hostname, scan_type, severity, finding, created_at
         FROM scan_results
         ORDER BY created_at DESC
         LIMIT 100",
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Summary counts per severity for the status bar
    let critical = results.iter().filter(|r| r.severity == "critical").count();
    let high     = results.iter().filter(|r| r.severity == "high").count();
    let medium   = results.iter().filter(|r| r.severity == "medium").count();
    let passed   = results.iter().filter(|r| r.severity == "pass").count();

    // Unique hostnames that have reported in
    let mut hostnames: Vec<&str> = results.iter().map(|r| r.hostname.as_str()).collect();
    hostnames.dedup();
    let server_count = hostnames.len();

    let mut ctx = Context::new();
    ctx.insert("results",      &results);
    ctx.insert("critical",     &critical);
    ctx.insert("high",         &high);
    ctx.insert("medium",       &medium);
    ctx.insert("passed",       &passed);
    ctx.insert("total",        &results.len());
    ctx.insert("server_count", &server_count);

    let html = state
        .tera
        .render("index.html", &ctx)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Html(html))
}

/// POST /api/scan-result — store a scan result received from an agent
async fn receive_scan_result(
    State(state): State<AppState>,
    Json(input): Json<ScanResultInput>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let now = Utc::now().format("%Y-%m-%d %H:%M:%S UTC").to_string();

    sqlx::query(
        "INSERT INTO scan_results
             (agent_id, hostname, scan_type, severity, finding, created_at)
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&input.agent_id)
    .bind(&input.hostname)
    .bind(&input.scan_type)
    .bind(&input.severity)
    .bind(&input.finding)
    .bind(&now)
    .execute(&state.db)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": "Scan result stored"
    })))
}

/// GET /api/results — return all results as JSON (for API consumers)
async fn get_results_json(
    State(state): State<AppState>,
) -> Result<Json<Vec<ScanResult>>, StatusCode> {
    let results = sqlx::query_as::<_, ScanResult>(
        "SELECT id, agent_id, hostname, scan_type, severity, finding, created_at
         FROM scan_results
         ORDER BY created_at DESC",
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(results))
}
