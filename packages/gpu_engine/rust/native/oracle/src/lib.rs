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
//! through the export that calls it.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

use std::sync::OnceLock;

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
    let symbol = unsafe { engine().get::<F>(name.as_bytes()) }
        .unwrap_or_else(|error| panic!("the engine exports no {name}: {error}"));
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
