//! AudioToolbox over the container's bytes — the engine's Apple
//! `qa_os_open`. ExtAudioFile fronts the OS codec (AAC, ALAC, ...) and
//! converts to the client format asked for: float PCM, interleaved, at the
//! file's own rate and channels — the conform contract.
//!
//! 🚨AudioToolbox reads through callbacks, so the container is read where
//! it lies, plain or framed — the span reader's, as every decoder's here
//! (`container`). That is the whole Apple half of 「decode a movie's sound
//! without holding the movie」.

use std::ffi::c_void;
use std::ptr::{self, NonNull};

use objc2_audio_toolbox::{
    AudioFileClose, AudioFileID, AudioFileOpenWithCallbacks, AudioFilePacketTableInfo, ExtAudioFileDispose,
    ExtAudioFileGetProperty, ExtAudioFileRead, ExtAudioFileRef, ExtAudioFileSetProperty,
    ExtAudioFileWrapAudioFileID, kAudioFileEndOfFileError, kExtAudioFileProperty_ClientDataFormat,
    kExtAudioFileProperty_FileDataFormat, kExtAudioFileProperty_PacketTable,
};
use objc2_core_audio_types::{
    AudioBuffer, AudioBufferList, AudioStreamBasicDescription, kAudioFormatFlagIsFloat, kAudioFormatFlagIsPacked,
    kAudioFormatLinearPCM,
};

use crate::FORMAT_OS;
use crate::container::Container;
use crate::start::{Start, head_is_a_movie_box, is_adts};
use crate::stream::{Decode, Opened};

/// Frames AudioToolbox is asked for at a time — the C's.
const BLOCK_FRAMES: usize = 16_384;

/// OSStatus's 「no error」.
const NO_ERR: i32 = 0;

struct AudioToolbox {
    file: AudioFileID,
    ext: ExtAudioFileRef,
    channels: usize,
    /// What the callbacks read, at an address of its own for as long as the
    /// file is open: it goes after both are disposed (`drop`).
    container: Box<Container>,
}

impl Drop for AudioToolbox {
    fn drop(&mut self) {
        // SAFETY: what open made, each disposed once — the ExtAudioFile
        // before the file it wraps, which it does not close.
        unsafe {
            if !self.ext.is_null() {
                ExtAudioFileDispose(self.ext);
            }
            if !self.file.is_null() {
                AudioFileClose(self.file);
            }
        }
    }
}

/// AudioToolbox's read: `request` bytes from `position` of the container
/// into `buffer`, how many in `actual` — short at the end, none past it.
unsafe extern "C-unwind" fn read(
    user: NonNull<c_void>,
    position: i64,
    request: u32,
    buffer: NonNull<c_void>,
    actual: NonNull<u32>,
) -> i32 {
    // SAFETY: `user` is the container open boxed; `buffer` holds `request`
    // bytes and `actual` one count, AudioToolbox's.
    unsafe {
        let container = user.cast::<Container>().as_ref();
        let size = container.size();
        if position < 0 || position >= size {
            actual.write(0);
            return if position > size { kAudioFileEndOfFileError } else { NO_ERR };
        }
        let out = std::slice::from_raw_parts_mut(buffer.cast::<u8>().as_ptr(), request as usize);
        actual.write(container.read_at(position, out) as u32);
    }
    NO_ERR
}

unsafe extern "C-unwind" fn size(user: NonNull<c_void>) -> i64 {
    // SAFETY: `user` is the container open boxed.
    unsafe { user.cast::<Container>().as_ref() }.size()
}

/// Whether `container_start` reads where the container's sound starts — a
/// movie's, or a bare ADTS stream's. Any other container's start is its
/// decoder's to say.
fn start_is_read_here(container: &Container) -> bool {
    head_is_a_movie_box(&container.head()) || is_adts(container)
}

/// An ExtAudioFile property of `ext` into `value`, or None.
///
/// # Safety
/// `T` is the property's own type.
unsafe fn property<T>(ext: ExtAudioFileRef, id: u32, value: &mut T) -> Option<()> {
    let mut size = size_of::<T>() as u32;
    // SAFETY: the caller's contract; `size` says what `value` holds.
    let status = unsafe { ExtAudioFileGetProperty(ext, id, NonNull::from(&mut size), NonNull::from(value).cast()) };
    (status == NO_ERR).then_some(())
}

/// `value` as `ext`'s property `id`, or None where it would not take it.
///
/// # Safety
/// `T` is the property's own type.
unsafe fn set_property<T>(ext: ExtAudioFileRef, id: u32, value: &T) -> Option<()> {
    // SAFETY: the caller's contract; the size is `value`'s.
    let status = unsafe { ExtAudioFileSetProperty(ext, id, size_of::<T>() as u32, NonNull::from(value).cast()) };
    (status == NO_ERR).then_some(())
}

/// The container read by AudioToolbox, or None when it does not read it.
pub(super) fn open(container: &Container) -> Option<Opened> {
    let container = Box::new(container.clone());
    let user = NonNull::from(&*container).cast::<c_void>();
    let mut decoder = AudioToolbox { file: ptr::null_mut(), ext: ptr::null_mut(), channels: 0, container };
    // SAFETY: the callbacks read what `user` points at, which the decoder
    // keeps until both are disposed; the out pointers are its fields.
    unsafe {
        if AudioFileOpenWithCallbacks(user, Some(read), None, Some(size), None, 0, NonNull::from(&mut decoder.file))
            != NO_ERR
        {
            return None;
        }
        if ExtAudioFileWrapAudioFileID(decoder.file, false, NonNull::from(&mut decoder.ext)) != NO_ERR {
            return None;
        }
    }
    let ext = decoder.ext;

    // 🚨AudioToolbox trims a file's priming off ITSELF, by a packet table it
    // keeps — for a movie that says nothing, Apple's own assumption, 2,112
    // (the macOS CI runner, 2026-10-15: the m4a without its edit list began
    // on its sine's 1,088th frame, and the movie Media Foundation wrote, 22
    // packets, came back 22 × 1,024 − 2,112 with its mark or without). This
    // app's law there is its format's standard, or nothing (Q6 · Q7), so where
    // this crate reads the start the trimming is turned off at both ends — 0
    // overrides what the file stores (ExtendedAudioFile.h) — before the client
    // format, so the decoder is made with it (user 2026-10-09, Q4: 「OS 가
    // 스스로 걷는 플랫폼에서는 그 걷기를 끄거나, 끌 수 없으면 걷은 만큼을 알아내
    // 맞춘다」). The C took no answer from it either: what it would not take
    // is counted below.
    if start_is_read_here(&decoder.container) {
        let none = AudioFilePacketTableInfo { mNumberValidFrames: 0, mPrimingFrames: 0, mRemainderFrames: 0 };
        // SAFETY: the packet table's own type.
        let _ = unsafe { set_property(ext, kExtAudioFileProperty_PacketTable, &none) };
    }

    // SAFETY: a plain C struct, all of whose fields take zero.
    let mut source: AudioStreamBasicDescription = unsafe { std::mem::zeroed() };
    // SAFETY: the file format's own type.
    unsafe { property(ext, kExtAudioFileProperty_FileDataFormat, &mut source) }?;
    if source.mChannelsPerFrame == 0 || source.mSampleRate <= 0.0 {
        return None;
    }
    let bytes = 4 * source.mChannelsPerFrame;
    let client = AudioStreamBasicDescription {
        mSampleRate: source.mSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: bytes,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytes,
        mChannelsPerFrame: source.mChannelsPerFrame,
        mBitsPerChannel: 32,
        mReserved: 0,
    };
    // SAFETY: the client format's own type.
    unsafe { set_property(ext, kExtAudioFileProperty_ClientDataFormat, &client) }?;

    // What it still trims — a container whose start is its decoder's to say
    // (a CAF's own packet table), or an override it would not take — it says,
    // the value it reads with, and only the rest is counted.
    let mut table = AudioFilePacketTableInfo { mNumberValidFrames: 0, mPrimingFrames: 0, mRemainderFrames: 0 };
    // SAFETY: the packet table's own type.
    let said = unsafe { property(ext, kExtAudioFileProperty_PacketTable, &mut table) }.is_some();
    let taken = if said && table.mPrimingFrames > 0 { i64::from(table.mPrimingFrames) } else { 0 };

    decoder.channels = client.mChannelsPerFrame as usize;
    Some(Opened {
        decoder: Box::new(decoder),
        format: FORMAT_OS,
        channels: client.mChannelsPerFrame as i32,
        sample_rate: source.mSampleRate as i32,
        start: Start { taken, ..Start::default() },
    })
}

impl Decode for AudioToolbox {
    /// ⚠️A read AudioToolbox refuses is the end — as every decoder behind a
    /// stream says it; the C failed the whole decode there.
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        block.resize(BLOCK_FRAMES * self.channels, 0.0);
        let mut list = AudioBufferList {
            mNumberBuffers: 1,
            mBuffers: [AudioBuffer {
                mNumberChannels: self.channels as u32,
                mDataByteSize: size_of_val(block.as_slice()) as u32,
                mData: block.as_mut_ptr().cast(),
            }],
        };
        let mut frames = BLOCK_FRAMES as u32;
        // SAFETY: the one buffer is `block`, `frames` frames of the client
        // format long; both counts are locals.
        if unsafe { ExtAudioFileRead(self.ext, NonNull::from(&mut frames), NonNull::from(&mut list)) } != NO_ERR {
            return 0;
        }
        let frames = (frames as usize).min(BLOCK_FRAMES);
        block.truncate(frames * self.channels);
        frames
    }
}
