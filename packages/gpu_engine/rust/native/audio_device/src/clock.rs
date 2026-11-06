//! The monotonic clock both ends of a clock's line read: a callback when
//! it stamps a point, a reader when it asks how long ago that was. Never
//! the wall clock — that one is set, and a line drawn across a setting
//! jumps. The C's own calls, so a line keeps the C's sleep behaviour, and
//! safe on a realtime thread: neither locks nor allocates.

#[cfg(windows)]
pub(crate) fn now_us() -> i64 {
    use std::sync::OnceLock;

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn QueryPerformanceCounter(count: *mut i64) -> i32;
        fn QueryPerformanceFrequency(frequency: *mut i64) -> i32;
    }
    static FREQUENCY: OnceLock<i64> = OnceLock::new();
    let frequency = *FREQUENCY.get_or_init(|| {
        let mut frequency = 0;
        // SAFETY: a valid out-pointer; it cannot fail on XP and later.
        unsafe { QueryPerformanceFrequency(&mut frequency) };
        frequency
    });
    let mut counter = 0;
    // SAFETY: as above.
    unsafe { QueryPerformanceCounter(&mut counter) };
    // Whole seconds and the remainder apart: the counter times a million
    // overflows 64 bits within hours of uptime.
    counter / frequency * 1_000_000 + counter % frequency * 1_000_000 / frequency
}

#[cfg(unix)]
pub(crate) fn now_us() -> i64 {
    let mut now = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: a valid out-pointer to a clock every unix has.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut now) };
    now.tv_sec as i64 * 1_000_000 + now.tv_nsec as i64 / 1_000
}
