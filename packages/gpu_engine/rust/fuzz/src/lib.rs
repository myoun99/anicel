//! The Rust decoders, fed what no test thought of (native-memory-safety ③,
//! native-to-rust-Q2): one function here per fuzz target (fuzz_targets/),
//! each the door the app's bytes come in by. A target that panics, hangs or
//! runs out of memory on an input has found a bug in the crate it reads;
//! that input becomes a `cargo test` case there, held to the C.

use std::ffi::CString;

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

/// What a frame is decoded into when it states no size, or more: the crates
/// that read zstd themselves size their own buffers.
const ROOM: usize = 1 << 20;

/// Any bytes, as the app reads a cel (qa_cel_compressor.dart's
/// `readFrame`): the size the frame states, then the frame into that many
/// bytes — and, where the app gives up on a frame that states none, into
/// `ROOM`.
pub fn compress_decompress(frame: &[u8]) {
    let length = frame.len() as i64;
    // SAFETY: the slice holds the length passed.
    let stated = unsafe { compress::qa_zstd_decompressed_size(frame.as_ptr(), length) };
    let room = usize::try_from(stated).ok().filter(|size| (1..=ROOM).contains(size));
    let room = room.unwrap_or(ROOM);
    let mut out = vec![0u8; room];
    // SAFETY: both buffers hold the lengths passed, and are apart.
    unsafe { compress::qa_zstd_decompress(out.as_mut_ptr(), room as i64, frame.as_ptr(), length) };
}

/// Frames the app reads a sound by as it conforms it (conform_making.dart's
/// `conformWindowFrames`).
const CONFORM_WINDOW: i64 = 1 << 18;

/// Any bytes, as the app takes a sound in (audio_conform_runner.dart's
/// `openAudioSource`): a whole file opened as a stream, read
/// `CONFORM_WINDOW` frames at a time into room for that many until a read
/// brings none, then closed. A sound comes in by a path, so the bytes are
/// a file first. The room is the app's own, so a sound that names more
/// channels than memory holds is found here as the app would meet it.
///
/// A sound carried framed in a project reads its blocks through the span
/// reader (`media::span`), which is a door of its own.
pub fn audio_stream(container: &[u8]) {
    // The app hands over no empty span (qa_audio_decoder.dart's `openSpan`).
    if container.is_empty() {
        return;
    }
    let file = std::env::temp_dir().join(format!("decoder_fuzz_audio_{}", std::process::id()));
    std::fs::write(&file, container).expect("the bytes written to a file");
    let path = CString::new(file.to_str().expect("a UTF-8 path")).expect("no NUL in a temp path");
    let (mut format, mut channels, mut rate) = (0, 0, 0);
    let length = container.len() as i64;
    // SAFETY: a NUL-terminated path, and out pointers to locals.
    let stream =
        unsafe { audio::qa_audio_stream_open(path.as_ptr(), 0, length, 0, &mut format, &mut channels, &mut rate) };
    if stream.is_null() {
        return;
    }
    // The app reads nothing of a stream that says no channels
    // (qa_audio_decoder.dart's `read`), and stops at a read that fails.
    if channels > 0 {
        let mut room = vec![0f32; CONFORM_WINDOW as usize * channels as usize];
        // SAFETY: an open stream, and room for the frames asked for.
        while unsafe { audio::qa_audio_stream_read(stream, room.as_mut_ptr(), CONFORM_WINDOW) } > 0 {}
    }
    // SAFETY: opened above, closed once.
    unsafe { audio::qa_audio_stream_close(stream) };
}
