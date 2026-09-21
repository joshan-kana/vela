use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};

use serde::Serialize;
use vela_core::{Issue, User};
use vela_youtrack::Client;

#[derive(Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
enum BridgeResponse<T> {
    Ok { data: T },
    Error { message: String },
}

#[derive(Serialize)]
struct MyWork {
    user: User,
    issues: Vec<Issue>,
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_load_my_work_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    top: usize,
) -> *mut c_char {
    let response = catch_unwind(AssertUnwindSafe(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let client = client(&service_url, bearer_token.as_deref())?;

        let runtime = runtime()?;
        runtime.block_on(async {
            let user = client
                .current_user()
                .await
                .map_err(|error| error.to_string())?;
            let issues = client
                .issues(Some("for: me #Unresolved"), top)
                .await
                .map_err(|error| error.to_string())?;

            Ok(MyWork { user, issues })
        })
    }));

    bridge_json(response)
}

/// Frees a string allocated by the Vela FFI.
///
/// # Safety
///
/// The pointer must be null or a pointer returned by this crate through
/// CString::into_raw, and it must not have been freed already.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vela_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: value must have been returned by CString::into_raw in this crate.
        drop(unsafe { CString::from_raw(value) });
    }
}

fn client(service_url: &str, bearer_token: Option<&str>) -> Result<Client, String> {
    match bearer_token.filter(|token| !token.is_empty()) {
        Some(token) => Client::new(service_url, token),
        None => Client::guest(service_url),
    }
    .map_err(|error| error.to_string())
}

fn runtime() -> Result<tokio::runtime::Runtime, String> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| format!("failed to start async runtime: {error}"))
}

fn read_required_string(value: *const c_char, name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{name} is required"));
    }

    // SAFETY: callers must provide a valid, NUL-terminated C string.
    let value = unsafe { CStr::from_ptr(value) };
    value
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{name} must be valid UTF-8"))
}

fn read_optional_string(value: *const c_char) -> Result<Option<String>, String> {
    if value.is_null() {
        return Ok(None);
    }

    // SAFETY: callers must provide a valid, NUL-terminated C string.
    let value = unsafe { CStr::from_ptr(value) };
    value
        .to_str()
        .map(|value| Some(value.to_owned()))
        .map_err(|_| "bearer token must be valid UTF-8".to_owned())
}

fn bridge_json<T: Serialize>(
    response: Result<Result<T, String>, Box<dyn std::any::Any + Send>>,
) -> *mut c_char {
    let response = match response {
        Ok(Ok(data)) => BridgeResponse::Ok { data },
        Ok(Err(message)) => BridgeResponse::<T>::Error { message },
        Err(_) => BridgeResponse::<T>::Error {
            message: "Rust bridge panicked".to_owned(),
        },
    };

    json_c_string(&response)
}

fn json_c_string<T: Serialize>(value: &T) -> *mut c_char {
    let json = serde_json::to_string(value).unwrap_or_else(|error| {
        format!(r#"{{"status":"error","message":"failed to serialize bridge response: {error}"}}"#)
    });

    CString::new(json)
        .expect("serialized JSON must not contain NUL bytes")
        .into_raw()
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;

    use serde_json::Value;

    use super::{BridgeResponse, json_c_string};

    #[test]
    fn serializes_error_response() {
        let response = BridgeResponse::<()>::Error {
            message: "nope".to_owned(),
        };
        let pointer = json_c_string(&response);

        // SAFETY: pointer came from json_c_string above.
        let json = unsafe { CString::from_raw(pointer) };
        let value: Value = serde_json::from_slice(json.as_bytes()).unwrap();

        assert_eq!(value["status"], "error");
        assert_eq!(value["message"], "nope");
    }
}
