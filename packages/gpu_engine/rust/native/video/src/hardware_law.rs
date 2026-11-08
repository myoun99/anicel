//! THE HARDWARE LAW — whether a Windows video job may hand its frames to a
//! hardware encoder, or stays with the OS's own software H.264.
//!
//! 🔬Measured 2026-10-08 on a Surface Pro 11 (Intel Core Ultra 7 268V, its
//! Arc 140V encoder), card surface-engine-mp4-pieces-fail-to-finalize: the
//! hardware H.264 transform ACCEPTS every media type the sink writer offers
//! it, then fails a job whose frame has a side of 48 px or less — three
//! 16-px macroblocks — with E_FAIL at Finalize (79 bytes on disk, the header
//! alone), or at the very first frame when the other side is long
//! (1920×48). 50 px and up encode, 1920×1080 included. The software H.264
//! transform encodes every one of those sizes; what it cannot take (32 px
//! and less) it turns away at SetInputMediaType, before a frame is spent.
//! Every engine test that cuts or writes a 64×48 movie was red on that
//! machine for this alone.
//!
//! ⚠️What this does NOT know: other vendors' hardware minimums (nobody has
//! measured one). A transform that refuses a size at SetInputMediaType costs
//! nothing — the writer falls back to software by itself; the ones this law
//! is for are the ones that say yes and fail late.
//!
//! ⛔Not a speed rule. The same machine encoded 240 frames faster in
//! software at every size up to 1920×1080 (1.1 s against 5.2 s at 64×64,
//! 3.6 s against 7.6 s at 1920×1080), but which transform a large export
//! takes is the export's question, measured on the user's own film — this
//! law only keeps the small jobs from a transform that cannot do them.
//!
//! No platform in it: the Windows writer asks it, and its tests run on every
//! host.

/// The longest side that still failed on the hardware transform above.
pub const FAILED_SIDE: i32 = 48;

/// Whether a job of `width`×`height` — the size the encoder is handed, after
/// the even pad — may ask for hardware transforms. HEVC always may: Windows
/// ships no software HEVC encoder, so without hardware there is no HEVC job.
pub fn may_encode(width: i32, height: i32, hevc: bool) -> bool {
    hevc || (width > FAILED_SIDE && height > FAILED_SIDE)
}

// The C's own cases (↩️qa_video_hardware_law_test.c, until the connection
// round deleted it). What the law keeps out of the hardware fails only on a
// machine whose encoder says yes and then gives up, so without these nothing
// off that machine would notice it gone.
#[cfg(test)]
#[test]
fn the_small_jobs_stay_in_software() {
    for (what, width, height, hevc, want) in [
        // The sizes the engine's own fixtures write, and what failed on them.
        ("the fixtures' movie", 64, 48, false, false),
        ("tall instead of wide", 48, 64, false, false),
        ("a long thin strip", 1920, 48, false, false),
        ("a thin strip the other way", 48, 1920, false, false),
        // The first sizes that encoded on that machine, and everyday ones.
        ("one pixel past three macroblocks", 50, 50, false, true),
        ("one past the failed side", 49, 49, false, true),
        ("past it on both sides", 64, 64, false, true),
        ("a full HD film", 1920, 1080, false, true),
        // HEVC has no software encoder on Windows — refusing it the hardware
        // would refuse it everything.
        ("HEVC stays on the hardware", 64, 48, true, true),
        ("HEVC at full HD", 1920, 1080, true, true),
    ] {
        assert_eq!(may_encode(width, height, hevc), want, "{what}: {width}x{height}");
    }
}
