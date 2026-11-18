//! The app's side of the fx plugin spec (the spec crate, sdk/fx/anicel-fx —
//! whose types, places and names this host reads the frame by): one plugin
//! opened from a native library or a WebAssembly module, asked the same
//! four questions either way — through the exports the app's
//! `QaFxPluginHost` binds by name (lib/src/native/qa_fx_plugin_host.dart)
//! in the GPU engine's library, which carries this crate (its lib.rs).
//! ↩️They were the C host's (qa_fx_plugin.h), which this crate replaced
//! (native-to-rust, 2026-11-06), held to it byte for byte until the
//! connection round deleted it (connection-round-checklist H, 2026-11-08 —
//! tests.rs keeps what it answered).
//!
//! 🗣️I-132-Q5 (유저 2026-10-27): 「a + 데스크톱은 같은 규격의 네이티브(.dll ·
//! .dylib)도」 — so the host has ONE frame writer (frame.rs) and two places
//! it writes to: its own memory for a native library, the module's linear
//! memory for a .wasm. Everything past opening is the same code.
//!
//! Why the spec is as it is — kept here, on the app's side, since the spec
//! crate is the SDK's and speaks to plugin makers (fx-plugin-sdk-publish,
//! 2026-11-04; the crate took the header's place on 유저 Q9 · 옛 플러그인
//! 없음, 2026-11-07):
//! 🗣️I-132-Q5: one .wasm runs on every platform and a desktop may also take
//! a native build of the same source, so the spec is a C FUNCTION SPEC that
//! a .dll speaks as well as a .wasm, not a WebAssembly component interface
//! (I-132-Q31: the component model stays a road to add on the wasm side) —
//! the spec crate's exports are `extern "C"` functions for that.
//! 🗣️I-132-Q29 (유저 2026-10-29): 「a + 플러그인이 다른 레이어를 읽기」 — a
//! 「layer」 parameter hands a plugin another row's picture. 「나중엔 최대한
//! 극한으로 확장 … 플러그인은 확장성이 젤 중요」: a plugin says what it can
//! do (`"can"`), so a later host can offer more — a GPU route, say, chosen
//! by the plugin as AE's GPU effects are — and an older plugin still runs.
//! ↩️No pointers in the frame: pointers would have made two layouts (4- and
//! 8-byte) the host fills differently, and a plugin built for the one would
//! read the other's fields wrong.
//! Published, spec 1 does not break: what comes later is spec 2 and `"can"`.
//!
//! ⚠️A plugin is asked by one thread at a time; two plugins may be asked at
//! once.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod frame;
mod job;
mod native;
mod wasm;

#[cfg(test)]
mod tests;

use std::ffi::{CStr, c_char, c_void};

pub use job::{BAD_JOB, FAILED, NO_ROOM, OK, Picture, RenderJob, TRAPPED};

use crate::frame::Plan;
use crate::job::{Head, Job};
use crate::native::Native;
use crate::wasm::Wasm;

/// An opened plugin of either kind — the one place the kind is asked.
enum Plugin {
    Native(Native),
    Wasm(Wasm),
}

impl Plugin {
    fn describe(&mut self, out: &mut [u8]) -> i32 {
        match self {
            Plugin::Native(native) => native.describe(out),
            Plugin::Wasm(wasm) => wasm.describe(out),
        }
    }

    fn reach(&mut self, head: &Head) -> i32 {
        match self {
            Plugin::Native(native) => native.reach(head),
            Plugin::Wasm(wasm) => wasm.reach(head),
        }
    }

    fn render(&mut self, job: &mut Job, plan: &Plan) -> i32 {
        match self {
            Plugin::Native(native) => native.render(job, plan),
            Plugin::Wasm(wasm) => wasm.render(job, plan),
        }
    }

    fn interprets(&self) -> bool {
        match self {
            Plugin::Native(_) => false,
            Plugin::Wasm(wasm) => wasm.interprets(),
        }
    }
}

/// Writes `what` into the caller's `error` room as the C host's snprintf
/// did: as much as fits before a NUL, and nothing where there is no room.
///
/// # Safety
/// `error` is null or holds `capacity` bytes.
unsafe fn say(error: *mut c_char, capacity: i32, what: &str) {
    if error.is_null() || capacity <= 0 {
        return;
    }
    let said = what.len().min(capacity as usize - 1);
    // SAFETY: the caller's contract; `said` + 1 is at most `capacity`.
    unsafe {
        std::ptr::copy_nonoverlapping(what.as_ptr().cast::<c_char>(), error, said);
        error.add(said).write(0);
    }
}

/// The plugin a handle names, or `None` for a null one.
///
/// # Safety
/// `handle` is null or came from an open and is not closed.
unsafe fn plugin<'a>(handle: *mut c_void) -> Option<&'a mut Plugin> {
    // SAFETY: the caller's contract.
    unsafe { handle.cast::<Plugin>().as_mut() }
}

/// A handle to `opened`, or null with why in `error`.
///
/// # Safety
/// `error` is null or holds `capacity` bytes.
unsafe fn handle(opened: Result<Plugin, String>, error: *mut c_char, capacity: i32) -> *mut c_void {
    match opened {
        Ok(plugin) => Box::into_raw(Box::new(plugin)).cast(),
        Err(why) => {
            // SAFETY: the caller's contract.
            unsafe { say(error, capacity, &why) };
            std::ptr::null_mut()
        }
    }
}

/// Opens the native plugin at `path` (UTF-8); null, with why in `error`,
/// where there is none.
///
/// # Safety
/// `path` is null or a NUL-terminated string; `error` is null or holds
/// `error_capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_open_native(
    path: *const c_char,
    error: *mut c_char,
    error_capacity: i32,
) -> *mut c_void {
    let opened = if path.is_null() {
        Err("no path")
    } else {
        // SAFETY: the caller's contract.
        Native::open(unsafe { CStr::from_ptr(path) })
    };
    let opened = opened.map(Plugin::Native).map_err(String::from);
    // SAFETY: the caller's contract.
    unsafe { handle(opened, error, error_capacity) }
}

/// Opens the WebAssembly plugin in `bytes`; null, with why in `error`,
/// where there is none.
///
/// # Safety
/// `bytes` is null or holds `length` bytes; `error` is null or holds
/// `error_capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_open_wasm(
    bytes: *const u8,
    length: i64,
    error: *mut c_char,
    error_capacity: i32,
) -> *mut c_void {
    let opened = if bytes.is_null() || length <= 0 {
        Err("no module".into())
    } else {
        // SAFETY: the caller's contract.
        let bytes = unsafe { std::slice::from_raw_parts(bytes, length as usize) };
        Wasm::open(bytes, wasm::INTERPRETS)
    };
    // SAFETY: the caller's contract.
    unsafe { handle(opened.map(Plugin::Wasm), error, error_capacity) }
}

/// The description's length in bytes; up to `capacity` of it in `out`.
///
/// # Safety
/// `handle` is null or an open plugin; `out` is null or holds `capacity`
/// bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_describe(
    handle: *mut c_void,
    out: *mut c_char,
    capacity: i32,
) -> i32 {
    // SAFETY: the caller's contract.
    match unsafe { plugin(handle) } {
        Some(plugin) if !out.is_null() && capacity > 0 => {
            // SAFETY: the caller's contract.
            let out = unsafe { std::slice::from_raw_parts_mut(out.cast(), capacity as usize) };
            plugin.describe(out)
        }
        _ => BAD_JOB,
    }
}

/// How far past its input the effect reaches for these values, in pixels.
///
/// # Safety
/// `handle` is null or an open plugin; `values` holds `value_count` values
/// of four doubles when that is above 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_reach(
    handle: *mut c_void,
    values: *const f64,
    value_count: i32,
    frame_index: i32,
    time: f64,
    frame_rate: f64,
    scale: f64,
) -> i32 {
    // SAFETY: the caller's contract.
    let Some(plugin) = (unsafe { plugin(handle) }) else {
        return BAD_JOB;
    };
    if value_count < 0 || (value_count > 0 && values.is_null()) {
        return BAD_JOB;
    }
    // SAFETY: the caller's contract, the count checked above.
    let values = unsafe { job::values(values, value_count) };
    plugin.reach(&Head { values, frame_index, time, frame_rate, scale })
}

/// Renders `job` into its output: [`OK`], or why not.
///
/// # Safety
/// `handle` is null or an open plugin; `job` is null or a job whose
/// pointers hold what [`RenderJob`] says they hold.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_render(handle: *mut c_void, job: *const RenderJob) -> i32 {
    // SAFETY: the caller's contract.
    let (Some(plugin), Some(job)) = (unsafe { plugin(handle) }, unsafe { job.as_ref() }) else {
        return BAD_JOB;
    };
    if !job::is_whole_job(job) {
        return BAD_JOB;
    }
    // SAFETY: the caller's contract, the job whole.
    let Some(mut job) = (unsafe { job::read(job) }) else {
        return BAD_JOB;
    };
    let Some(plan) = Plan::of(&job) else {
        return BAD_JOB;
    };
    plugin.render(&mut job, &plan)
}

/// # Safety
/// `handle` is null or an open plugin, never asked again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_close(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: the caller's contract.
        drop(unsafe { Box::from_raw(handle.cast::<Plugin>()) });
    }
}

/// 1 when `handle` is a module its engine interprets, as the engine itself
/// says; 0 for compiled code and a native library.
///
/// # Safety
/// `handle` is null or an open plugin.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_fx_plugin_interprets(handle: *mut c_void) -> i32 {
    // SAFETY: the caller's contract.
    unsafe { plugin(handle) }.is_some_and(|plugin| plugin.interprets()).into()
}

/// The job's size as this build lays it, for the Dart struct that mirrors
/// it.
#[unsafe(no_mangle)]
pub extern "C" fn qa_fx_render_job_sizeof() -> i32 {
    size_of::<RenderJob>() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_fx_picture_sizeof() -> i32 {
    size_of::<Picture>() as i32
}
