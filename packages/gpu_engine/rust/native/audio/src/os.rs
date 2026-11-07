//! The OS's own codec stack — the last stage, for what no bundled decoder
//! reads (native-to-rust-Q6, the user's answer 2026-11-06: 「symphonia 먼저,
//! 못 읽는 것만 지금처럼 OS 로」): HE-AAC, AAC whose core runs at 24 kHz or
//! less (`bundled::core_may_hide_sbr`), AAC of more than two channels, and
//! what only the OS reads — Windows' WMA, MPEG frames behind a RIFX. A
//! sound read here can come out a little differently on each device; one a
//! bundled decoder reads cannot.
//!
//! 🚨★**A STAGE AT THE END, AND NOTHING MORE** (the user's note on that
//! answer: 「읽는길은 하나인게 좋은거지? … 하나로 합칠수있게」 — board
//! audio-one-reading-path). Nothing before it knows it is there, so once
//! our own decoders read what it reads, deleting it leaves one way of
//! reading a sound.
//!
//! Media Foundation on Windows ([media_foundation]). ⚠️AudioToolbox and the
//! NDK's MediaCodec are still the C's (`qa_audio_decode.c`) and come next:
//! until then this stage reads nothing on those platforms.

#[cfg(windows)]
mod media_foundation;

use crate::container::Container;
use crate::stream::Opened;

/// The container opened by the OS's codec stack, or None when it does not
/// read it — or this platform's stage is not here yet.
pub(crate) fn open(container: &Container) -> Option<Opened> {
    #[cfg(windows)]
    {
        media_foundation::open(container)
    }
    #[cfg(not(windows))]
    {
        let _ = container;
        None
    }
}
