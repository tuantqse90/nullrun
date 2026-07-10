use fred::prelude::*;
use rand::Rng;
use sha2::{Digest, Sha256};

use crate::{
    config::{
        OTP_MAX_REQUESTS_PER_WINDOW, OTP_MAX_VERIFY_ATTEMPTS, OTP_REQUEST_WINDOW_SECS, OTP_TTL_SECS,
    },
    error::AppError,
};

// Unused while sms_mode=log issues a fixed dev code; the real SMS provider
// switches back to random codes.
#[allow(dead_code)]
pub fn generate_code() -> String {
    let n: u32 = rand::rng().random_range(0..1_000_000);
    format!("{n:06}")
}

pub fn hash_code(code: &str) -> String {
    hex_digest(code.as_bytes())
}

fn hex_digest(data: &[u8]) -> String {
    let digest = Sha256::digest(data);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Stores the hashed OTP for `phone` with a TTL, enforcing the per-phone
/// request rate limit. Returns Err(TooManyRequests) when over the cap.
pub async fn store_code(redis: &Client, phone: &str, code: &str) -> Result<(), AppError> {
    let rl_key = format!("otp:req:{phone}");
    let count: i64 = redis.incr(&rl_key).await?;
    if count == 1 {
        let _: bool = redis.expire(&rl_key, OTP_REQUEST_WINDOW_SECS, None).await?;
    }
    if count > OTP_MAX_REQUESTS_PER_WINDOW {
        return Err(AppError::TooManyRequests);
    }

    let _: () = redis
        .set(
            format!("otp:code:{phone}"),
            hash_code(code),
            Some(Expiration::EX(OTP_TTL_SECS)),
            None,
            false,
        )
        .await?;
    let _: i64 = redis.del(format!("otp:att:{phone}")).await?;
    Ok(())
}

/// Verifies a submitted code. Wrong attempts are capped; hitting the cap
/// invalidates the code entirely (a 6-digit space must not be brute-forceable).
pub async fn verify_code(redis: &Client, phone: &str, code: &str) -> Result<(), AppError> {
    let code_key = format!("otp:code:{phone}");
    let stored: Option<String> = redis.get(&code_key).await?;
    let Some(stored) = stored else {
        return Err(AppError::Unauthorized);
    };

    let att_key = format!("otp:att:{phone}");
    let attempts: i64 = redis.incr(&att_key).await?;
    if attempts == 1 {
        let _: bool = redis.expire(&att_key, OTP_TTL_SECS, None).await?;
    }
    if attempts > OTP_MAX_VERIFY_ATTEMPTS {
        let _: i64 = redis.del(&code_key).await?;
        return Err(AppError::TooManyRequests);
    }

    if hash_code(code) != stored {
        return Err(AppError::Unauthorized);
    }

    let _: i64 = redis.del(vec![code_key, att_key]).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_codes_are_six_digits() {
        for _ in 0..100 {
            let code = generate_code();
            assert_eq!(code.len(), 6);
            assert!(code.chars().all(|c| c.is_ascii_digit()));
        }
    }

    #[test]
    fn hash_is_stable_and_hex() {
        let h = hash_code("123456");
        assert_eq!(h, hash_code("123456"));
        assert_eq!(h.len(), 64);
        assert_ne!(h, hash_code("123457"));
    }
}
