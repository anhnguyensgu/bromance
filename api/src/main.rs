mod error;
mod handlers;
mod models;

use axum::{
    routing::{get, post},
    Router,
};
use jsonwebtoken::EncodingKey;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    pub encoding_key: EncodingKey,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "server=debug,tower_http=debug".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
        .await
        .expect("Failed to connect to DB");

    // Load private key
    let encoding_key = EncodingKey::from_ed_pem(include_bytes!("../keys/private.pem"))
        .expect("Failed to load private key");

    let app_state = AppState {
        db: pool,
        encoding_key,
    };

    let app = Router::new()
        .route("/", get(|| async { "Hello, World!" }))
        .route("/auth/register", post(handlers::auth::register))
        .route("/auth/login", post(handlers::auth::login))
        .layer(TraceLayer::new_for_http())
        .with_state(app_state);

    let verbose_addr = "0.0.0.0:3000";
    let listener = tokio::net::TcpListener::bind(verbose_addr).await?;
    tracing::debug!("listening on {}", verbose_addr);
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
