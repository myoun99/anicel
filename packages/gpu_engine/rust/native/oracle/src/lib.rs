//! The C answer key (native-to-rust, 관제 2026-11-06). The app's native C
//! is moving to Rust a module at a time, each module to a crate beside this
//! one; until the connection round switches the app over and deletes the
//! C, a module's Rust is held to the C, byte for byte, through what the
//! engine exports.
//!
//! The key is the engine the app ships, as CMake builds it
//! (`packages/qa_native/src/CMakeLists.txt`) — not the C compiled once more
//! here, under other flags — loaded from `QA_ENGINE_PATH`. The workspace's
//! `.cargo/config.toml` points that at this checkout's own build on
//! Windows, and CI sets it. A land builds the lane's engine from the lane's
//! C before it runs the crates' tests (`tool/lane.sh`, refusals 6 and 8).
//!
//! ⛔A MISSING ENGINE FAILS, IT NEVER SKIPS: a comparison skipped prints the
//! same green as one that held (the Dart suites learnt it twice —
//! `test/helpers/native_engine_path.dart`).
//!
//! A module's tests call the exports its C has through [`export`] and hold
//! the Rust's bytes to theirs: on the cases the C's own tests run, on the
//! files the Dart parity suites read, and on inputs made up in the test. A
//! function the engine does not export — a header's `static` — is held to
//! through the export that calls it. A module whose C is a library of its
//! own beside the engine (`qa_tablet`, the pen) is held to that library
//! through [`sidecar_export`].

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock, PoisonError};

use libloading::Library;

const MISSING: &str = "no C engine to compare with — build it with \
    `bash tool/lane.sh engine` (or cmake -S packages/qa_native/src -B \
    build/native_standalone && cmake --build build/native_standalone \
    --config Release), or set QA_ENGINE_PATH";

/// The engine, loaded once for the test binary.
pub fn engine() -> &'static Library {
    static ENGINE: OnceLock<Library> = OnceLock::new();
    ENGINE.get_or_init(|| {
        let path = std::env::var("QA_ENGINE_PATH").unwrap_or_else(|_| panic!("{MISSING}"));
        // SAFETY: the library the app itself loads; loading it here runs
        // what loading it there runs.
        unsafe { Library::new(&path) }
            .unwrap_or_else(|error| panic!("{path}: {error} — {MISSING}"))
    })
}

/// The engine's export `name`, as `F`.
///
/// # Safety
/// `F` is the function pointer type of the export's C declaration.
pub unsafe fn export<F: Copy>(name: &str) -> F {
    // SAFETY: the caller's contract.
    unsafe { export_of(engine(), "the engine", name) }
}

/// A library the engine's build makes beside the engine, by the name CMake
/// gives it: the C of a module the engine does not carry (`qa_tablet`), or
/// a library a module's tests hand to it (the fx host's sample plugins).
pub fn beside(name: &str) -> PathBuf {
    engine();
    let engine = PathBuf::from(std::env::var("QA_ENGINE_PATH").expect("the engine's path"));
    let path = engine.with_file_name(libloading::library_filename(name));
    assert!(path.is_file(), "no {} beside the engine — `bash tool/lane.sh engine`", path.display());
    path
}

/// The library [`beside`] the engine called `name`, loaded once for the
/// test binary.
pub fn sidecar(name: &str) -> &'static Library {
    static LOADED: Mutex<Vec<(String, &'static Library)>> = Mutex::new(Vec::new());
    let mut loaded = LOADED.lock().unwrap_or_else(PoisonError::into_inner);
    if let Some((_, library)) = loaded.iter().find(|(own, _)| own == name) {
        return library;
    }
    let path = beside(name);
    // SAFETY: a library the app itself loads, as the engine is.
    let library = unsafe { Library::new(&path) }
        .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
    let library: &'static Library = Box::leak(Box::new(library));
    loaded.push((name.to_owned(), library));
    library
}

/// The export `name` of the library [`sidecar`] calls `library`, as `F`.
///
/// # Safety
/// `F` is the function pointer type of the export's C declaration.
pub unsafe fn sidecar_export<F: Copy>(library: &str, name: &str) -> F {
    // SAFETY: the caller's contract.
    unsafe { export_of(sidecar(library), library, name) }
}

/// # Safety
/// `F` is the function pointer type of the export's C declaration.
unsafe fn export_of<F: Copy>(library: &Library, called: &str, name: &str) -> F {
    // SAFETY: the caller's contract.
    let symbol = unsafe { library.get::<F>(name.as_bytes()) }
        .unwrap_or_else(|error| panic!("{called} exports no {name}: {error}"));
    *symbol
}

#[cfg(test)]
mod tests {
    use super::export;

    // A key built from other C would hold the Rust to the wrong answers:
    // the engine must answer with the ABI this checkout's C declares.
    #[test]
    fn the_engine_answers_with_the_abi_its_c_declares() {
        // SAFETY: qa_engine.c — `int32_t qa_engine_abi_version(void)`.
        let abi = unsafe { export::<extern "C" fn() -> i32>("qa_engine_abi_version") }();
        // This checkout's C, read when the test runs: every checkout builds
        // into the trunk's one target folder, and a test built in a lane runs
        // on the trunk (gpu_engine's kernels/shared/one_checkout.rs).
        let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
        let path = format!("{crate_dir}/../../../../qa_native/src/qa_engine.c");
        let c = std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{path}: {error}"));
        let declared: i32 = c
            .split("qa_engine_abi_version(void) { return ")
            .nth(1)
            .and_then(|rest| rest.split(';').next())
            .and_then(|number| number.trim().parse().ok())
            .expect("LIVENESS — qa_engine.c declares its ABI");
        assert_eq!(
            abi, declared,
            "the engine is not built from this checkout's C — `bash tool/lane.sh engine`"
        );
    }
}
