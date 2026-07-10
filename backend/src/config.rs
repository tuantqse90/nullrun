#[derive(Debug, Clone)]
pub struct Config {
    pub bind_addr: String,
    pub database_url: String,
    pub redis_url: String,
    pub jwt_secret: String,
    /// "log" = OTP codes are logged + echoed in the response (dev only).
    /// A real SMS provider replaces this before any external user sees the app.
    pub sms_mode: SmsMode,
    /// "dev" = attestation accepted without Apple verification (no iOS build exists yet).
    /// "apple" = full App Attest verification (required before production).
    pub attest_mode: AttestMode,
    /// Static token for partner-facing endpoints (reconciliation) until the
    /// M6 dashboard brings real partner auth.
    pub partner_api_token: String,
    /// Static token for the internal admin console. Replace with real
    /// role-based auth before any non-founder gets access.
    pub admin_api_token: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SmsMode {
    Log,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AttestMode {
    Dev,
    Apple,
}

pub const OTP_TTL_SECS: i64 = 300;
pub const OTP_MAX_REQUESTS_PER_WINDOW: i64 = 3;
pub const OTP_REQUEST_WINDOW_SECS: i64 = 900;
pub const OTP_MAX_VERIFY_ATTEMPTS: i64 = 5;
pub const ACCESS_TOKEN_TTL_SECS: i64 = 900;
pub const REFRESH_TOKEN_TTL_DAYS: i64 = 30;
pub const ATTEST_CHALLENGE_TTL_SECS: i64 = 300;
// Anti-cheat rate caps (M3): keep session farming unprofitable.
pub const SESSION_CREATE_COOLDOWN_SECS: i64 = 30;
pub const MAX_SESSIONS_PER_DAY: i64 = 20;

impl Config {
    pub fn from_env() -> Self {
        let jwt_secret = env_or("JWT_SECRET", "dev-secret-change-me");
        if jwt_secret == "dev-secret-change-me" {
            tracing::warn!("JWT_SECRET not set — using insecure dev default");
        }
        let attest_mode = match env_or("ATTEST_MODE", "dev").as_str() {
            "apple" => AttestMode::Apple,
            _ => AttestMode::Dev,
        };
        Self {
            bind_addr: env_or("BIND_ADDR", "0.0.0.0:8080"),
            database_url: env_or(
                "DATABASE_URL",
                "postgres://nullshift:nullshift@localhost:5433/nullshift",
            ),
            redis_url: env_or("REDIS_URL", "redis://localhost:6380"),
            jwt_secret,
            sms_mode: SmsMode::Log,
            attest_mode,
            partner_api_token: env_or("PARTNER_API_TOKEN", "dev-partner-token"),
            admin_api_token: env_or("ADMIN_API_TOKEN", "dev-admin-token"),
        }
    }
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn env_or_falls_back_to_default() {
        assert_eq!(env_or("NULLSHIFT_UNSET_VAR", "fallback"), "fallback");
    }
}
