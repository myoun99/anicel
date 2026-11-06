//! The still-image encoder (EX4): baseline JPEG, memory to memory — the
//! engine's `qa_image_encode.c` over stb_image_write, in Rust
//! (native-to-rust, 저장). Until the connection round the C is the answer
//! key: the tests hold every byte to the engine's `qa_image_encode_jpg`.
//!
//! Why native: Flutter's engine encodes PNG only, and the pub 'image'
//! package would drag a large pure-Dart dependency for one codec. stb's
//! writer is byte-deterministic, so the encoder can be pinned by hash like
//! the rest of the engine — and so it is ported line for line, not
//! swapped for another encoder whose bytes would differ.
//!
//! The contract with Dart (`lib/src/native/qa_image_encoder.dart`) is the
//! C's, unchanged:
//!   - input is TOP-DOWN RGB24 (the caller flattens RGBA over the chosen
//!     background — JPG carries no alpha, and the flatten is three lines
//!     of Dart against a background color the spec owns);
//!   - output is a buffer handed to Dart, released with
//!     `qa_image_encode_free` (never with Dart's allocator).

mod jpeg;
#[cfg(test)]
mod tests;

use std::alloc::{Layout, alloc, dealloc};
use std::ptr::null_mut;

pub use jpeg::encode;

/// What a handed-out buffer carries before its bytes: their count, which
/// `qa_image_encode_free` needs to give the block back.
const HEAD: usize = size_of::<usize>();

fn layout(len: usize) -> Option<Layout> {
    Layout::from_size_align(HEAD.checked_add(len)?, align_of::<usize>()).ok()
}

/// `bytes` in a block of their own for Dart to hold; null if there is no
/// room.
fn hand_out(bytes: &[u8]) -> *mut u8 {
    let Some(layout) = layout(bytes.len()) else {
        return null_mut();
    };
    // SAFETY: the layout is not empty (HEAD > 0); the block is written
    // within it — the count at its start, the bytes after.
    unsafe {
        let block = alloc(layout);
        if block.is_null() {
            return block;
        }
        block.cast::<usize>().write(bytes.len());
        let data = block.add(HEAD);
        data.copy_from_nonoverlapping(bytes.as_ptr(), bytes.len());
        data
    }
}

/// Encodes top-down RGB24 into a baseline JPEG. `quality` clamps to
/// 1..=100. On success `*out_data` · `*out_size` carry the file's bytes
/// (the caller frees them with [`qa_image_encode_free`]) and 1 returns;
/// otherwise 0, with nothing handed out.
///
/// # Safety
/// `rgb` points at `width` x `height` x 3 bytes; `out_data` and
/// `out_size` are writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_encode_jpg(
    rgb: *const u8,
    width: i32,
    height: i32,
    quality: i32,
    out_data: *mut *mut u8,
    out_size: *mut i32,
) -> i32 {
    if rgb.is_null() || out_data.is_null() || out_size.is_null() || width <= 0 || height <= 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    unsafe {
        *out_data = null_mut();
        *out_size = 0;
    }
    let (width, height) = (width as usize, height as usize);
    // SAFETY: the caller's contract.
    let rgb = unsafe { std::slice::from_raw_parts(rgb, width * height * 3) };
    let bytes = encode(rgb, width, height, quality);
    let Ok(size) = i32::try_from(bytes.len()) else {
        return 0;
    };
    let data = hand_out(&bytes);
    if data.is_null() {
        return 0;
    }
    // SAFETY: the caller's contract.
    unsafe {
        *out_data = data;
        *out_size = size;
    }
    1
}

/// Gives back what [`qa_image_encode_jpg`] handed out; null is nothing.
///
/// # Safety
/// `data` is null or a buffer [`qa_image_encode_jpg`] handed out, not yet
/// given back.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_encode_free(data: *mut u8) {
    if data.is_null() {
        return;
    }
    // SAFETY: the caller's contract — the block starts HEAD before `data`
    // and holds its count there.
    unsafe {
        let block = data.sub(HEAD);
        let len = block.cast::<usize>().read();
        dealloc(block, layout(len).expect("the layout it was made with"));
    }
}
