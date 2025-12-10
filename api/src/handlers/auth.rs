use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::{extract::State, Json};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

use crate::{
    error::AppError,
    models::user::{AuthResponse, CreateUser, LoginPayload, User},
};

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    sub: String, // email
    exp: usize,
}

pub async fn register(
    State(pool): State<SqlitePool>,
    Json(payload): Json<CreateUser>,
) -> Result<Json<User>, AppError> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(payload.password.as_bytes(), &salt)?
        .to_string();

    let user = sqlx::query_as!(
        User,
        "INSERT INTO users (email, password_hash) VALUES (?, ?) RETURNING id as \"id!\", email as \"email!\", password_hash as \"password_hash!\", created_at as \"created_at!\"",
        payload.email,
        password_hash
    )
    .fetch_one(&pool)
    .await?;

    Ok(Json(user))
}

pub async fn login(
    State(pool): State<SqlitePool>,
    Json(payload): Json<LoginPayload>,
) -> Result<Json<AuthResponse>, AppError> {
    let user = sqlx::query_as!(
        User,
        "SELECT id as \"id!\", email as \"email!\", password_hash as \"password_hash!\", created_at as \"created_at!\" FROM users WHERE email = ?",
        payload.email
    )
    .fetch_optional(&pool)
    .await?
    .ok_or(AppError::LoginFail)?;

    let parsed_hash = PasswordHash::new(&user.password_hash)?;
    Argon2::default()
        .verify_password(payload.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::LoginFail)?;

    // Generate JWT
    let expiration = chrono::Utc::now()
        .checked_add_signed(chrono::Duration::hours(24))
        .expect("valid timestamp")
        .timestamp();

    let claims = Claims {
        sub: user.email,
        exp: expiration as usize,
    };

    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret("secret".as_ref()),
    )?;

    Ok(Json(AuthResponse { token }))
}
