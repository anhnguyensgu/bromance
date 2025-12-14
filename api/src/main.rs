mod models;
mod rpc;

use jsonwebtoken::EncodingKey;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
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
            std::env::var("RUST_LOG").unwrap_or_else(|_| "server=debug".into()),
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

    let addr = "[::0]:50051".parse().unwrap();
    tracing::info!("gRPC listening on {}", addr);
    let auth_service = rpc::auth::AuthServiceImpl { state: app_state };

    tonic::transport::Server::builder()
        .add_service(
            rpc::auth::auth_proto::auth_service_server::AuthServiceServer::new(auth_service),
        )
        .serve_with_shutdown(addr, shutdown_signal())
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
