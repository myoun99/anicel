//! The Android context cpal's AAudio host asks the JVM through
//! (`ndk_context::android_context`): for the mixer's bursts as a stream
//! opens, and for the device list. Nothing set it, and the app died two
//! seconds after launch, opening its output — the context's `expect`
//! panicking across the door (board android-dies-opening-the-sound-output,
//! 2026-11-16, on the tablet). The plugin hands it as it attaches to the
//! engine (`GpuEnginePlugin.onAttachedToEngine`), before Dart's main can
//! open a device; until it has, the OS's context does not come up
//! (`backend::session`) and an open fails as one the OS refused.

use std::ffi::c_void;
use std::sync::Once;
use std::sync::atomic::{AtomicBool, Ordering::SeqCst};

use jni_sys::{JNIEnv, JavaVM, jobject};

static HANDING: Once = Once::new();
static HANDED: AtomicBool = AtomicBool::new(false);

/// Whether the plugin has handed the context.
pub(crate) fn context_handed() -> bool {
    HANDED.load(SeqCst)
}

/// `GpuEnginePlugin.handAndroidContext`: the app's context, held for the
/// life of the process by a global reference that is never let go.
///
/// ⛔ONCE: `initialize_android_context` asserts it was never called before,
/// and an engine started again attaches the plugin again — handing the same
/// application's context, which the first hand already holds.
///
/// # Safety
/// Called by the JVM, with the calling thread's `JNIEnv` and a `Context`.
#[unsafe(no_mangle)]
pub unsafe extern "system" fn Java_com_myoun_gpu_1engine_GpuEnginePlugin_handAndroidContext(
    env: *mut JNIEnv,
    _plugin: jobject,
    context: jobject,
) {
    HANDING.call_once(|| {
        // SAFETY: `env` is the JVM's for this thread (the contract).
        let table = unsafe { &**env };
        let (Some(get_java_vm), Some(new_global_ref)) = (table.GetJavaVM, table.NewGlobalRef) else {
            return;
        };
        let mut vm: *mut JavaVM = std::ptr::null_mut();
        // SAFETY: as above; `context` is the call's live local reference.
        let global = unsafe {
            if get_java_vm(env, &mut vm) != 0 {
                return;
            }
            new_global_ref(env, context)
        };
        if vm.is_null() || global.is_null() {
            return;
        }
        // SAFETY: the process's JVM, and a global reference nobody deletes;
        // the `Once` makes this the one call.
        unsafe { ndk_context::initialize_android_context(vm.cast::<c_void>(), global.cast::<c_void>()) };
        HANDED.store(true, SeqCst);
    });
}
