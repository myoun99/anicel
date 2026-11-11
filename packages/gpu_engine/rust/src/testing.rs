//! What the GPU tests share.

use std::sync::OnceLock;

use crate::device::Engine;

pub use ledger::assert_pinned;

/// The engine on the platform's first adapter, opened once for the whole
/// test process, as the app opens one device: blend's tests opened one
/// per test, put eighteen D3D12 devices up at once, and the process died
/// on a cold compile (exit 2173, RTX 4080, 2026-11-05). Every kernel
/// folder's tests come here, so none has to make the same fix of its own
/// (관제, gpu-engine-skeleton 2026-11-05 14:49).
///
/// 🚨ITS ERRORS PANIC, AS wgpu's DID (관제 2026-11-11, on the lost-device
/// lane): the app's engine notes an error no scope catches and fails its
/// next wait by it (`Refusals`, in `device.rs`), so a test that never
/// waits would pass over one — here it ends the test that raised it, where
/// it is raised, the alarm these tests had while it ended the process.
pub fn first_engine() -> &'static Engine {
    static ENGINE: OnceLock<Engine> = OnceLock::new();
    ENGINE.get_or_init(|| {
        let engine = Engine::open_first().expect("these tests need a GPU adapter");
        let alarm = |error: wgpu::Error| panic!("wgpu error: {error}");
        engine.device.on_uncaptured_error(std::sync::Arc::new(alarm));
        engine
    })
}

/// `buffer`'s bytes once the GPU is done with all that was submitted — the
/// engine's own read-back (`Engine::read_buffer`), which the cel pixel pass
/// hands the app its runs by. The buffer is `COPY_SRC`.
pub fn read_buffer(engine: &Engine, buffer: &wgpu::Buffer) -> Vec<u8> {
    engine.read_buffer(buffer).expect("read back")
}

/// The last error a call of the C ABI left, as the app reads it.
pub fn last_error() -> String {
    let mut buffer = [0u8; 256];
    // SAFETY: `buffer` holds its length.
    let length = unsafe { crate::gpu_engine_last_error(buffer.as_mut_ptr(), buffer.len()) };
    String::from_utf8_lossy(&buffer[..length.min(buffer.len())]).into_owned()
}

/// Bytes this thread holds from the heap, so a test sees a free give back
/// what its new took — a leak answers like a free
/// (`kernels/shared/every_free.rs`).
///
/// ⛔ONE A CRATE: Rust takes one `#[global_allocator]` in a crate, so every
/// test of this one counts here, the ink entry's among them (캔버스 베이스,
/// connection-round-checklist 2026-11-08 00:10). fx_plugin's tests count
/// the same way in a crate of their own: two, and a third crate that
/// counts is where they move into a test crate of the workspace's, as the
/// ledger's reader did (브러시/렌더링 00:08).
struct Counting;

thread_local! {
    static HELD: std::cell::Cell<isize> = const { std::cell::Cell::new(0) };
}

pub fn held() -> isize {
    HELD.with(std::cell::Cell::get)
}

fn count(bytes: isize) {
    let _ = HELD.try_with(|held| held.set(held.get() + bytes));
}

// SAFETY: the system's allocator, counted.
unsafe impl std::alloc::GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: std::alloc::Layout) -> *mut u8 {
        count(layout.size() as isize);
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.alloc(layout) }
    }

    unsafe fn dealloc(&self, at: *mut u8, layout: std::alloc::Layout) {
        count(-(layout.size() as isize));
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.dealloc(at, layout) }
    }
}

#[global_allocator]
static COUNTING: Counting = Counting;

#[test]
fn the_tests_share_one_device() {
    assert!(std::ptr::eq(first_engine(), first_engine()));
}
