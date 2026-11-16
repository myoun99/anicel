//! What the GPU tests share.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{OnceLock, PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};

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
    FIRST.get_or_init(|| {
        let engine = Engine::open_first().expect("these tests need a GPU adapter");
        let alarm = |error: wgpu::Error| panic!("wgpu error: {error}");
        engine.device().on_uncaptured_error(std::sync::Arc::new(alarm));
        SHARED_SUBMITS.store(engine.submits_as(), Ordering::Release);
        engine
    })
}

/// [`first_engine`]'s, once it is opened.
static FIRST: OnceLock<Engine> = OnceLock::new();

/// The number [`first_engine`]'s submits go by (`Engine::submits_as`) —
/// none till it is opened: an engine's threads are numbered from one.
static SHARED_SUBMITS: AtomicU64 = AtomicU64::new(0);

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
///
/// 🚨★★AND NONE AT WORK BESIDE THE SHARED ONE: a device of a test's own and
/// [`first_engine`]'s at work at once wrote wrong pixels on the Surface
/// (Intel), each of them — empty composites, another test's colours —, and
/// the GPU wrote them so: read twice, alike (🔬캔버스 베이스, 2026-11-15
/// 04:06–05:23, engine-pictures-keep-to-pool-pages: devices of a probe's
/// own beside the shared one, two runs of six red within 1,012 and 3,248
/// rounds; the same work on the shared device from two threads, five runs
/// and some 78,000 rounds, none). The crate's composite tests went on
/// failing so in full runs, with this turn one device at a time beside the
/// shared one: four tests, two gates of two, and the crate run whole on
/// the Surface 2 of 8 red, those of a device of its own left out 0 of 8
/// (🔬캔버스 베이스, posed-row-composite-tests-flicker-in-full-runs,
/// 2026-11-16 13:57–14:25, the two run in turn). So the turn is the GPU's:
/// taken once the shared device is through with what it was handed, and
/// held, the shared device's submits wait for it (`Queue::submit`).
/// ⚠️A test that holds it works no other device — the shared one's submit
/// would wait for the test that waits for it. ⏳Why the driver mixes two
/// devices' work is not known; the app opens one (`openAppGpuEngine`), and
/// Flutter's renderer is no D3D12 one.
static THE_GPU: RwLock<()> = RwLock::new(());

/// A test's hold on [`THE_GPU`], let go where it is dropped: after every
/// device opened under it, so it is taken first.
pub(crate) struct DeviceTurn(#[allow(dead_code)] RwLockWriteGuard<'static, ()>);

impl DeviceTurn {
    /// An engine on the platform's first adapter, this test's own: for one
    /// whose thread or device a test ends, loses or stands alone on.
    pub(crate) fn engine(&self) -> Engine {
        Engine::open_first().expect("these tests need a GPU adapter")
    }
}

/// The turn for a device of the calling test's own — waited for while
/// another test has one up, and given once the shared device is through
/// with what it was handed ([`THE_GPU`]). A test that failed with it in
/// hand left it behind in good order: the lock guards nothing but the turn.
pub(crate) fn a_device_of_its_own() -> DeviceTurn {
    let turn = turn_of(&THE_GPU);
    if let Some(shared) = FIRST.get() {
        shared.through_with_all_submitted();
    }
    turn
}

/// A hold on `turn` — the tests' ([`a_device_of_its_own`]), or one a
/// test of the turn keeps for itself, where no other test waits.
pub(crate) fn turn_of(turn: &'static RwLock<()>) -> DeviceTurn {
    DeviceTurn(turn.write().unwrap_or_else(PoisonError::into_inner))
}

/// A submit's hold on [`THE_GPU`] where the engine whose submits go by
/// `by` is [`first_engine`]'s — none for a device of a test's own.
pub(crate) fn submitting(by: u64) -> Option<RwLockReadGuard<'static, ()>> {
    let shared = SHARED_SUBMITS.load(Ordering::Acquire);
    (shared != 0 && shared == by).then(|| THE_GPU.read().unwrap_or_else(PoisonError::into_inner))
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

/// What the calling thread's next done on `engine` is told
/// (`Engine::done_then`): the bodies it handed over unwaited through, or
/// the first that failed and why, and the GPU done with what they
/// submitted.
pub(crate) fn done_here(engine: &Engine) -> Result<(), String> {
    let (tell, told) = std::sync::mpsc::channel();
    engine.done_then(move |done| {
        let _ = tell.send(done);
    });
    told.recv().expect("a done is told, once")
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

/// `bytes`, what this thread is counted to hold from here on: a verb's
/// body runs on a thread of the engine's as a call of its caller's, with
/// its caller's count and back with it (`Callers`, in `device.rs`).
pub fn put_held(bytes: isize) {
    HELD.with(|held| held.set(bytes));
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
