use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::LazyLock;

use serde::Serialize;
use vela_core::{AgileBoard, Issue, ProjectSchema, SavedQuery, User, UserRef, YouTrackDiscovery};
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
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_my_work(&service_url, bearer_token.as_deref(), top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_discover_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        discover(&service_url, bearer_token.as_deref())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_project_schema_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    project_id: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let project_id = read_required_string(project_id, "project ID")?;

        load_project_schema(&service_url, bearer_token.as_deref(), &project_id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_users_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    skip: usize,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_users(&service_url, bearer_token.as_deref(), skip, top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_agile_boards_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    skip: usize,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_agile_boards(&service_url, bearer_token.as_deref(), skip, top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_saved_queries_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    skip: usize,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_saved_queries(&service_url, bearer_token.as_deref(), skip, top)
    })
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

fn ffi_json<T: Serialize>(operation: impl FnOnce() -> Result<T, String>) -> *mut c_char {
    let response = catch_unwind(AssertUnwindSafe(operation));
    json_c_string(bridge_response_json(response))
}

fn discover(service_url: &str, bearer_token: Option<&str>) -> Result<YouTrackDiscovery, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async { client.discover().await.map_err(|error| error.to_string()) })
}

fn load_project_schema(
    service_url: &str,
    bearer_token: Option<&str>,
    project_id: &str,
) -> Result<ProjectSchema, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .project_schema(project_id)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_users(
    service_url: &str,
    bearer_token: Option<&str>,
    skip: usize,
    top: usize,
) -> Result<Vec<UserRef>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .users(skip, top)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_agile_boards(
    service_url: &str,
    bearer_token: Option<&str>,
    skip: usize,
    top: usize,
) -> Result<Vec<AgileBoard>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .agile_boards(skip, top)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_saved_queries(
    service_url: &str,
    bearer_token: Option<&str>,
    skip: usize,
    top: usize,
) -> Result<Vec<SavedQuery>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .saved_queries(skip, top)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_my_work(
    service_url: &str,
    bearer_token: Option<&str>,
    top: usize,
) -> Result<MyWork, String> {
    let client = client(service_url, bearer_token)?;
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
}

fn client(service_url: &str, bearer_token: Option<&str>) -> Result<Client, String> {
    match bearer_token.filter(|token| !token.is_empty()) {
        Some(token) => Client::new(service_url, token),
        None => Client::guest(service_url),
    }
    .map_err(|error| error.to_string())
}

static RUNTIME: LazyLock<Result<tokio::runtime::Runtime, String>> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .map_err(|error| format!("failed to start async runtime: {error}"))
});

fn runtime() -> Result<&'static tokio::runtime::Runtime, String> {
    RUNTIME.as_ref().map_err(|error| error.clone())
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

fn bridge_response_json<T: Serialize>(
    response: Result<Result<T, String>, Box<dyn std::any::Any + Send>>,
) -> String {
    let response = match response {
        Ok(Ok(data)) => BridgeResponse::Ok { data },
        Ok(Err(message)) => BridgeResponse::<T>::Error { message },
        Err(_) => BridgeResponse::<T>::Error {
            message: "Rust bridge panicked".to_owned(),
        },
    };

    serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(r#"{{"status":"error","message":"failed to serialize bridge response: {error}"}}"#)
    })
}

fn json_c_string(json: String) -> *mut c_char {
    CString::new(json)
        .expect("serialized JSON must not contain NUL bytes")
        .into_raw()
}

#[cfg(target_os = "android")]
mod android {
    use jni::{
        EnvUnowned,
        errors::ThrowRuntimeExAndDefault,
        objects::{JObject, JString},
        sys::{jint, jstring},
    };

    use super::{
        bridge_response_json, discover, load_agile_boards, load_my_work, load_project_schema,
        load_saved_queries, load_users,
    };
    use std::panic::{AssertUnwindSafe, catch_unwind};
    use std::sync::LazyLock;

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_initializeRust<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        context: JObject<'local>,
    ) {
        unowned_env
            .with_env(|env| -> jni::errors::Result<()> {
                rustls_platform_verifier::android::init_with_env(env, context)?;
                Ok(())
            })
            .resolve::<ThrowRuntimeExAndDefault>();
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_discoverJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    discover(&service_url, Some(&bearer_token))
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_loadProjectSchemaJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        project_id: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let project_id = project_id.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_project_schema(&service_url, Some(&bearer_token), &project_id)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_usersJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        skip: jint,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let skip = usize::try_from(skip.max(0)).expect("non-negative jint must fit usize");
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_users(&service_url, Some(&bearer_token), skip, top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_agileBoardsJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        skip: jint,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let skip = usize::try_from(skip.max(0)).expect("non-negative jint must fit usize");
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_agile_boards(&service_url, Some(&bearer_token), skip, top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_savedQueriesJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        skip: jint,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let skip = usize::try_from(skip.max(0)).expect("non-negative jint must fit usize");
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_saved_queries(&service_url, Some(&bearer_token), skip, top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_loadMyWorkJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_my_work(&service_url, Some(&bearer_token), top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;

    use serde_json::Value;

    use super::{BridgeResponse, bridge_response_json, json_c_string};

    #[test]
    fn serializes_error_response() {
        let response =
            Result::<Result<(), String>, Box<dyn std::any::Any + Send>>::Ok(Err("nope".to_owned()));
        let json = bridge_response_json(response);
        let pointer = json_c_string(json);

        // SAFETY: pointer came from json_c_string above.
        let json = unsafe { CString::from_raw(pointer) };
        let value: Value = serde_json::from_slice(json.as_bytes()).unwrap();

        assert_eq!(value["status"], "error");
        assert_eq!(value["message"], "nope");
    }

    #[test]
    fn bridge_response_shape_stays_stable() {
        let response = BridgeResponse::Ok { data: 42 };
        let value = serde_json::to_value(response).unwrap();

        assert_eq!(value["status"], "ok");
        assert_eq!(value["data"], 42);
    }
}
