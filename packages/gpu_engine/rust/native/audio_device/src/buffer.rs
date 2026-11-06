//! THE DEVICE'S OWN PCM (play-press-first-frame-stall, 10-15) —
//! `qa_audio_buffer_*`. Every source a schedule plays is a buffer made
//! once here and named by the address of its samples. A schedule copies
//! none of them: each source of the slot that plays a buffer HOLDS it, and
//! a buffer goes when its maker has let go and no slot holds it any more —
//! so its maker may let go at any time, even while it plays. ↩️Each
//! schedule copied every source's PCM into a block of its own, at every
//! press, seek and window advance (🔬33ms on the AMMI OP press).
//!
//! The C found a buffer by a magic word in a head before the samples,
//! which reads memory before any pointer it is handed; this keeps the
//! buffers in a book by address instead, and checks and holds a
//! schedule's sources under one lock. The callback never holds or lets go
//! — it reads a slot, and the slot's holds outlive every block that reads
//! it (`Transport::set_schedule`) — so the lock never meets the realtime
//! thread.

use std::collections::HashMap;
use std::ptr;
use std::sync::{LazyLock, Mutex, MutexGuard, PoisonError};

use audio_mix::Source;

/// Four samples, so the samples start 16-byte aligned, as the C's do.
#[repr(C, align(16))]
#[derive(Clone, Copy)]
struct Quad([f32; 4]);

struct Buffer {
    _quads: Vec<Quad>,
    floats: i64,
    holds: i32,
}

/// Every buffer there is, by the address of its samples.
static BUFFERS: LazyLock<Mutex<HashMap<usize, Buffer>>> = LazyLock::new(Default::default);

fn book() -> MutexGuard<'static, HashMap<usize, Buffer>> {
    BUFFERS.lock().unwrap_or_else(PoisonError::into_inner)
}

/// A buffer of `floats` samples, its maker holding it until [`release`];
/// the maker fills it before a schedule names it. Null when `floats` is
/// negative or the memory is not there.
pub(crate) fn new(floats: i64) -> *mut f32 {
    let Ok(count) = usize::try_from(floats) else {
        return ptr::null_mut();
    };
    let quads = count.max(1).div_ceil(4);
    let mut storage = Vec::new();
    if storage.try_reserve_exact(quads).is_err() {
        return ptr::null_mut();
    }
    storage.resize(quads, Quad([0.0; 4]));
    let samples = storage.as_mut_ptr().cast::<f32>();
    book().insert(samples as usize, Buffer { _quads: storage, floats, holds: 1 });
    samples
}

/// One more hold on `samples`, for a caller about to name them in a
/// schedule while their maker may let go: `samples`, or null when they
/// are not a buffer's.
pub(crate) fn retain(samples: *mut f32) -> *mut f32 {
    match book().get_mut(&(samples as usize)) {
        Some(buffer) => {
            buffer.holds += 1;
            samples
        }
        None => ptr::null_mut(),
    }
}

/// Lets go of one hold on `samples` — the maker's, a retain's or a slot's.
pub(crate) fn release(samples: *const f32) {
    let mut book = book();
    let key = samples as usize;
    if let Some(buffer) = book.get_mut(&key) {
        buffer.holds -= 1;
        if buffer.holds == 0 {
            book.remove(&key);
        }
    }
}

/// How many hold `samples`: its maker, each retain's caller and each
/// source of a slot that plays them. -1 when they are not a buffer's.
pub(crate) fn holds(samples: *const f32) -> i32 {
    book().get(&(samples as usize)).map_or(-1, |buffer| buffer.holds)
}

/// Holds the buffer each of `sources` plays — when every one plays
/// nothing, or every one of its length x channels samples lies inside a
/// buffer. Else holds none: the callback must never chase a pointer whose
/// life nobody holds.
pub(crate) fn hold_all(sources: &[Source]) -> bool {
    let mut book = book();
    let reads = |source: &Source| {
        if source.samples.is_null() {
            return true;
        }
        let Some(buffer) = book.get(&(source.samples as usize)) else {
            return false;
        };
        source.length <= 0 || source.channels <= 0 || source.length <= buffer.floats / i64::from(source.channels)
    };
    if !sources.iter().all(reads) {
        return false;
    }
    for source in sources {
        if let Some(buffer) = book.get_mut(&(source.samples as usize)) {
            buffer.holds += 1;
        }
    }
    true
}

/// Lets go of the hold each of `sources` has on its buffer.
pub(crate) fn let_go_all(sources: &[Source]) {
    for source in sources {
        release(source.samples);
    }
}
