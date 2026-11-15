//! The still-image decoder: a JPEG's pixels, decoded where an import lays
//! them — on the worker that cuts them into a cel's tiles
//! (`lib/src/services/import/cel_picture.dart`, `readFileRows`), so the
//! isolate that paints holds none of them.
//!
//! 🗣️유저 2026-11-15 (a-raster-import-goes-gpu-cpu-gpu-cpu-Q2): 「빠른 JPEG
//! 디코더를 들인다」 — and the download of zune-jpeg and zune-core allowed
//! in chat (Q3). 🔬Surface, the same 4000×3000 JPEG on a worker: the image
//! package read it in 0.80–0.83 s, the engine's codec in 0.13–0.15 s. Q1's
//! answer (「프로파일대로 바꿔 읽는다(크기 상관없이)」) put every still JPEG
//! on the app's own decoder, and its colours are turned to sRGB after, as
//! the file says (`colour_profile.dart`) — this crate hands them as coded.
//!
//! The contract with Dart (`lib/src/native/qa_image_decoder.dart`): a
//! file opened ([`qa_image_decode_jpg_open`]) is a handle that holds the
//! picture, or why it did not decode — its own, so workers that open at
//! once never read each other's — its rows asked one at a time as they
//! show ([`qa_image_decode_jpg_row`]), and closed.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod jpeg;
#[cfg(test)]
mod tests;

pub use jpeg::Decoded;

/// An opened file: its picture, or why it has none.
pub struct Opened(Result<Decoded, String>);

/// The JPEG `bytes` (`length` of them) decoded, as a handle the caller
/// closes ([`qa_image_decode_jpg_close`]) whether it decoded or not; null
/// only where there is nothing to read.
///
/// # Safety
/// `bytes` is null or holds `length` bytes, for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_decode_jpg_open(bytes: *const u8, length: usize) -> *mut Opened {
    if bytes.is_null() || length == 0 {
        return std::ptr::null_mut();
    }
    // SAFETY: the caller's contract.
    let bytes = unsafe { std::slice::from_raw_parts(bytes, length) };
    Box::into_raw(Box::new(Opened(Decoded::of(bytes))))
}

/// 1, and the picture's width and height as it shows into `size`; 0 where
/// it did not decode ([`qa_image_decode_jpg_error`] says why).
///
/// # Safety
/// `opened` is one [`qa_image_decode_jpg_open`] handed out and not yet
/// closed; `size` holds two.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_decode_jpg_size(opened: *const Opened, size: *mut i32) -> i32 {
    // SAFETY: the caller's contract.
    let Some(Ok(decoded)) = (unsafe { opened.as_ref() }).map(|opened| &opened.0) else {
        return 0;
    };
    let (width, height) = decoded.shown();
    // SAFETY: the caller's contract.
    unsafe {
        *size = width as i32;
        *size.add(1) = height as i32;
    }
    1
}

/// Row `y` of the picture as it shows into `rgba` — its width × 4 bytes,
/// straight RGBA8, opaque: 1, or 0 where there is no such row.
///
/// # Safety
/// `opened` as [`qa_image_decode_jpg_size`] takes it; `rgba` holds a row.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_decode_jpg_row(opened: *const Opened, y: i32, rgba: *mut u8) -> i32 {
    // SAFETY: the caller's contract.
    let Some(Ok(decoded)) = (unsafe { opened.as_ref() }).map(|opened| &opened.0) else {
        return 0;
    };
    let (Ok(y), false) = (usize::try_from(y), rgba.is_null()) else {
        return 0;
    };
    // SAFETY: the caller's contract — a row of the width it shows.
    let row = unsafe { std::slice::from_raw_parts_mut(rgba, decoded.shown().0 * 4) };
    i32::from(decoded.row(y, row))
}

/// Why the file did not decode, cut to the `room` given — a byte short of
/// it, for the NUL: its length, or -1 where it did decode or there is no
/// room.
///
/// # Safety
/// `opened` as [`qa_image_decode_jpg_size`] takes it; `text` holds `room`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_decode_jpg_error(opened: *const Opened, text: *mut u8, room: i32) -> i32 {
    // SAFETY: the caller's contract.
    let Some(Err(why)) = (unsafe { opened.as_ref() }).map(|opened| &opened.0) else {
        return -1;
    };
    let Ok(room) = usize::try_from(room) else {
        return -1;
    };
    if text.is_null() || room == 0 {
        return -1;
    }
    let length = why.floor_char_boundary(room - 1);
    // SAFETY: `length` < `room`, which `text` holds.
    unsafe {
        text.copy_from_nonoverlapping(why.as_ptr(), length);
        *text.add(length) = 0;
    }
    length as i32
}

/// The handle let go, and the picture with it.
///
/// # Safety
/// `opened` is null or one [`qa_image_decode_jpg_open`] handed out, not
/// closed before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_image_decode_jpg_close(opened: *mut Opened) {
    if !opened.is_null() {
        // SAFETY: the caller's contract.
        drop(unsafe { Box::from_raw(opened) });
    }
}
