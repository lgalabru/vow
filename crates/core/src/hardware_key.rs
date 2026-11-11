//! Offline key-method policy. Capability reports are transport observations, not attestation.
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Capability {
    Supported,
    Unsupported,
    Incompatible,
    Failed,
    Unavailable,
}
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Method {
    Fido2,
    Piv,
    Webauthn,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    action: String,
    direct_fido: Capability,
    piv: Capability,
    piv_ready: bool,
    native_configured: bool,
    #[serde(default)]
    enrolled_method: Option<Method>,
}
#[derive(Debug, Serialize)]
struct Decision {
    format: &'static str,
    method: Option<Method>,
    state: &'static str,
    reason: &'static str,
    writes_permitted: bool,
}
impl Decision {
    fn new(method: Option<Method>, state: &'static str, reason: &'static str) -> Self {
        Self {
            format: "vow.hardware-key-policy.v1",
            method,
            state,
            reason,
            writes_permitted: false,
        }
    }
}
fn decide(r: Request) -> Result<Decision, String> {
    if r.action != "hardware_key_policy" || (r.piv_ready && r.piv != Capability::Supported) {
        return Err("Invalid hardware-key capability report.".into());
    }
    if let Some(method) = r.enrolled_method {
        let ready = match method {
            Method::Fido2 => r.direct_fido == Capability::Supported,
            Method::Piv => r.piv == Capability::Supported && r.piv_ready,
            Method::Webauthn => r.native_configured,
        };
        return Ok(Decision::new(
            Some(method),
            if ready { "pinned" } else { "blocked" },
            "The enrolled method is pinned. Changing methods requires explicit enrollment.",
        ));
    }
    Ok(match r.direct_fido {
        Capability::Supported => Decision::new(
            Some(Method::Fido2),
            "selected",
            "Use direct offline USB signing with the existing FIDO2 PIN.",
        ),
        Capability::Unsupported => match r.piv {
            Capability::Supported if r.piv_ready => Decision::new(
                Some(Method::Piv),
                "selected",
                "Use the prepared smart-card credential and its existing PIN.",
            ),
            Capability::Supported => Decision::new(
                Some(Method::Piv),
                "setup_required",
                "Prepare smart-card signing on the Mac. No PIN or credential was changed.",
            ),
            Capability::Unsupported | Capability::Incompatible => Decision::new(
                None,
                "unsupported",
                "This key needs administrator preparation or replacement with compatible hardware.",
            ),
            Capability::Failed | Capability::Unavailable => Decision::new(
                None,
                "blocked",
                "The smart-card check failed. No other signing method was selected.",
            ),
        },
        Capability::Incompatible => Decision::new(
            None,
            "unsupported",
            "The USB FIDO application cannot meet Vow's enrollment requirements.",
        ),
        Capability::Failed | Capability::Unavailable => Decision::new(
            None,
            "blocked",
            "The USB FIDO check did not complete. No fallback was selected.",
        ),
    })
}
pub fn evaluate(input: &Value) -> Result<Value, String> {
    let request = serde_json::from_value(input.clone())
        .map_err(|_| "Invalid hardware-key policy request.")?;
    serde_json::to_value(decide(request)?).map_err(|_| "Cannot encode hardware-key policy.".into())
}
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn request(fido: &str, piv: &str, ready: bool) -> Value {
        json!({"action":"hardware_key_policy", "direct_fido":fido,"piv":piv,"piv_ready":ready,"native_configured":true})
    }
    #[test]
    fn new_offline_enrollment_prefers_direct_fido_even_with_native_configuration() {
        let result = evaluate(&request("supported", "supported", true)).unwrap();
        assert_eq!(result["method"], "fido2");
        assert_eq!(result["state"], "selected");
        assert_eq!(result["writes_permitted"], false);
    }
    #[test]
    fn only_explicit_unsupported_result_can_offer_piv() {
        for fido in ["failed", "unavailable", "incompatible"] {
            let result = evaluate(&request(fido, "supported", true)).unwrap();
            assert!(result["method"].is_null());
        }
        assert_eq!(
            evaluate(&request("unsupported", "supported", true)).unwrap()["method"],
            "piv"
        );
        assert_eq!(
            evaluate(&request("unsupported", "supported", false)).unwrap()["state"],
            "setup_required"
        );
    }
    #[test]
    fn all_capability_combinations_preserve_enrolled_method_and_never_allow_writes() {
        for method in ["fido2", "piv", "webauthn"] {
            for fido in [
                "supported",
                "unsupported",
                "incompatible",
                "failed",
                "unavailable",
            ] {
                for piv in [
                    "supported",
                    "unsupported",
                    "incompatible",
                    "failed",
                    "unavailable",
                ] {
                    for native in [true, false] {
                        let mut input = request(fido, piv, piv == "supported");
                        input["enrolled_method"] = json!(method);
                        input["native_configured"] = json!(native);
                        let result = evaluate(&input).unwrap();
                        assert_eq!(result["method"], method);
                        assert_eq!(result["writes_permitted"], false);
                        let ready = match method {
                            "fido2" => fido == "supported",
                            "piv" => piv == "supported",
                            _ => native,
                        };
                        assert_eq!(result["state"], if ready { "pinned" } else { "blocked" });
                    }
                }
            }
        }
    }
    #[test]
    fn unprepared_existing_piv_is_blocked_without_changing_method() {
        let mut input = request("supported", "supported", false);
        input["enrolled_method"] = json!("piv");
        let result = evaluate(&input).unwrap();
        assert_eq!(result["method"], "piv");
        assert_eq!(result["state"], "blocked");
    }
    #[test]
    fn malformed_unknown_and_contradictory_reports_fail_closed() {
        for input in [
            json!({}),
            json!({"direct_fido":"guess"}),
            request("unsupported", "failed", true),
        ] {
            assert!(evaluate(&input).is_err());
        }
        for field in [
            "action",
            "direct_fido",
            "piv",
            "piv_ready",
            "native_configured",
        ] {
            let mut input = request("supported", "unsupported", false);
            input.as_object_mut().unwrap().remove(field);
            assert!(evaluate(&input).is_err());
        }
        let mut input = request("supported", "unsupported", false);
        input["allow_fallback"] = json!(true);
        assert!(evaluate(&input).is_err());
        input.as_object_mut().unwrap().remove("allow_fallback");
        input["enrolled_method"] = json!("unknown");
        assert!(evaluate(&input).is_err());
    }
}
