mod models;
mod rest;
mod rpc;

use jsonwebtoken::EncodingKey;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use tonic::codec::CompressionEncoding;
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

    // REST server on port 3000
    let rest_app = rest::router(app_state.clone());
    let rest_addr = "0.0.0.0:3000";
    tracing::info!("REST API listening on {}", rest_addr);
    let rest_listener = tokio::net::TcpListener::bind(rest_addr).await?;

    // gRPC server on port 50051
    let grpc_addr = "[::0]:50051".parse().unwrap();
    tracing::info!("gRPC listening on {}", grpc_addr);
    let auth_service = rpc::auth::AuthServiceImpl { state: app_state };
    let auth_server =
        rpc::auth::auth_proto::auth_service_server::AuthServiceServer::new(auth_service)
            .accept_compressed(CompressionEncoding::Gzip)
            .send_compressed(CompressionEncoding::Gzip);
    let grpc_server = tonic::transport::Server::builder()
        .add_service(auth_server)
        .serve_with_shutdown(grpc_addr, shutdown_signal());

    // Run both servers concurrently
    tokio::select! {
        res = axum::serve(rest_listener, rest_app) => {
            if let Err(e) = res {
                tracing::error!("REST server error: {}", e);
            }
        }
        res = grpc_server => {
            if let Err(e) = res {
                tracing::error!("gRPC server error: {}", e);
            }
        }
    }

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
