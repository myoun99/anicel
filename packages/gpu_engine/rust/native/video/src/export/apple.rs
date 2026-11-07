//! Apple: AVAssetWriter — `qa_video_apple.m`'s export half, through objc2.
//! The writer IS the OS's MP4/MOV writer on macOS and iOS: hardware H.264
//! and H.265 through VideoToolbox, ProRes where the machine has it, AAC
//! through AudioToolbox, muxing included. Our pixel job is RGBA → NV12 in
//! the app's colour law for H.26x, RGBA → BGRA for ProRes, plus the
//! even-size pad.

use std::ffi::c_void;
use std::ptr::{self, NonNull};
use std::sync::{Mutex, mpsc};
use std::time::Duration;

use block2::RcBlock;
use objc2::{AllocAnyThread, Message};
use objc2::rc::{Retained, autoreleasepool};
use objc2::runtime::AnyObject;
use objc2_av_foundation::{
    AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor, AVAssetWriterStatus,
    AVFileTypeMPEG4, AVFileTypeQuickTimeMovie, AVMediaTypeAudio, AVMediaTypeVideo,
    AVVideoAverageBitRateKey, AVVideoCodecKey, AVVideoCodecTypeH264, AVVideoColorPrimariesKey,
    AVVideoColorPrimaries_SMPTE_C, AVVideoColorPropertiesKey, AVVideoCompressionPropertiesKey,
    AVVideoHeightKey, AVVideoTransferFunctionKey, AVVideoTransferFunction_ITU_R_709_2,
    AVVideoWidthKey, AVVideoYCbCrMatrixKey, AVVideoYCbCrMatrix_ITU_R_601_4,
};
use objc2_avf_audio::{
    AVEncoderBitRateKey, AVFormatIDKey, AVLinearPCMBitDepthKey, AVLinearPCMIsBigEndianKey,
    AVLinearPCMIsFloatKey, AVLinearPCMIsNonInterleaved, AVNumberOfChannelsKey, AVSampleRateKey,
};
use objc2_core_audio_types::{
    AudioStreamBasicDescription, kAudioFormatFlagIsPacked, kAudioFormatFlagIsSignedInteger,
    kAudioFormatLinearPCM, kAudioFormatMPEG4AAC,
};
use objc2_core_foundation::{CFRetained, CFString};
use objc2_core_media::{
    CMAudioFormatDescription, CMAudioFormatDescriptionCreate,
    CMAudioSampleBufferCreateWithPacketDescriptions, CMBlockBuffer, CMSampleBuffer, CMTime,
    kCMTimeZero,
};
use objc2_core_video::{
    CVAttachmentMode, CVPixelBuffer, CVPixelBufferGetBaseAddress, CVPixelBufferGetBaseAddressOfPlane,
    CVPixelBufferGetBytesPerRow, CVPixelBufferGetBytesPerRowOfPlane, CVPixelBufferGetHeight,
    CVPixelBufferGetHeightOfPlane, CVPixelBufferGetPlaneCount, CVPixelBufferIsPlanar,
    CVPixelBufferLockBaseAddress, CVPixelBufferLockFlags, CVPixelBufferPool,
    CVPixelBufferUnlockBaseAddress, kCVImageBufferColorPrimariesKey,
    kCVImageBufferColorPrimaries_SMPTE_C, kCVImageBufferTransferFunctionKey,
    kCVImageBufferTransferFunction_ITU_R_709_2, kCVImageBufferYCbCrMatrixKey,
    kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVPixelBufferHeightKey, kCVPixelBufferPixelFormatTypeKey,
    kCVPixelBufferWidthKey, kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    kCVReturnSuccess,
};
use objc2_foundation::{NSDictionary, NSFileManager, NSNumber, NSString, NSURL};

use super::{
    BAD_OPEN, CODEC_H264, CODEC_HEVC, CODEC_PRORES_4444, CODEC_PRORES_422, CODEC_PRORES_HQ,
    CODEC_PRORES_LT, CODEC_PRORES_PROXY, CONTAINER_MOV, CONTAINER_MP4, Job, lock, set_error,
};
use crate::colour::{self, Picture, Planes};

pub const SUPPORTED: bool = true;

/// How long a write waits for its input, in 1 ms naps: an offline render
/// waits for the encoder to drain, and gives the frame up after 10 s.
const SPINS: u32 = 10_000;

struct Writer {
    writer: Retained<AVAssetWriter>,
    video: Retained<AVAssetWriterInput>,
    adaptor: Retained<AVAssetWriterInputPixelBufferAdaptor>,
    /// The sound track and the PCM it is handed, for a job with channels.
    audio: Option<(Retained<AVAssetWriterInput>, CFRetained<CMAudioFormatDescription>)>,
    src_width: usize,
    src_height: usize,
    /// Padded even.
    width: usize,
    height: usize,
    fps_num: i64,
    fps_den: i64,
    frame_index: i64,
    audio_samples: i64,
    sample_rate: i32,
    channels: usize,
    /// ProRes 4444 asked to keep the picture's alpha.
    keep_alpha: bool,
    /// Frames go to the encoder as NV12 made here (`colour`) rather than
    /// BGRA for VideoToolbox to convert — every codec but ProRes.
    ycbcr: bool,
}

// SAFETY: the one export is called from whichever thread Dart is on, one
// call at a time under the lock — as the C's process globals were — and
// AVAssetWriter takes its calls from any thread.
unsafe impl Send for Writer {}

static WRITER: Mutex<Option<Writer>> = Mutex::new(None);

/// The v10 pair matrix on Apple: H.264 in both containers, H.265 in MP4,
/// ProRes in MOV. Legality alone — device support (an iPad without the
/// ProRes engine) answers at open, where the writer can refuse.
pub fn probe(container: i32, codec: i32) -> bool {
    match codec {
        CODEC_H264 => true,
        CODEC_HEVC => container == CONTAINER_MP4,
        CODEC_PRORES_PROXY | CODEC_PRORES_LT | CODEC_PRORES_422 | CODEC_PRORES_HQ
        | CODEC_PRORES_4444 => container == CONTAINER_MOV,
        _ => false,
    }
}

fn is_prores(codec: i32) -> bool {
    codec >= CODEC_PRORES_PROXY
}

/// A key or value AVFoundation names: there on every OS this builds for —
/// a missing one would have raised in the C's dictionary literals too.
fn named(name: Option<&'static NSString>) -> &'static NSString {
    name.expect("an AVFoundation name")
}

/// A CoreVideo key as the dictionary's NSString.
fn bridged(key: &CFString) -> &NSString {
    // SAFETY: CFString and NSString are toll-free bridged.
    unsafe { &*(key as *const CFString).cast::<NSString>() }
}

fn dictionary(entries: &[(&NSString, &AnyObject)]) -> Retained<NSDictionary<NSString, AnyObject>> {
    let (keys, values): (Vec<&NSString>, Vec<&AnyObject>) = entries.iter().copied().unzip();
    NSDictionary::from_slices(&keys, &values)
}

/// The AVFoundation codec identifiers ARE these fourcc strings; literals
/// dodge SDK-availability guards on the newer named constants (ProRes
/// Proxy/LT gained names only in macOS 12 / iOS 15 SDKs).
fn codec_id(codec: i32) -> Retained<NSString> {
    let fourcc = match codec {
        CODEC_HEVC => "hvc1",
        CODEC_PRORES_PROXY => "apco",
        CODEC_PRORES_LT => "apcs",
        CODEC_PRORES_422 => "apcn",
        CODEC_PRORES_HQ => "apch",
        CODEC_PRORES_4444 => "ap4h",
        // SAFETY: reading the framework's constant.
        _ => return named(unsafe { AVVideoCodecTypeH264 }).retain(),
    };
    NSString::from_str(fourcc)
}

/// The video track's settings: the codec at the padded size, the job's
/// bitrate for H.26x when it names one, and the colour the H.26x pictures
/// are written in.
///
/// ⚠️The bitrate goes in as Dart passed it, without the floor and ceiling
/// the Windows and Android writers clamp to (`super::bitrate`) — the C's
/// Apple writer never clamped, and none is in the lineup's tests to say
/// otherwise; 0 leaves the rate to VideoToolbox.
fn video_settings(job: &Job, width: usize, height: usize) -> Retained<NSDictionary<NSString, AnyObject>> {
    // SAFETY: reading the framework's constant names.
    let (codec_key, width_key, height_key, compression_key, bitrate_key) = unsafe {
        (
            named(AVVideoCodecKey),
            named(AVVideoWidthKey),
            named(AVVideoHeightKey),
            named(AVVideoCompressionPropertiesKey),
            named(AVVideoAverageBitRateKey),
        )
    };
    let codec = codec_id(job.codec);
    let (width, height) = (NSNumber::new_i32(width as i32), NSNumber::new_i32(height as i32));
    let mut entries: Vec<(&NSString, &AnyObject)> = vec![(codec_key, &codec), (width_key, &width), (height_key, &height)];
    let bitrate = NSNumber::new_i32(job.bitrate_bps);
    let compression = dictionary(&[(bitrate_key, &bitrate)]);
    if !is_prores(job.codec) && job.bitrate_bps > 0 {
        entries.push((compression_key, &compression));
    }
    // 🚨★★★**THE H.26x PICTURES ARE MADE YCbCr HERE, IN THE APP'S COLOUR
    // LAW, AND THE FILE SAYS SO** (`colour`, BT.601 studio range — what the
    // Android writer has always written). They used to go in as BGRA for
    // VideoToolbox to convert, and what the Apple reader turned back had
    // lost red in exact proportion — 0.9136 of it, BT.709 in and BT.601
    // out: red 110 came back 101, and a piece cut from a take 168 where the
    // take showed 185 (2026-09-24, board `trimmed-piece-apple-parity`).
    // Naming BT.601 in these properties alone moved none of those numbers,
    // so the pictures are converted before the encoder sees them, and these
    // properties now describe what was really written. ⚠️ProRes stays BGRA:
    // 4444 carries alpha, and its conversion is still VideoToolbox's to
    // choose.
    // SAFETY: reading the framework's constant names.
    let colour = unsafe {
        dictionary(&[
            (named(AVVideoColorPrimariesKey), named(AVVideoColorPrimaries_SMPTE_C)),
            (named(AVVideoTransferFunctionKey), named(AVVideoTransferFunction_ITU_R_709_2)),
            (named(AVVideoYCbCrMatrixKey), named(AVVideoYCbCrMatrix_ITU_R_601_4)),
        ])
    };
    if !is_prores(job.codec) {
        // SAFETY: as above.
        entries.push((named(unsafe { AVVideoColorPropertiesKey }), &colour));
    }
    dictionary(&entries)
}

/// The sound track's settings: ProRes deliveries carry PCM (the master
/// convention); the H.26x containers keep AAC.
fn audio_settings(job: &Job) -> Retained<NSDictionary<NSString, AnyObject>> {
    let rate = NSNumber::new_i32(job.sample_rate);
    let channels = NSNumber::new_i32(job.channels);
    // SAFETY: reading the framework's constant names.
    unsafe {
        if is_prores(job.codec) {
            let (format, depth, no) = (NSNumber::new_u32(kAudioFormatLinearPCM), NSNumber::new_i32(16), NSNumber::new_bool(false));
            dictionary(&[
                (named(AVFormatIDKey), &format),
                (named(AVSampleRateKey), &rate),
                (named(AVNumberOfChannelsKey), &channels),
                (named(AVLinearPCMBitDepthKey), &depth),
                (named(AVLinearPCMIsFloatKey), &no),
                (named(AVLinearPCMIsBigEndianKey), &no),
                (named(AVLinearPCMIsNonInterleaved), &no),
            ])
        } else {
            let (format, bitrate) = (NSNumber::new_u32(kAudioFormatMPEG4AAC), NSNumber::new_i32(192_000));
            dictionary(&[
                (named(AVFormatIDKey), &format),
                (named(AVSampleRateKey), &rate),
                (named(AVNumberOfChannelsKey), &channels),
                (named(AVEncoderBitRateKey), &bitrate),
            ])
        }
    }
}

/// The time scale the video track keeps: a multiple of the rate's
/// numerator, lifted to at least 600 — none when it would not fit.
///
/// 🚨THE TRACK KEEPS TIME IN A UNIT THAT HOLDS ONE FRAME EXACTLY. Frame i is
/// appended at exactly i * den / num seconds, but an input left at its
/// default time scale lets the writer pick its own, and in 1/600 s a
/// 24000/1001 frame is 25.025 units: it rounds to 25, every frame lasts
/// exactly 1/24 s, and the file says 24.0 fps. A trimmed 23.976 take came
/// back as 24 on the Apple engine only (2026-09-24, first run of
/// `a_trimmed_file_is_carried_as_its_piece_test` on a Mac). A multiple of
/// the rate's numerator holds every frame time exactly; it is lifted to at
/// least 600 so a 12 or 24 fps track keeps a conventional unit.
fn media_time_scale(fps_num: i64) -> Option<i32> {
    let scale = if fps_num < 600 { fps_num * ((600 + fps_num - 1) / fps_num) } else { fps_num };
    i32::try_from(scale).ok()
}

/// The PCM the mix arrives as: interleaved, signed 16-bit.
fn pcm_description(job: &Job) -> Option<CFRetained<CMAudioFormatDescription>> {
    let bytes = (job.channels * 2) as u32;
    let pcm = AudioStreamBasicDescription {
        mSampleRate: f64::from(job.sample_rate),
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: bytes,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytes,
        mChannelsPerFrame: job.channels as u32,
        mBitsPerChannel: 16,
        mReserved: 0,
    };
    let mut out: *const CMAudioFormatDescription = ptr::null();
    // SAFETY: the description is a local the call copies; `out` is a local
    // it writes once.
    let status = unsafe {
        CMAudioFormatDescriptionCreate(
            None,
            NonNull::from(&pcm),
            0,
            ptr::null(),
            0,
            ptr::null(),
            None,
            NonNull::from(&mut out),
        )
    };
    let out = NonNull::new(out.cast_mut()).filter(|_| status == 0)?;
    // SAFETY: a Create call hands over the one reference it made.
    Some(unsafe { CFRetained::from_raw(out) })
}

pub fn open(job: &Job) -> bool {
    let mut held = lock(&WRITER);
    let Some(path) = job.path.filter(|_| held.is_none() && job.well_formed()) else {
        set_error(BAD_OPEN);
        return false;
    };
    if !probe(job.container, job.codec) {
        set_error("video export: that container/codec pair is not in the lineup");
        return false;
    }
    match autoreleasepool(|_| writer(path.to_str().ok(), job)) {
        Ok(writer) => {
            *held = Some(writer);
            true
        }
        Err(message) => {
            set_error(message);
            false
        }
    }
}

/// The writer for `job`, begun, or what the C said when it could not be.
/// A path that is not UTF-8 is a file that could not be created, where the
/// C's `stringWithUTF8String` handed AVFoundation nil.
fn writer(path: Option<&str>, job: &Job) -> Result<Writer, &'static str> {
    let (width, height) = ((job.width + (job.width & 1)) as usize, (job.height + (job.height & 1)) as usize);
    let ycbcr = !is_prores(job.codec);
    let path = path.map(NSString::from_str).ok_or("video export: the output file could not be created")?;
    // Writing fails where a file already is.
    let _ = NSFileManager::defaultManager().removeItemAtPath_error(&path);
    // SAFETY: reading the framework's constants.
    let file_type = named(unsafe { if job.container == CONTAINER_MOV { AVFileTypeQuickTimeMovie } else { AVFileTypeMPEG4 } });
    // SAFETY: a file URL and a file type AVMediaFormat.h declares.
    let writer = unsafe { AVAssetWriter::initWithURL_fileType_error(AVAssetWriter::alloc(), &NSURL::fileURLWithPath(&path), file_type) }
        .map_err(|_| "video export: the output file could not be created")?;

    let settings = video_settings(job, width, height);
    // SAFETY: a video input with video settings, set up before writing.
    let video = unsafe {
        let video = AVAssetWriterInput::initWithMediaType_outputSettings(
            AVAssetWriterInput::alloc(),
            named(AVMediaTypeVideo),
            Some(&settings),
        );
        video.setExpectsMediaDataInRealTime(false);
        // ↩️2026-11-07 (native-to-rust, Apple writer): the C set this inside
        // @try, 「AVFoundation raises when the output file type has no media
        // time scale to set」. The header names one raise only — a value set
        // on an AUDIO input — and this is the video input of an MP4 or a MOV,
        // set before writing starts; catching it here would need objc2's
        // exception helper, a C build the main PC's Apple check cannot make.
        // The Mac CI job writes both containers through this line.
        if let Some(scale) = media_time_scale(i64::from(job.fps_num)) {
            video.setMediaTimeScale(scale);
        }
        video
    };
    let format = NSNumber::new_u32(if ycbcr { kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange } else { kCVPixelFormatType_32BGRA });
    let (pixel_width, pixel_height) = (NSNumber::new_i32(width as i32), NSNumber::new_i32(height as i32));
    // SAFETY: reading the framework's constant keys.
    let attributes = unsafe {
        dictionary(&[
            (bridged(kCVPixelBufferPixelFormatTypeKey), &format),
            (bridged(kCVPixelBufferWidthKey), &pixel_width),
            (bridged(kCVPixelBufferHeightKey), &pixel_height),
        ])
    };
    // SAFETY: a video input no adaptor holds, before writing; the attributes
    // are pixel buffer attributes.
    let adaptor = unsafe {
        AVAssetWriterInputPixelBufferAdaptor::initWithAssetWriterInput_sourcePixelBufferAttributes(
            AVAssetWriterInputPixelBufferAdaptor::alloc(),
            &video,
            Some(&attributes),
        )
    };
    // SAFETY: an input of our own, offered before writing.
    unsafe {
        if !writer.canAddInput(&video) {
            return Err("video export: this machine's encoder refused the codec");
        }
        writer.addInput(&video);
    }

    let audio = if job.channels > 0 {
        let settings = audio_settings(job);
        // SAFETY: an audio input with audio settings, offered before writing.
        let input = unsafe {
            let input = AVAssetWriterInput::initWithMediaType_outputSettings(
                AVAssetWriterInput::alloc(),
                named(AVMediaTypeAudio),
                Some(&settings),
            );
            input.setExpectsMediaDataInRealTime(false);
            if !writer.canAddInput(&input) {
                return Err("video export: no AAC encoder accepted the mix");
            }
            writer.addInput(&input);
            input
        };
        Some((input, pcm_description(job).ok_or("video export: the PCM description failed")?))
    } else {
        None
    };

    // SAFETY: a writer with its inputs added.
    unsafe {
        if !writer.startWriting() {
            return Err("video export: the writer refused to begin");
        }
        writer.startSessionAtSourceTime(kCMTimeZero);
    }
    Ok(Writer {
        writer,
        video,
        adaptor,
        audio,
        src_width: job.width as usize,
        src_height: job.height as usize,
        width,
        height,
        fps_num: i64::from(job.fps_num),
        fps_den: i64::from(job.fps_den),
        frame_index: 0,
        audio_samples: 0,
        sample_rate: job.sample_rate,
        channels: job.channels as usize,
        keep_alpha: job.codec == CODEC_PRORES_4444 && job.alpha,
        ycbcr,
    })
}

/// Whether `input` takes more within the wait — false when it never did.
fn ready(input: &AVAssetWriterInput) -> bool {
    for _ in 0..=SPINS {
        // SAFETY: a property read on an input of our own.
        if unsafe { input.isReadyForMoreMediaData() } {
            return true;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    false
}

/// `rgba` into `pixels` as BGRA — the ProRes road, where VideoToolbox still
/// makes the YCbCr (4444 carries alpha). False when the buffer is not the
/// shape asked for.
fn fill_bgra(writer: &Writer, pixels: &CVPixelBuffer, rgba: &[u8]) -> bool {
    let base = CVPixelBufferGetBaseAddress(pixels).cast::<u8>();
    let stride = CVPixelBufferGetBytesPerRow(pixels);
    if base.is_null() || stride < writer.width * 4 || CVPixelBufferGetHeight(pixels) < writer.height {
        return false;
    }
    // SAFETY: a locked buffer of at least `height` rows of `stride` bytes.
    let target = unsafe { std::slice::from_raw_parts_mut(base, stride * writer.height) };
    // Opaque codecs bake white pad pixels and force A=0xFF; ProRes 4444
    // with alpha keeps the real channel and pads TRANSPARENT (a hairline
    // of paper would read as content in a compositing master).
    let pad = if writer.keep_alpha { 0x00 } else { 0xFF };
    for (y, out_row) in target.chunks_exact_mut(stride).enumerate() {
        let out_row = &mut out_row[..writer.width * 4];
        if y >= writer.src_height {
            out_row.fill(pad);
            continue;
        }
        let in_row = &rgba[y * writer.src_width * 4..][..writer.src_width * 4];
        let (picture, padding) = out_row.split_at_mut(writer.src_width * 4);
        for (out, pixel) in picture.chunks_exact_mut(4).zip(in_row.chunks_exact(4)) {
            out.copy_from_slice(&[pixel[2], pixel[1], pixel[0], if writer.keep_alpha { pixel[3] } else { 0xFF }]);
        }
        padding.fill(pad);
    }
    true
}

/// `rgba` into `pixels` as NV12 in the app's colour law (`colour`) — the
/// H.26x road — and the buffer TOLD what it holds, so nothing between here
/// and the encoder converts it again. False when the buffer is not the
/// two-plane shape asked for.
fn fill_ycbcr(writer: &Writer, pixels: &CVPixelBuffer, rgba: &[u8]) -> bool {
    if !CVPixelBufferIsPlanar(pixels) || CVPixelBufferGetPlaneCount(pixels) != 2 {
        return false;
    }
    let luma = CVPixelBufferGetBaseAddressOfPlane(pixels, 0).cast::<u8>();
    let chroma = CVPixelBufferGetBaseAddressOfPlane(pixels, 1).cast::<u8>();
    let luma_stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0);
    let chroma_stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 1);
    if luma.is_null()
        || chroma.is_null()
        || luma_stride < writer.width
        || chroma_stride < writer.width
        || CVPixelBufferGetHeightOfPlane(pixels, 0) < writer.height
        || CVPixelBufferGetHeightOfPlane(pixels, 1) < writer.height / 2
    {
        return false;
    }
    // SAFETY: a locked two-plane buffer of at least these rows of these
    // strides, checked above.
    let (y, chroma) = unsafe {
        (
            std::slice::from_raw_parts_mut(luma, luma_stride * writer.height),
            std::slice::from_raw_parts_mut(chroma, chroma_stride * (writer.height / 2)),
        )
    };
    let picture = Picture { rgba, width: writer.src_width, height: writer.src_height };
    let mut planes = Planes { y, y_stride: luma_stride, chroma, cb: 0, cr: 1, chroma_stride, chroma_step: 2 };
    colour::from_rgba(&picture, writer.width, writer.height, &mut planes);
    // SAFETY: the framework's constant keys, each with a value of its own.
    unsafe {
        for (key, value) in [
            (kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4),
            (kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_SMPTE_C),
            (kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2),
        ] {
            pixels.set_attachment(key, value, CVAttachmentMode::ShouldPropagate);
        }
    }
    true
}

impl Writer {
    fn frame(&mut self, rgba: &[u8]) -> bool {
        if !ready(&self.video) {
            return false;
        }
        // SAFETY: the adaptor's pool, once writing has begun.
        let Some(pool) = (unsafe { self.adaptor.pixelBufferPool() }) else {
            return false;
        };
        let mut out: *mut CVPixelBuffer = ptr::null_mut();
        // SAFETY: `out` is a local the call writes once.
        let made = unsafe { CVPixelBufferPool::create_pixel_buffer(None, &pool, NonNull::from(&mut out)) };
        let Some(out) = NonNull::new(out).filter(|_| made == kCVReturnSuccess) else {
            return false;
        };
        // SAFETY: a Create call hands over the one reference it made.
        let pixels = unsafe { CFRetained::from_raw(out) };
        // 🚨The same check the reader makes, for the same reason: on a
        // machine without the media hardware a pool can hand back a buffer
        // that will not lock, or one smaller than asked, and writing a whole
        // frame into it was a segmentation fault instead of a refused frame.
        // SAFETY: a buffer of our own, unlocked below.
        if unsafe { CVPixelBufferLockBaseAddress(&pixels, CVPixelBufferLockFlags(0)) } != kCVReturnSuccess {
            return false;
        }
        let filled = if self.ycbcr { fill_ycbcr(self, &pixels, rgba) } else { fill_bgra(self, &pixels, rgba) };
        // SAFETY: locked above.
        unsafe { CVPixelBufferUnlockBaseAddress(&pixels, CVPixelBufferLockFlags(0)) };
        if !filled {
            return false;
        }
        // Frame i shows at i * den / num seconds — exact fraction, like
        // every other timing conversion in this program.
        // SAFETY: plain arithmetic on a value type.
        let time = unsafe { CMTime::new(self.frame_index * self.fps_den, self.fps_num as i32) };
        // SAFETY: a filled buffer at a numeric time, the input ready.
        if !unsafe { self.adaptor.appendPixelBuffer_withPresentationTime(&pixels, time) } {
            return false;
        }
        self.frame_index += 1;
        true
    }

    fn sound(&mut self, pcm: &[u8], frames: i32) -> bool {
        let Some((input, format)) = &self.audio else {
            return false;
        };
        if !ready(input) {
            return false;
        }
        let mut block: *mut CMBlockBuffer = ptr::null_mut();
        // SAFETY: a block of `pcm.len()` bytes the buffer allocates; `block`
        // is a local the call writes once.
        let made = unsafe {
            CMBlockBuffer::create_with_memory_block(
                None,
                ptr::null_mut(),
                pcm.len(),
                None,
                ptr::null(),
                0,
                pcm.len(),
                0,
                NonNull::from(&mut block),
            )
        };
        let Some(block) = NonNull::new(block).filter(|_| made == 0) else {
            return false;
        };
        // SAFETY: a Create call hands over the one reference it made.
        let block = unsafe { CFRetained::from_raw(block) };
        // SAFETY: `pcm` fills the block it was sized for. The C ignored the
        // answer too: a block that did not take it fails as a sample below.
        let _ = unsafe { CMBlockBuffer::replace_data_bytes(NonNull::from(pcm).cast::<c_void>(), &block, 0, pcm.len()) };
        // SAFETY: plain arithmetic on a value type.
        let time = unsafe { CMTime::new(self.audio_samples, self.sample_rate) };
        let mut sample: *mut CMSampleBuffer = ptr::null_mut();
        // SAFETY: a ready block of `frames` PCM frames in `format`; `sample`
        // is a local the call writes once.
        let made = unsafe {
            CMAudioSampleBufferCreateWithPacketDescriptions(
                None,
                Some(&block),
                true,
                None,
                ptr::null_mut(),
                format,
                frames as isize,
                time,
                ptr::null(),
                NonNull::from(&mut sample),
            )
        };
        let Some(sample) = NonNull::new(sample).filter(|_| made == 0) else {
            return false;
        };
        // SAFETY: a Create call hands over the one reference it made.
        let sample = unsafe { CFRetained::from_raw(sample) };
        // SAFETY: an audio sample for the audio input, which is ready.
        if !unsafe { input.appendSampleBuffer(&sample) } {
            return false;
        }
        self.audio_samples += i64::from(frames);
        true
    }
}

/// # Safety
/// `rgba` is null or holds the frame `open` was given.
pub unsafe fn write_frame(rgba: *const u8) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|_| !rgba.is_null()) else {
        return false;
    };
    // SAFETY: the caller's contract.
    let rgba = unsafe { std::slice::from_raw_parts(rgba, writer.src_width * writer.src_height * 4) };
    autoreleasepool(|_| writer.frame(rgba))
}

/// # Safety
/// `interleaved` is null or holds `frames` × the channels `open` was given.
pub unsafe fn write_audio(interleaved: *const i16, frames: i32) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|writer| writer.audio.is_some() && !interleaved.is_null() && frames > 0)
    else {
        return false;
    };
    // SAFETY: the caller's contract.
    let pcm = unsafe { std::slice::from_raw_parts(interleaved.cast::<u8>(), frames as usize * writer.channels * 2) };
    autoreleasepool(|_| writer.sound(pcm, frames))
}

pub fn finish() -> bool {
    let Some(writer) = lock(&WRITER).take() else {
        return false;
    };
    autoreleasepool(|_| {
        // SAFETY: inputs of a writer that began, all appends returned.
        unsafe {
            writer.video.markAsFinished();
            if let Some((audio, _)) = &writer.audio {
                audio.markAsFinished();
            }
        }
        let (done, finished) = mpsc::channel();
        let handler = RcBlock::new(move || {
            let _ = done.send(());
        });
        // SAFETY: the handler only signals, from whichever queue runs it.
        unsafe { writer.writer.finishWritingWithCompletionHandler(&handler) };
        let _ = finished.recv();
        // SAFETY: a property read on a writer that has finished.
        let status = unsafe { writer.writer.status() };
        status == AVAssetWriterStatus::Completed
    })
}

pub fn abort() {
    if let Some(writer) = lock(&WRITER).take() {
        // SAFETY: a writer that began.
        autoreleasepool(|_| unsafe { writer.writer.cancelWriting() });
    }
}
