//! What the GPU tests share.

use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use crate::device::Engine;
use crate::kernels::composite::TileAt;
use crate::kernels::pool::Pool;

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

/// The turn a test holds for as long as a device of its own is up
/// ([`a_device_of_its_own`]): one test's at a time, beside
/// [`first_engine`]'s.
///
/// 🚨★★SEVERAL DEVICES UP AT ONCE, EACH COMPILING AND BINDING, END THE
/// PROCESS — exit 2173, which is 0x87D, the D3D12 debug layer's break on an
/// error: `Create…View: Specified CPU descriptor handle … does not refer to
/// a location in a descriptor heap`, of a heap its thread had only just
/// made. 2026-11-05 with eighteen up (blend's tests, above), and again
/// 2026-11-14 with sixteen: `device::tests` run first and all at once, ten
/// of them opened an engine each, and six more were to (🔬the dump of
/// 02:52, its stack named: wgpu's own bind group as it makes a device,
/// `create_bind_group` in `CreateUnorderedAccessView`, on the thread of a
/// test that opened one).
///
/// 🔬RTX 4080, 2026-11-14, on the code as it stood before those six:
/// sixteen threads each opening a device, compiling a kernel cold and
/// binding a buffer to it — dead within seconds, two runs of two, the same
/// stack; and of one wgpu instance all the same. The same compiles and
/// binds on ONE device from sixteen threads, 384 of them: none. Devices
/// opened and let go with nothing else, 640 on sixteen threads: none. One
/// device at work on twelve threads and others opened beside it one at a
/// time, nine minutes: none. ⚠️Why D3D12 reads such a heap so is not
/// known. Only a debug build has the layer: the crate's own tests, not the
/// app's library.
///
/// ↩️The fix of 2026-11-05 was a word — "as the app opens one device" —
/// and ten of `device::tests` and as many tests again elsewhere came to
/// open one of their own after it. So a test's
/// own device is opened under this turn and no other way
/// (`kernels/shared/one_device_turn.rs` reads the sources for it):
/// 🗣️관제 2026-11-14 04:20, the-ui-thread-never-enters-the-driver, 「이번엔
/// 쓸 수 없게 닫는다」.
static A_DEVICE_OF_ITS_OWN: Mutex<()> = Mutex::new(());

/// A test's hold on [`A_DEVICE_OF_ITS_OWN`], let go where it is dropped:
/// after every device opened under it, so it is taken first.
pub(crate) struct DeviceTurn(#[allow(dead_code)] MutexGuard<'static, ()>);

impl DeviceTurn {
    /// An engine on the platform's first adapter, this test's own: for one
    /// whose thread or device a test ends, loses or stands alone on.
    pub(crate) fn engine(&self) -> Engine {
        Engine::open_first().expect("these tests need a GPU adapter")
    }
}

/// The turn for a device of the calling test's own — waited for while
/// another test has one up. A test that failed with it in hand left it
/// behind in good order: the lock guards nothing but the turn.
pub(crate) fn a_device_of_its_own() -> DeviceTurn {
    DeviceTurn(A_DEVICE_OF_ITS_OWN.lock().unwrap_or_else(PoisonError::into_inner))
}

/// `buffer`'s bytes once the GPU is done with all that was submitted — the
/// engine's own read-back (`Engine::read_buffer`), which the cel pixel pass
/// hands the app its runs by. The buffer is `COPY_SRC`.
pub fn read_buffer(engine: &Engine, buffer: &wgpu::Buffer) -> Vec<u8> {
    engine.read_buffer(buffer).expect("read back")
}

/// A pool on [`first_engine`] holding `tiles` — a stored tile's bytes each
/// — on a cel of its own, and their places: what a test of the C ABI
/// names its tiles by. ⛔ONE: the executor's ABI tests and the cel pixel
/// kernels' each wrote it, and the fill's came as a third (11-12).
pub(crate) fn stored(tiles: &[Vec<u8>]) -> (Pool, Vec<TileAt>) {
    let engine = first_engine();
    let mut pool = Pool::new(engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let bytes: Vec<&[u8]> = tiles.iter().map(Vec::as_slice).collect();
    let places = pool.store(engine, cel, &bytes).expect("store");
    (pool, places)
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
