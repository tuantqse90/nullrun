/// Normalizes a Vietnamese mobile number to E.164 (+84xxxxxxxxx).
///
/// Accepts "0912345678", "84912345678", "+84 912 345 678" and common
/// separator characters. VN mobile prefixes after +84: 3, 5, 7, 8, 9
/// followed by 8 digits.
pub fn normalize_vn_phone(input: &str) -> Result<String, &'static str> {
    let cleaned: String = input
        .chars()
        .filter(|c| !matches!(c, ' ' | '-' | '.' | '(' | ')'))
        .collect();

    let digits = if let Some(rest) = cleaned.strip_prefix("+84") {
        rest.to_string()
    } else if let Some(rest) = cleaned.strip_prefix("84") {
        rest.to_string()
    } else if let Some(rest) = cleaned.strip_prefix('0') {
        rest.to_string()
    } else {
        return Err("phone must start with +84, 84, or 0");
    };

    if digits.len() != 9 || !digits.chars().all(|c| c.is_ascii_digit()) {
        return Err("invalid Vietnamese mobile number");
    }
    if !matches!(digits.as_bytes()[0], b'3' | b'5' | b'7' | b'8' | b'9') {
        return Err("invalid Vietnamese mobile prefix");
    }

    Ok(format!("+84{digits}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_common_formats() {
        for input in [
            "0912345678",
            "84912345678",
            "+84912345678",
            "+84 912 345 678",
            "0912-345-678",
        ] {
            assert_eq!(
                normalize_vn_phone(input).unwrap(),
                "+84912345678",
                "{input}"
            );
        }
    }

    #[test]
    fn rejects_invalid_numbers() {
        for input in [
            "12345",
            "0112345678",  // 01x is no longer a VN mobile prefix
            "091234567",   // too short
            "09123456789", // too long
            "+8591234567", // wrong country
            "091234567a",  // non-digit
            "",
        ] {
            assert!(normalize_vn_phone(input).is_err(), "{input}");
        }
    }
}
