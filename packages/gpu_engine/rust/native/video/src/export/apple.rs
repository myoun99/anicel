//! Apple: AVAssetWriter, through objc2 (↩️`qa_video_apple.m`'s export half
//! until the connection round deleted it).
//! The writer IS the OS's MP4/MOV writer on macOS and iOS: hardware H.264
//! and H.265 through VideoToolbox, ProRes where the machine has it, AAC
//! through AudioToolbox, muxing included. Our pixel job: for H.26x, NV12
//! laid into the two planes as it is — an export's from the GPU engine, a
//! trimmed piece's as its movie's decoder made it, named as that movie
//! names it; RGBA → BGRA for ProRes; and the even-size pad. ↩️RGBA was
//! made NV12 here in the app's colour law for H.26x too, till 2026-11-15.

use std::collections::VecDeque;
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
    AVVideoColorPropertiesKey, AVVideoCompressionPropertiesKey, AVVideoHeightKey, AVVideoTransferFunctionKey,
    AVVideoWidthKey, AVVideoYCbCrMatrixKey,
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
    CVPixelBufferUnlockBaseAddress, kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey,
    kCVImageBufferYCbCrMatrixKey, kCVPixelBufferHeightKey, kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey,
    kCVPixelFormatType_32BGRA, kCVReturnSuccess,
};
use objc2_foundation::{NSDictionary, NSFileManager, NSNumber, NSString, NSURL};

use super::{
    BAD_OPEN, CODEC_H264, CODEC_HEVC, CODEC_PRORES_4444, CODEC_PRORES_422, CODEC_PRORES_HQ,
    CODEC_PRORES_LT, CODEC_PRORES_PROXY, CONTAINER_MOV, CONTAINER_MP4, H26X_TAKES_NV12, Job, lock, set_error,
};
use super::nv12::{self, Nv12};
use crate::colour::{Colours, Planes, core_video};

pub const SUPPORTED: bool = true;

/// How long a write waits for an input that holds back more than it may
/// ([`Writer::hand_on`]), in 1 ms naps with neither input taking anything:
/// an offline render waits for the encoder to drain, and gives up after
/// 10 s.
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
    /// Frames go to the encoder as NV12 the app made (`colour`) rather than
    /// BGRA for VideoToolbox to convert — every codec but ProRes, which is
    /// handed RGBA alone ([`write_frame`]) as H.26x is NV12 alone.
    ycbcr: bool,
    /// What the NV12 is named, on every buffer (`Job::named`).
    colours: Colours,
    /// What each input was handed and has not taken yet, in the order it
    /// came: a frame with its time and its index, a sound with its first
    /// sample and its length ([`Writer::hand_on`]).
    ///
    /// 🚨A WRITE NEVER WAITS ON ONE INPUT WHILE THE CALLER HOLDS WHAT THE
    /// OTHER NEEDS (저장 2026-11-16, round-1091-builds-all-stop-at-their-checks).
    /// AVAssetWriter keeps an input not ready while it waits for another's
    /// media, to lay the two in its own interleaving pattern
    /// (AVAssetWriterInput.h, `readyForMoreMediaData`), and the caller
    /// hands a frame and then that frame's sound, one call at a time. A
    /// frame waited here for the video input, and the sound the writer
    /// waited on could come only after it: on the Mac runner each long
    /// movie with sound reached frame 28 (about 1.17 s in) 60 to 80 s into
    /// its job and gave up there, 「the video input took nothing for 10 s
    /// (writer status 1)」 — every run. Now what an input will not take yet
    /// waits here, and goes in whenever it takes, while the caller's next
    /// call hands the other its own. ⚠️Read from the code and the header:
    /// no Mac has run it yet.
    waiting_frames: VecDeque<(CFRetained<CVPixelBuffer>, CMTime, i64)>,
    waiting_sound: VecDeque<(CFRetained<CMSampleBuffer>, i64, i64)>,
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


/// A Core Video name as the NSString it is toll-free bridged to — what
/// AVFoundation's settings take.
fn bridged(name: &CFString) -> &NSString {
    name.as_ref()
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
    // choose. A piece's are its movie's (`Job::named`) — ⚠️all three or
    // none, as AVFoundation takes them: a movie that leaves one unnamed
    // names it only on its buffers ([`into_two_planes`]).
    let [primaries, transfer, matrix] = core_video::names_of(job.named());
    let colour = match (&primaries, &transfer, &matrix) {
        (Some(primaries), Some(transfer), Some(matrix)) => Some(unsafe {
            // SAFETY: reading the framework's constant names; each name a
            // CFString as the NSString it is toll-free bridged to.
            dictionary(&[
                (named(AVVideoColorPrimariesKey), bridged(primaries)),
                (named(AVVideoTransferFunctionKey), bridged(transfer)),
                (named(AVVideoYCbCrMatrixKey), bridged(matrix)),
            ])
        }),
        _ => None,
    };
    if let Some(colour) = colour.as_ref().filter(|_| !is_prores(job.codec)) {
        // SAFETY: as above.
        entries.push((named(unsafe { AVVideoColorPropertiesKey }), colour));
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
    if held.is_some() {
        set_error(BAD_OPEN);
        return false;
    }
    let path = job.path;
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
    // The two planes in the range the pictures are in: the law's studio
    // range, or a piece's movie's own.
    let format = if ycbcr { core_video::biplanar_of(job.named().range) } else { kCVPixelFormatType_32BGRA };
    let format = NSNumber::new_u32(format);
    let (pixel_width, pixel_height) = (NSNumber::new_i32(width as i32), NSNumber::new_i32(height as i32));
    // SAFETY: reading the framework's constant keys, each a CFString as the
    // NSString it is toll-free bridged to.
    let attributes = unsafe {
        dictionary(&[
            (kCVPixelBufferPixelFormatTypeKey.as_ref(), &format),
            (kCVPixelBufferWidthKey.as_ref(), &pixel_width),
            (kCVPixelBufferHeightKey.as_ref(), &pixel_height),
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
        colours: job.named(),
        waiting_frames: VecDeque::new(),
        waiting_sound: VecDeque::new(),
    })
}

/// False, and why `what` was refused: in the writer's words where it has
/// failed — its status and AVFoundation's reason — as the other writers say
/// why a frame or a sound was not taken (`windows.rs`: 「a frame failed to
/// encode」). ↩️(round-1091-builds-all-stop-at-their-checks, 2026-11-16)
/// each refusal here answered false and said nothing, so the Mac runner's
/// two long test movies failed with an empty reason — and the writer they
/// left open answered the next opens 「bad open parameters」.
fn refused(writer: &AVAssetWriter, what: &str) -> bool {
    // SAFETY: property reads on a writer of our own.
    let (status, error) = unsafe { (writer.status(), writer.error()) };
    let status = status.0;
    set_error(&match error {
        Some(error) => format!("video export: {what} (writer status {status}: {})", error.localizedDescription()),
        None => format!("video export: {what} (writer status {status})"),
    });
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

/// `frame` into `pixels` as it is — an export's frames on the H.26x road,
/// the colour law's bytes already, or a piece's, its movie's own: laid.
fn fill_nv12(writer: &Writer, pixels: &CVPixelBuffer, frame: &Nv12) -> bool {
    into_two_planes(writer, pixels, |planes| nv12::lay(frame, planes))
}

/// `pixels`' two planes handed to `fill` as NV12 lies in them, and the
/// buffer TOLD what it holds, so nothing between here and the encoder
/// converts it again. False when the buffer is not the two-plane shape
/// asked for.
fn into_two_planes(writer: &Writer, pixels: &CVPixelBuffer, fill: impl FnOnce(&mut Planes)) -> bool {
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
    fill(&mut Planes { y, y_stride: luma_stride, chroma, cb: 0, cr: 1, chroma_stride, chroma_step: 2 });
    // Each the pictures are named (`Job::named`), and none they are not.
    let [primaries, transfer, matrix] = core_video::names_of(writer.colours);
    // SAFETY: the framework's constant keys, each with a value of its own.
    unsafe {
        for (key, value) in [
            (kCVImageBufferYCbCrMatrixKey, matrix),
            (kCVImageBufferColorPrimariesKey, primaries),
            (kCVImageBufferTransferFunctionKey, transfer),
        ] {
            if let Some(value) = value {
                pixels.set_attachment(key, &value, CVAttachmentMode::ShouldPropagate);
            }
        }
    }
    true
}

impl Writer {
    /// The next frame: a buffer of the adaptor's pool, filled by `fill`
    /// while it is locked, handed on at its time ([`Self::hand_on`]).
    fn frame(&mut self, fill: impl FnOnce(&Writer, &CVPixelBuffer) -> bool) -> bool {
        let at = self.frame_index;
        // SAFETY: the adaptor's pool, once writing has begun.
        let Some(pool) = (unsafe { self.adaptor.pixelBufferPool() }) else {
            return refused(&self.writer, &format!("frame {at}: the adaptor has no pixel buffer pool"));
        };
        let mut out: *mut CVPixelBuffer = ptr::null_mut();
        // SAFETY: `out` is a local the call writes once.
        let made = unsafe { CVPixelBufferPool::create_pixel_buffer(None, &pool, NonNull::from(&mut out)) };
        let Some(out) = NonNull::new(out).filter(|_| made == kCVReturnSuccess) else {
            return refused(&self.writer, &format!("frame {at}: the pool made no pixel buffer ({made})"));
        };
        // SAFETY: a Create call hands over the one reference it made.
        let pixels = unsafe { CFRetained::from_raw(out) };
        // 🚨The same check the reader makes, for the same reason: on a
        // machine without the media hardware a pool can hand back a buffer
        // that will not lock, or one smaller than asked, and writing a whole
        // frame into it was a segmentation fault instead of a refused frame.
        // SAFETY: a buffer of our own, unlocked below.
        if unsafe { CVPixelBufferLockBaseAddress(&pixels, CVPixelBufferLockFlags(0)) } != kCVReturnSuccess {
            return refused(&self.writer, &format!("frame {at}: the pixel buffer would not lock"));
        }
        let filled = fill(self, &pixels);
        // SAFETY: locked above.
        unsafe { CVPixelBufferUnlockBaseAddress(&pixels, CVPixelBufferLockFlags(0)) };
        if !filled {
            return refused(&self.writer, &format!("frame {at}: the pixel buffer is not the shape asked"));
        }
        // Frame i shows at i * den / num seconds — exact fraction, like
        // every other timing conversion in this program.
        // SAFETY: plain arithmetic on a value type.
        let time = unsafe { CMTime::new(self.frame_index * self.fps_den, self.fps_num as i32) };
        self.waiting_frames.push_back((pixels, time, at));
        self.frame_index += 1;
        self.hand_on(self.second())
    }

    fn sound(&mut self, pcm: &[u8], frames: i32) -> bool {
        let Some((_, format)) = &self.audio else {
            return false;
        };
        let at = self.audio_samples;
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
            return refused(&self.writer, &format!("sound at sample {at}: no block buffer ({made})"));
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
            return refused(&self.writer, &format!("sound at sample {at}: no sample buffer ({made})"));
        };
        // SAFETY: a Create call hands over the one reference it made.
        let sample = unsafe { CFRetained::from_raw(sample) };
        self.waiting_sound.push_back((sample, at, i64::from(frames)));
        self.audio_samples += i64::from(frames);
        self.hand_on(self.second())
    }

    /// A second of the movie — its frames, rounded up, and its samples:
    /// how much an input may hold back before a write waits for it. ⚠️How
    /// far the Apple writer holds one input for another is not measured;
    /// the caller hands each frame's sound right after it, a skew of one
    /// frame, and a refusal says how much was waiting.
    fn second(&self) -> (usize, i64) {
        (((self.fps_num + self.fps_den - 1) / self.fps_den) as usize, i64::from(self.sample_rate))
    }

    /// Hands each input what it was handed and has not taken, as far as it
    /// takes it, and while either holds back more than `room` (frames,
    /// samples) waits for them to. False, in the writer's words, where it
    /// refused one, or neither took anything for [`SPINS`] naps.
    fn hand_on(&mut self, room: (usize, i64)) -> bool {
        let mut naps = 0;
        loop {
            let Some(frames) = self.hand_frames() else {
                return false;
            };
            let Some(sound) = self.hand_sound() else {
                return false;
            };
            if self.waiting_frames.len() <= room.0 && self.waiting_samples() <= room.1 {
                return true;
            }
            if frames || sound {
                naps = 0;
            } else if naps == SPINS {
                return self.refuse_waiting(room);
            } else {
                naps += 1;
                std::thread::sleep(Duration::from_millis(1));
            }
        }
    }

    /// The frames waiting, appended while the video input takes them:
    /// whether it took any — none where it refused one.
    fn hand_frames(&mut self) -> Option<bool> {
        let mut took = false;
        // SAFETY: a property read on an input of our own.
        while !self.waiting_frames.is_empty() && unsafe { self.video.isReadyForMoreMediaData() } {
            let Some((pixels, time, at)) = self.waiting_frames.pop_front() else {
                break;
            };
            // SAFETY: a filled buffer at a numeric time, the input ready.
            if !unsafe { self.adaptor.appendPixelBuffer_withPresentationTime(&pixels, time) } {
                refused(&self.writer, &format!("frame {at} was not appended"));
                return None;
            }
            took = true;
        }
        Some(took)
    }

    /// [`Self::hand_frames`] for the sound.
    fn hand_sound(&mut self) -> Option<bool> {
        let Some((input, _)) = &self.audio else {
            return Some(false);
        };
        let mut took = false;
        // SAFETY: a property read on an input of our own.
        while !self.waiting_sound.is_empty() && unsafe { input.isReadyForMoreMediaData() } {
            let Some((sample, at, _)) = self.waiting_sound.pop_front() else {
                break;
            };
            // SAFETY: an audio sample for the audio input, which is ready.
            if !unsafe { input.appendSampleBuffer(&sample) } {
                refused(&self.writer, &format!("sound at sample {at} was not appended"));
                return None;
            }
            took = true;
        }
        Some(took)
    }

    fn waiting_samples(&self) -> i64 {
        self.waiting_sound.iter().map(|(_, _, frames)| frames).sum()
    }

    /// False, and which input held back past `room` while neither took
    /// anything for [`SPINS`] naps, with what each was holding.
    fn refuse_waiting(&self, room: (usize, i64)) -> bool {
        let held = format!("{} frames and {} samples waiting", self.waiting_frames.len(), self.waiting_samples());
        match self.waiting_frames.front().filter(|_| self.waiting_frames.len() > room.0) {
            Some((_, _, at)) => {
                refused(&self.writer, &format!("frame {at}: the video input took nothing for 10 s ({held})"))
            }
            None => {
                let at = self.waiting_sound.front().map_or(self.audio_samples, |(_, at, _)| *at);
                refused(&self.writer, &format!("sound at sample {at}: the audio input took nothing for 10 s ({held})"))
            }
        }
    }
}

/// # Safety
/// `rgba` is null or holds the frame `open` was given.
pub unsafe fn write_frame(rgba: *const u8) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|_| !rgba.is_null()) else {
        return false;
    };
    if writer.ycbcr {
        set_error(H26X_TAKES_NV12);
        return false;
    }
    // SAFETY: the caller's contract.
    let rgba = unsafe { std::slice::from_raw_parts(rgba, writer.src_width * writer.src_height * 4) };
    autoreleasepool(|_| writer.frame(|writer, pixels| fill_bgra(writer, pixels, rgba)))
}

/// The frame the open writer takes as NV12 — the H.26x road's, padded
/// even; none for ProRes, which takes BGRA.
pub fn nv12_shape() -> Option<(usize, usize)> {
    lock(&WRITER).as_ref().filter(|writer| writer.ycbcr).map(|writer| (writer.width, writer.height))
}

/// # Safety
/// `bytes` is null or holds the frame `nv12_shape` says, rows `stride`
/// bytes apart.
pub unsafe fn write_nv12(bytes: *const u8, stride: i64) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|writer| writer.ycbcr && !bytes.is_null() && stride > 0) else {
        return false;
    };
    // SAFETY: the caller's contract.
    let Some(frame) = (unsafe { nv12::handed(bytes, stride as usize, writer.width, writer.height) }) else {
        return false;
    };
    autoreleasepool(|_| writer.frame(|writer, pixels| fill_nv12(writer, pixels, &frame)))
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
    let Some(mut writer) = lock(&WRITER).take() else {
        return false;
    };
    autoreleasepool(|_| {
        // What either input still holds back goes in before it is marked
        // finished — the sound first, so that no frame is held for sound
        // that will not come; a writer that will not take it is let go.
        let heard = writer.hand_on((usize::MAX, 0));
        if heard && let Some((audio, _)) = &writer.audio {
            // SAFETY: an input of a writer that began, its appends returned.
            unsafe { audio.markAsFinished() };
        }
        if !heard || !writer.hand_on((0, 0)) {
            // SAFETY: a writer that began.
            unsafe { writer.writer.cancelWriting() };
            return false;
        }
        // SAFETY: as above.
        unsafe { writer.video.markAsFinished() };
        let (done, finished) = mpsc::channel();
        let handler = RcBlock::new(move || {
            let _ = done.send(());
        });
        // SAFETY: the handler only signals, from whichever queue runs it.
        unsafe { writer.writer.finishWritingWithCompletionHandler(&handler) };
        let _ = finished.recv();
        // SAFETY: a property read on a writer that has finished.
        let status = unsafe { writer.writer.status() };
        status == AVAssetWriterStatus::Completed || refused(&writer.writer, "the movie did not finish")
    })
}

pub fn abort() {
    if let Some(writer) = lock(&WRITER).take() {
        // SAFETY: a writer that began.
        autoreleasepool(|_| unsafe { writer.writer.cancelWriting() });
    }
}
