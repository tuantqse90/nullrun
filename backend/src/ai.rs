//! Thin OpenAI-compatible chat client (the locked v2 architecture:
//! DeepSeek-style API over reqwest — no local models, no Python).
//! Configured via env: AI_BASE_URL, AI_API_KEY, AI_MODEL. Every caller
//! must degrade gracefully when no key is set — demos never die on a
//! missing credential.

use serde_json::{json, Value};

use crate::error::AppError;

#[derive(Debug, Clone)]
pub struct AiConfig {
    pub base_url: String,
    pub api_key: String,
    pub model: String,
}

impl AiConfig {
    pub fn from_env() -> Option<Self> {
        let api_key = std::env::var("AI_API_KEY").ok()?;
        if api_key.is_empty() {
            return None;
        }
        Some(Self {
            base_url: std::env::var("AI_BASE_URL")
                .unwrap_or_else(|_| "https://api.deepseek.com/v1".into()),
            api_key,
            model: std::env::var("AI_MODEL").unwrap_or_else(|_| "deepseek-chat".into()),
        })
    }
}

/// One chat completion. With `json_mode`, the model is instructed (and the
/// API asked) to return a single JSON object.
pub async fn chat(
    config: &AiConfig,
    system: &str,
    user: &str,
    json_mode: bool,
) -> Result<String, AppError> {
    let mut body = json!({
        "model": config.model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.7,
        "max_tokens": 500,
    });
    if json_mode {
        body["response_format"] = json!({"type": "json_object"});
    }
    complete(config, body).await
}

/// Chat completion over a full pre-built message array (system + turns) — for
/// multi-turn conversations. Same client and error handling as `chat`.
pub async fn chat_messages(
    config: &AiConfig,
    messages: &[Value],
    max_tokens: u32,
) -> Result<String, AppError> {
    let body = json!({
        "model": config.model,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": max_tokens,
    });
    complete(config, body).await
}

/// Shared request path: POST /chat/completions and pull out the reply text.
async fn complete(config: &AiConfig, body: Value) -> Result<String, AppError> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| AppError::Internal(format!("ai client: {e}")))?;
    let resp = client
        .post(format!(
            "{}/chat/completions",
            config.base_url.trim_end_matches('/')
        ))
        .bearer_auth(&config.api_key)
        .json(&body)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("ai request: {e}")))?;

    let status = resp.status();
    let payload: Value = resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("ai response: {e}")))?;
    if !status.is_success() {
        return Err(AppError::Internal(format!(
            "ai upstream {status}: {payload}"
        )));
    }
    payload["choices"][0]["message"]["content"]
        .as_str()
        .map(|s| s.trim().to_string())
        .ok_or_else(|| AppError::Internal("ai: empty completion".into()))
}

/// Best-effort JSON extraction — models occasionally wrap JSON in fences.
pub fn parse_json(raw: &str) -> Option<Value> {
    let trimmed = raw
        .trim()
        .trim_start_matches("```json")
        .trim_start_matches("```")
        .trim_end_matches("```");
    serde_json::from_str(trimmed.trim()).ok()
}
