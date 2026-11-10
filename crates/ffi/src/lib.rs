//! Version-one, session-based C ABI for the local prototype.
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    ffi::{CString, c_char},
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};
use vow_core::Session;
static NEXT: AtomicU64 = AtomicU64::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<u64, Session>>> = OnceLock::new();
fn sessions() -> &'static Mutex<HashMap<u64, Session>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}
fn output(v: Value) -> *mut c_char {
    CString::new(v.to_string())
        .expect("JSON escapes NUL")
        .into_raw()
}
/// Allocate a new independent prototype session. Zero means the session could not be created.
#[unsafe(no_mangle)]
pub extern "C" fn vow_session_create_v1() -> u64 {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    match sessions().lock() {
        Ok(mut s) => {
            s.insert(id, Session::default());
            id
        }
        Err(_) => 0,
    }
}
/// Destroy a session and all of its pending signing state.
#[unsafe(no_mangle)]
pub extern "C" fn vow_session_destroy_v1(id: u64) {
    if let Ok(mut s) = sessions().lock() {
        s.remove(&id);
    }
}
/// Borrow UTF-8 JSON for this call and return a Rust-owned JSON string.
/// # Safety
/// `data` must point to `len` readable bytes for the duration of the call.
/// Free the result exactly once with `vow_string_free_v1`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vow_dispatch_v1(id: u64, data: *const u8, len: usize) -> *mut c_char {
    if data.is_null() || len == 0 || len > 20 * 1024 * 1024 {
        return output(json!({"ok":false,"error":"Invalid request buffer."}));
    }
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Value, String> {
        // SAFETY: the caller guarantees valid storage; null/length were checked above.
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        let request: Value = serde_json::from_slice(bytes).map_err(|_| "Invalid request JSON.")?;
        let mut sessions = sessions()
            .lock()
            .map_err(|_| "The session is unavailable. Restart the app.")?;
        sessions
            .get_mut(&id)
            .ok_or("Session not found.")?
            .dispatch(&request)
    }));
    output(match result {
        Ok(Ok(data)) => json!({"ok":true,"data":data}),
        Ok(Err(error)) => json!({"ok":false,"error":error}),
        Err(_) => {
            json!({"ok":false,"error":"The request could not be completed. Restart the app."})
        }
    })
}
/// Release a returned string. A null pointer is allowed.
/// # Safety
/// The pointer must be an unfreed result from `vow_dispatch_v1`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vow_string_free_v1(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { CString::from_raw(ptr) });
    }
}

/// Profile a bounded preview transaction in the Mac SDK. No session/key state is exposed.
/// # Safety
/// `data` must point to `len` readable bytes; the owned result uses `vow_string_free_v1`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vow_profile_transaction_v1(data: *const u8, len: usize) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Value, String> {
        if data.is_null() || len == 0 || len > 16 * 1024 {
            return Err("Invalid profiling input size.".into());
        }
        // SAFETY: caller owns readable input for this call, checked for null and bounded length.
        let request: Value =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(data, len) })
                .map_err(|_| "Invalid profiling input.")?;
        #[cfg(target_os = "macos")]
        {
            vow_simulation::profile(&request)
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = request;
            Err("Profiling is available on Mac only.".into())
        }
    }));
    output(match result {
        Ok(Ok(data)) => json!({"ok":true,"data":data}),
        Ok(Err(error)) => json!({"ok":false,"error":error}),
        Err(_) => json!({"ok":false,"error":"Profiling failed. No approval was produced."}),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;
    fn request(id: u64, value: Value) -> Value {
        let bytes = serde_json::to_vec(&value).unwrap();
        // SAFETY: input storage is alive through dispatch and output is freed once.
        unsafe {
            let ptr = vow_dispatch_v1(id, bytes.as_ptr(), bytes.len());
            let result = serde_json::from_slice(CStr::from_ptr(ptr).to_bytes()).unwrap();
            vow_string_free_v1(ptr);
            result
        }
    }
    #[test]
    fn sessions_are_isolated_and_destroyed_handles_are_rejected() {
        let first = vow_session_create_v1();
        let second = vow_session_create_v1();
        assert!(
            request(first, json!({"action":"organization","name":"First team"}))["ok"]
                .as_bool()
                .unwrap()
        );
        assert_eq!(
            request(second, json!({"action":"snapshot"}))["data"]["organization"],
            "Solana Foundation"
        );
        vow_session_destroy_v1(first);
        assert_eq!(request(first, json!({"action":"snapshot"}))["ok"], false);
        vow_session_destroy_v1(second);
    }
    #[test]
    fn null_input_is_a_reported_error() {
        // SAFETY: null is explicitly supported by the rejected-input contract.
        unsafe {
            let ptr = vow_dispatch_v1(0, std::ptr::null(), 1);
            let result: Value = serde_json::from_slice(CStr::from_ptr(ptr).to_bytes()).unwrap();
            assert_eq!(result["ok"], false);
            vow_string_free_v1(ptr);
        }
    }
}
