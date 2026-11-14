//! The NDK's media objects, each let go of once on every way out: an
//! extractor, a format, a codec — through `ndk-sys` (`served_span.rs` says
//! why never a table by hand). One holding for the decoders that read
//! through MediaCodec (저장 2026-11-07): the sound's held these three in a
//! file of its own, and the movie's would have been a second.

use ndk_sys::{
    AMediaCodec, AMediaCodec_delete, AMediaCodec_stop, AMediaExtractor, AMediaExtractor_delete, AMediaFormat,
    AMediaFormat_delete, media_status_t,
};

/// `Some` where the NDK said OK — for `?` on every way out.
pub fn ok(status: media_status_t) -> Option<()> {
    (status == media_status_t::AMEDIA_OK).then_some(())
}

/// An extractor, deleted as it drops. Null is held as null: a caller asks
/// `.0.is_null()` straight after `AMediaExtractor_new`.
pub struct Extractor(pub *mut AMediaExtractor);

impl Drop for Extractor {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: the extractor handed to this, deleted once.
            unsafe { AMediaExtractor_delete(self.0) };
        }
    }
}

/// A format handed over by the NDK, or null, deleted as it drops.
pub struct Format(pub *mut AMediaFormat);

impl Drop for Format {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: a format handed over to this, deleted once.
            unsafe { AMediaFormat_delete(self.0) };
        }
    }
}

/// A codec, stopped if it started and deleted as it drops.
pub struct Codec {
    pub codec: *mut AMediaCodec,
    pub started: bool,
}

impl Drop for Codec {
    fn drop(&mut self) {
        if self.codec.is_null() {
            return;
        }
        // SAFETY: the codec handed to this, stopped if it started, deleted
        // once.
        unsafe {
            if self.started {
                AMediaCodec_stop(self.codec);
            }
            AMediaCodec_delete(self.codec);
        }
    }
}
