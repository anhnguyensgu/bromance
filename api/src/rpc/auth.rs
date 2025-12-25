use crate::models::user::{Claims, User};
use crate::AppState;
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use jsonwebtoken::{encode, Header};
use tonic::{Request, Response, Status};

pub mod auth_proto {
    tonic::include_proto!("auth");
}

use auth_proto::auth_service_server::AuthService;
use auth_proto::{LoginRequest, LoginResponse, RegisterRequest, RegisterResponse};

pub struct AuthServiceImpl {
    pub state: AppState,
}

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    async fn login(
        &self,
        request: Request<LoginRequest>,
    ) -> Result<Response<LoginResponse>, Status> {
        let req = request.into_inner();

        let user = sqlx::query_as!(
            User,
            "SELECT id as \"id!\", email as \"email!\", password_hash as \"password_hash!\", created_at as \"created_at!\" FROM users WHERE email = ?",
            req.username
        )
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(e.to_string()))?
        .ok_or(Status::unauthenticated("Invalid credentials"))?;

        let parsed_hash =
            PasswordHash::new(&user.password_hash).map_err(|e| Status::internal(e.to_string()))?;

        Argon2::default()
            .verify_password(req.password.as_bytes(), &parsed_hash)
            .map_err(|_| Status::unauthenticated("Invalid credentials"))?;

        let expiration = chrono::Utc::now()
            .checked_add_signed(chrono::Duration::hours(24))
            .ok_or_else(|| Status::internal("valid timestamp"))?
            .timestamp();

        let claims = Claims {
            sub: user.email,
            exp: expiration as usize,
        };

        let header = Header::new(jsonwebtoken::Algorithm::EdDSA);
        let token = encode(&header, &claims, &self.state.encoding_key)
            .map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(LoginResponse {
            token,
            success: true,
            message: "Login successful".to_string(),
        }))
    }

    async fn register(
        &self,
        request: Request<RegisterRequest>,
    ) -> Result<Response<RegisterResponse>, Status> {
        let req = request.into_inner();
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();
        let password_hash = argon2
            .hash_password(req.password.as_bytes(), &salt)
            .map_err(|e| Status::internal(e.to_string()))?
            .to_string();

        let _user = sqlx::query_as!(
            User,
            "INSERT INTO users (email, password_hash) VALUES (?, ?) RETURNING id as \"id!\", email as \"email!\", password_hash as \"password_hash!\", created_at as \"created_at!\"",
            req.username,
            password_hash
        )
        .fetch_one(&self.state.db)
        .await
        .map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(RegisterResponse {
            success: true,
            message: "User registered successfully".to_string(),
        }))
    }
}
