use axum::{extract::State, http::StatusCode, response::IntoResponse, routing::post, Json, Router};
use serde::{Deserialize, Serialize};

use crate::AppState;

// Request/Response types
#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct LoginResponse {
    pub token: String,
    pub success: bool,
    pub message: String,
}

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct RegisterResponse {
    pub success: bool,
    pub message: String,
}

#[derive(Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

// Handlers
pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> impl IntoResponse {
    use argon2::{Argon2, PasswordHash, PasswordVerifier};

    // Find user
    let user =
        match sqlx::query_as::<_, crate::models::user::User>("SELECT * FROM users WHERE email = ?")
            .bind(&req.username)
            .fetch_optional(&state.db)
            .await
        {
            Ok(Some(user)) => user,
            Ok(None) => {
                return (
                    StatusCode::UNAUTHORIZED,
                    Json(ErrorResponse {
                        error: "Invalid credentials".to_string(),
                    }),
                )
                    .into_response()
            }
            Err(e) => {
                tracing::error!("Database error: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: "Internal server error".to_string(),
                    }),
                )
                    .into_response();
            }
        };

    // Verify password
    let parsed_hash = match PasswordHash::new(&user.password_hash) {
        Ok(h) => h,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Internal server error".to_string(),
                }),
            )
                .into_response()
        }
    };

    if Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed_hash)
        .is_err()
    {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ErrorResponse {
                error: "Invalid credentials".to_string(),
            }),
        )
            .into_response();
    }

    // Generate JWT
    use jsonwebtoken::{encode, Header};

    let claims = crate::models::user::Claims {
        sub: user.id.to_string(),
        exp: (chrono::Utc::now() + chrono::Duration::days(7)).timestamp() as usize,
    };

    let token = match encode(
        &Header::new(jsonwebtoken::Algorithm::EdDSA),
        &claims,
        &state.encoding_key,
    ) {
        Ok(t) => t,
        Err(e) => {
            tracing::error!("JWT error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Internal server error".to_string(),
                }),
            )
                .into_response();
        }
    };

    (
        StatusCode::OK,
        Json(LoginResponse {
            token,
            success: true,
            message: "Login successful".to_string(),
        }),
    )
        .into_response()
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> impl IntoResponse {
    use argon2::{
        password_hash::{rand_core::OsRng, SaltString},
        Argon2, PasswordHasher,
    };

    // Check if user exists
    let existing = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM users WHERE email = ?")
        .bind(&req.username)
        .fetch_one(&state.db)
        .await;

    if let Ok(count) = existing {
        if count > 0 {
            return (
                StatusCode::CONFLICT,
                Json(RegisterResponse {
                    success: false,
                    message: "User already exists".to_string(),
                }),
            )
                .into_response();
        }
    }

    // Hash password
    let salt = SaltString::generate(&mut OsRng);
    let password_hash = match Argon2::default().hash_password(req.password.as_bytes(), &salt) {
        Ok(h) => h.to_string(),
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(RegisterResponse {
                    success: false,
                    message: "Internal server error".to_string(),
                }),
            )
                .into_response()
        }
    };

    // Insert user
    let result = sqlx::query("INSERT INTO users (email, password_hash) VALUES (?, ?)")
        .bind(&req.username)
        .bind(&password_hash)
        .execute(&state.db)
        .await;

    match result {
        Ok(_) => (
            StatusCode::CREATED,
            Json(RegisterResponse {
                success: true,
                message: "Registration successful".to_string(),
            }),
        )
            .into_response(),
        Err(e) => {
            tracing::error!("Database error: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(RegisterResponse {
                    success: false,
                    message: "Internal server error".to_string(),
                }),
            )
                .into_response()
        }
    }
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/api/auth/login", post(login))
        .route("/api/auth/register", post(register))
        .with_state(state)
}
