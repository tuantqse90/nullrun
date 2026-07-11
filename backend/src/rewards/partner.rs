//! Partner adapter layer. Guardian is the ANCHOR partner, not the only one —
//! every reward row carries a partner code and resolves to an adapter here.
//!
//! Only the mock exists until Guardian BD access lands (the project's #1 open
//! item). The mock assumes the voucher-code baseline: we issue a code, the
//! store scans/enters it. Replace `issue_voucher` internals with the real
//! API call when the integration shape is known.

use rand::Rng;
use uuid::Uuid;

#[derive(Debug)]
pub struct VoucherIssue {
    pub voucher_code: String,
    pub partner_ref: String,
}

#[derive(Debug, thiserror::Error)]
#[allow(dead_code)] // the mock never fails; the real Guardian adapter will
pub enum PartnerError {
    #[error("partner unavailable: {0}")]
    Unavailable(String),
}

pub enum Adapter {
    GuardianMock,
    /// The Tasco/VETC ecosystem partners (VETC toll, VETC GO mobility, and the
    /// wider Tasco ecosystem). One mock issuing partner-prefixed voucher codes
    /// until the real Tasco/VETC BD integration lands.
    TascoMock {
        prefix: &'static str,
    },
}

impl Adapter {
    pub fn for_code(code: &str) -> Option<Self> {
        match code {
            "guardian" => Some(Adapter::GuardianMock),
            "vetc" => Some(Adapter::TascoMock { prefix: "VETC" }),
            "vetcgo" => Some(Adapter::TascoMock { prefix: "VGO" }),
            "tasco" => Some(Adapter::TascoMock { prefix: "TASCO" }),
            _ => None,
        }
    }

    /// True when redeeming a reward from this partner requires a linked
    /// Guardian membership. Only Guardian rewards do — Tasco/VETC rewards
    /// redeem straight from the user's activity points.
    pub fn requires_guardian_link(code: &str) -> bool {
        code == "guardian"
    }

    /// Validates a partner membership id at link time.
    /// Hội Cam card format is unknown until BD access — accept 6–16 digits.
    pub fn valid_member_id(&self, member_id: &str) -> bool {
        let n = member_id.len();
        (6..=16).contains(&n) && member_id.bytes().all(|b| b.is_ascii_digit())
    }

    pub async fn issue_voucher(&self, redemption_id: Uuid) -> Result<VoucherIssue, PartnerError> {
        let prefix = match self {
            Adapter::GuardianMock => "GRD",
            Adapter::TascoMock { prefix } => prefix,
        };
        let code = random_code(8);
        Ok(VoucherIssue {
            voucher_code: format!("{prefix}-{}-{}", &code[..4], &code[4..]),
            partner_ref: format!("mock-{redemption_id}"),
        })
    }
}

/// A short, unambiguous voucher code (no easily-confused characters).
fn random_code(len: usize) -> String {
    const CHARS: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::rng();
    (0..len)
        .map(|_| CHARS[rng.random_range(0..CHARS.len())] as char)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn member_id_validation() {
        let a = Adapter::GuardianMock;
        assert!(a.valid_member_id("123456"));
        assert!(a.valid_member_id("8412345678901234"));
        assert!(!a.valid_member_id("12345")); // too short
        assert!(!a.valid_member_id("12345678901234567")); // too long
        assert!(!a.valid_member_id("12a456")); // non-digit
    }

    #[tokio::test]
    async fn mock_issues_formatted_vouchers() {
        let a = Adapter::GuardianMock;
        let v = a.issue_voucher(Uuid::new_v4()).await.unwrap();
        assert!(v.voucher_code.starts_with("GRD-"), "{}", v.voucher_code);
        assert_eq!(v.voucher_code.len(), 13);
        assert!(v.partner_ref.starts_with("mock-"));
    }

    #[tokio::test]
    async fn tasco_partners_issue_prefixed_vouchers() {
        for (code, prefix) in [("vetc", "VETC-"), ("vetcgo", "VGO-"), ("tasco", "TASCO-")] {
            let a = Adapter::for_code(code).expect("adapter");
            let v = a.issue_voucher(Uuid::new_v4()).await.unwrap();
            assert!(v.voucher_code.starts_with(prefix), "{}", v.voucher_code);
        }
    }

    #[test]
    fn only_guardian_needs_a_link() {
        assert!(Adapter::requires_guardian_link("guardian"));
        assert!(!Adapter::requires_guardian_link("vetc"));
        assert!(!Adapter::requires_guardian_link("vetcgo"));
        assert!(!Adapter::requires_guardian_link("tasco"));
    }

    #[test]
    fn unknown_partner_is_none() {
        assert!(Adapter::for_code("insurer_x").is_none());
    }
}
