//! Apple: AVAssetReader, through objc2 (↩️`qa_video_apple.m`'s decode half
//! until the connection round deleted it).
//! A reader is started over a time RANGE and walks forward; it cannot seek,
//! so repositioning builds a new one over the same asset. A whole file is an
//! asset on its URL; a span is SERVED — AVFoundation has no 「open this file
//! from byte N」 — through a URL whose scheme it does not know, and a
//! resource loader answering every request for it out of media's one span
//! reader. The only pixel job here is BGRA → RGBA and the stride.
//!
//! 🔄**THE C'S READER HALF ONCE SAID THE OPPOSITE**: 「deliberately NOT
//! AVAssetReader … a reader is sequential, the wrong tool for 『the picture
//! at frame N』」. That stopped being true the day the viewer grew a play
//! button: playing IS asking for N, then N+1, and the image generator before
//! this answered each with a fresh random access (유저 2026-08-31:
//! 「재생하고있는데 화면이 첫 프레임 그림에서 전혀 안바뀜」). Its one advantage,
//! exact frames, is kept by the law's half-frame slack (`sample_reaches`).

use std::ffi::CStr;
use std::sync::{Mutex, PoisonError};

use dispatch2::{DispatchQueue, DispatchRetained};
use media::span::Span;
use objc2::rc::{Retained, autoreleasepool};
use objc2::runtime::{AnyObject, NSObject, NSObjectProtocol, ProtocolObject};
use objc2::{AllocAnyThread, DefinedClass, define_class, msg_send};
use objc2_av_foundation::{
    AVAsset, AVAssetReader, AVAssetReaderStatus, AVAssetReaderTrackOutput, AVAssetResourceLoader,
    AVAssetResourceLoaderDelegate, AVAssetResourceLoadingRequest, AVAssetTrack, AVFileTypeAppleM4V,
    AVFileTypeMPEG4, AVFileTypeQuickTimeMovie, AVMediaTypeVideo, AVURLAsset,
};
use objc2_core_media::{CMTime, CMTimeFlags, CMTimeRange, kCMTimePositiveInfinity};
use objc2_core_video::{
    CVPixelBuffer, CVPixelBufferGetBaseAddress, CVPixelBufferGetBytesPerRow, CVPixelBufferGetHeight,
    CVPixelBufferGetPixelFormatType, CVPixelBufferGetWidth, CVPixelBufferIsPlanar,
    CVPixelBufferLockBaseAddress, CVPixelBufferLockFlags, CVPixelBufferUnlockBaseAddress,
    kCVPixelBufferPixelFormatTypeKey, kCVPixelFormatType_32BGRA, kCVReturnSuccess,
};
use objc2_foundation::{NSData, NSDictionary, NSNumber, NSString, NSURL};

use super::{Opened, PAST_THE_END, Rate, Why, frame_ticks, sample_reaches, ticks_at};

pub const SUPPORTED: bool = true;

/// The ticks a read walks in: µs, as the C counted them.
const TICKS: i64 = 1_000_000;

/// How many samples a read walks toward its frame before it gives up — the
/// guard the other two carry: a stream that never reaches its target ends
/// rather than spins.
const WALK: usize = 600;

/// The most one response hands AVFoundation at a time. A request 「to the end
/// of the resource」 is the whole rest of the movie, and answering it in one
/// piece was one allocation the size of the movie.
const SERVED_CHUNK: i64 = 1024 * 1024;

/// The platform's own state for one movie.
pub struct Reader {
    asset: Retained<AVAsset>,
    track: Retained<AVAssetTrack>,
    /// What serves a span, held for as long as the asset is — AVFoundation
    /// keeps only a WEAK reference to a resource loader's delegate, so
    /// letting it go is how a carried movie stops answering mid-play.
    serving: Option<(Retained<Serving>, DispatchRetained<DispatchQueue>)>,
    /// The reader over the range last started, and its one output.
    reading: Option<(Retained<AVAssetReader>, Retained<AVAssetReaderTrackOutput>)>,
    stored: (usize, usize),
}

// SAFETY: the asset, its track and the reader are opened on the caller's
// thread and then called only from the movie's reading thread (`reading.rs`),
// one call at a time; the span the loader answers from on its own queue is
// behind a lock of its own.
unsafe impl Send for Reader {}

impl Reader {
    pub fn open(path: &CStr, span: Option<(i64, i64, bool)>) -> Result<(Reader, Opened), Why> {
        autoreleasepool(|_| {
            let (asset, serving) = match span {
                Some((offset, length, framed)) => {
                    // ⛔The span refuses itself when it is not INSIDE the file, or
                    // when a framed header does not hold together: a loader that
                    // promised bytes the file cannot supply would produce a
                    // truncated movie, which reads as a corrupt one rather than as
                    // a span that was wrong.
                    let span = Span::open(path, offset, length, framed).ok_or("that span does not hold a readable movie")?;
                    let (asset, serving) = served(span);
                    (asset, Some(serving))
                }
                None => {
                    let path = path.to_str().map_err(|_| "path is not valid UTF-8")?;
                    // SAFETY: a file URL.
                    (unsafe { AVAsset::assetWithURL(&NSURL::fileURLWithPath(&NSString::from_str(path))) }, None)
                }
            };
            // SAFETY: an asset of our own, asked for its pictures.
            #[allow(deprecated)]
            let tracks = unsafe { asset.tracksWithMediaType(AVMediaTypeVideo.expect("an AVFoundation name")) };
            let track = tracks.firstObject().ok_or("this file has no readable video stream")?;
            // SAFETY: plain property reads on the track.
            let (size, turn, rate, range) =
                unsafe { (track.naturalSize(), track.preferredTransform(), track.nominalFrameRate(), track.timeRange()) };
            // 🚨★★★**THE STORED SIZE, AND THE TURN REPORTED SEPARATELY.** The
            // C once handed back the display size and let the image generator
            // apply the transform — correct, and the only place in the program
            // that was: upright phone video lay on its side on the other two.
            // The turn is a FACT this reports and the law acts on, once, for
            // everyone; a reader's track output does not apply it either.
            let (width, height) = (size.width.abs() as i32, size.height.abs() as i32);
            // atan2 over the matrix rather than four hard-coded shapes: it reads
            // a rotation that carries a scale or a flip alongside it, which the
            // literal comparisons quietly answered 「none」 for.
            let rotation = (turn.b.atan2(turn.a) * 180.0 / std::f64::consts::PI).round() as i32;
            // 🚨★★★**THE VIDEO TRACK'S duration, not the ASSET'S.** An asset is
            // as long as its longest track, and an MP4's AAC ends tens of ms
            // past its last picture: counted from the asset, that is a frame
            // with no picture in it (유저 2026-08-31 「72프레임짜리 비디오인데
            // 73프레임째의 빈 화면」). ⛔A track with no usable range still has
            // pictures: the asset's duration is the honest upper bound rather
            // than none.
            // SAFETY: plain arithmetic and a property read.
            let seconds = [unsafe { range.duration.seconds() }, unsafe { asset.duration().seconds() }]
                .into_iter()
                .find(|seconds| seconds.is_finite() && *seconds > 0.0)
                .unwrap_or(0.0);
            let opened = Opened {
                stored_width: width,
                stored_height: height,
                rotation,
                // ⚠️The rate goes back RAW, as a number: the law makes it a
                // fraction (`rate_to_fraction`), for MediaCodec's too.
                rate: Rate::Nominal(f64::from(rate)),
                length: ((seconds * 1_000_000.0 + 0.5) as i64, TICKS),
            };
            // ⛔No reader is built HERE: a reader owns a time RANGE, and which
            // depends on the frame asked for — `reposition`'s, which the law
            // calls exactly when the position it wants is not the one loaded.
            let stored = (width.max(0) as usize, height.max(0) as usize);
            Ok((Reader { asset, track, serving, reading: None, stored }, opened))
        })
    }

    pub fn reposition(&mut self, index: i64, rate: (i32, i32)) -> Result<(), Why> {
        // In the rate's own clock, where every frame's time is whole — the
        // C's CMTimeMake(index × den, num).
        // SAFETY: plain arithmetic on a value type.
        let start = unsafe { CMTime::new(ticks_at(index, i64::from(rate.0), rate), rate.0) };
        autoreleasepool(|_| self.start_reading(start))
    }

    /// Starts a fresh reader delivering pictures from `start` to the end —
    /// which needs no length.
    ///
    /// 🚨★★★**REPOSITIONING IS BUILDING A NEW READER — there is no seek.** A
    /// reader walks forward from the range it was started over and cannot be
    /// rewound, which is why the law asks for a reposition only when the index
    /// it wants is not the one already next: playing builds one reader per
    /// PLAY, not one per frame.
    fn start_reading(&mut self, start: CMTime) -> Result<(), Why> {
        self.stop_reading();
        let described = |error: Retained<objc2_foundation::NSError>| Why::from(error.localizedDescription().to_string());
        // SAFETY (each): a reader over an asset of our own, set up before it
        // starts; the settings are a video output's.
        unsafe {
            let reader = AVAssetReader::initWithAsset_error(AVAssetReader::alloc(), &self.asset).map_err(described)?;
            reader.setTimeRange(CMTimeRange { start, duration: kCMTimePositiveInfinity });
            // 32BGRA so the pixel job is the byte swap Media Foundation's path
            // does — one conversion shape rather than a second one.
            let format = NSNumber::new_u32(kCVPixelFormatType_32BGRA);
            let (key, value): (&NSString, &AnyObject) = (kCVPixelBufferPixelFormatTypeKey.as_ref(), &format);
            let settings = NSDictionary::from_slices(&[key], &[value]);
            let output = AVAssetReaderTrackOutput::assetReaderTrackOutputWithTrack_outputSettings(&self.track, Some(&settings));
            // ⛔The buffer is copied out before the next pull, so there is
            // nothing to protect from being reused.
            output.setAlwaysCopiesSampleData(false);
            if !reader.canAddOutput(&output) {
                return Err("no decoder for this codec".into());
            }
            reader.addOutput(&output);
            if !reader.startReading() {
                return Err(reader.error().map_or("that movie could not be read".into(), described));
            }
            self.reading = Some((reader, output));
        }
        Ok(())
    }

    /// Lets the reader go and leaves the asset: every reposition builds a
    /// fresh one over it.
    fn stop_reading(&mut self) {
        if let Some((reader, _)) = self.reading.take() {
            // SAFETY: a reader of our own.
            unsafe { reader.cancelReading() };
        }
    }

    /// Walks the reader forward to the picture for `index` and writes it,
    /// straight RGBA at the stored size.
    ///
    /// 🚨★★★**FORWARD, NOT A SEEK.** The reader is already standing on the
    /// next picture whenever the law asks for it, which is what makes the walk
    /// below empty in the common case.
    pub fn read(&mut self, index: i64, rate: (i32, i32), rgba: &mut [u8], alive: &dyn Fn()) -> Result<(), Why> {
        let Some((reader, output)) = &self.reading else {
            return Err("no document is open".into());
        };
        let (target, frame) = (ticks_at(index, TICKS, rate), frame_ticks(TICKS, rate));
        autoreleasepool(|_| {
            for _ in 0..WALK {
                // SAFETY: the output of a reader that started.
                let next = unsafe { output.copyNextSampleBuffer() };
                alive();
                let Some(sample) = next else {
                    // SAFETY: a property read on a reader of our own.
                    let failed = unsafe { reader.status() } == AVAssetReaderStatus::Failed;
                    return Err(if failed { "the reader failed mid-stream" } else { PAST_THE_END }.into());
                };
                // SAFETY: a sample of our own.
                let stamp = micros(unsafe { sample.presentation_time_stamp() });
                if !sample_reaches(stamp.unwrap_or(target), target, frame) {
                    continue;
                }
                // SAFETY: as above.
                let pixels = unsafe { sample.image_buffer() }.ok_or("that frame could not be read")?;
                return copy_bgra(&pixels, self.stored, rgba);
            }
            Err("that frame could not be read".into())
        })
    }
}

impl Drop for Reader {
    fn drop(&mut self) {
        // ⚠️The reader goes FIRST: it is what is still asking the loader for
        // bytes, and closing the span under a live reader is a read on a
        // closed file rather than a clean stop.
        self.stop_reading();
        if let Some((serving, _)) = &self.serving {
            *serving.ivars().span.lock().unwrap_or_else(PoisonError::into_inner) = None;
        }
    }
}

/// A sample time in µs, rounded as the C rounded it — none when it is not a
/// number (an infinity, or indefinite), which the walk takes for its target.
fn micros(time: CMTime) -> Option<i64> {
    let numeric = time.flags.contains(CMTimeFlags::Valid) && !time.flags.intersects(CMTimeFlags::ImpliedValueFlagsMask);
    // SAFETY: plain arithmetic on a value type.
    numeric.then(|| (unsafe { time.seconds() } * 1_000_000.0 + 0.5) as i64)
}

/// One BGRA pixel buffer out as straight RGBA at the stored size.
///
/// ⚠️`bytesPerRow` is NOT width × 4: a hardware decoder pads its rows.
///
/// 🚨★★★**IT CHECKS WHAT IT WAS HANDED BEFORE IT READS A BYTE.** The BGRA asked
/// for comes out of a hardware scaler, and a machine without one hands back
/// something else — Codemagic's Mac is a VM (`IOServiceMatching failed for:
/// AppleM2ScalerParavirtDriver`, 2026-09-10). The C once read the stored size
/// out of whatever arrived, and the test process died of a segmentation
/// fault with no sentence anywhere saying why.
fn copy_bgra(pixels: &CVPixelBuffer, (width, height): (usize, usize), rgba: &mut [u8]) -> Result<(), Why> {
    let format = CVPixelBufferGetPixelFormatType(pixels);
    let have = (CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels));
    if format != kCVPixelFormatType_32BGRA || CVPixelBufferIsPlanar(pixels) || have.0 < width || have.1 < height {
        let name = format_name(format);
        let why = format!("the reader handed back a {name} picture of {}x{}, not the BGRA {width}x{height} this copy reads", have.0, have.1);
        return Err(why.into());
    }
    // SAFETY: a buffer of our own, unlocked below.
    if unsafe { CVPixelBufferLockBaseAddress(pixels, CVPixelBufferLockFlags::ReadOnly) } != kCVReturnSuccess {
        return Err("the reader's picture would not lock for reading".into());
    }
    let base = CVPixelBufferGetBaseAddress(pixels).cast::<u8>();
    let pitch = CVPixelBufferGetBytesPerRow(pixels);
    let copied = if base.is_null() || pitch < width * 4 {
        Err("the reader's picture has no readable rows".into())
    } else {
        // SAFETY: a locked buffer of at least `height` rows of `pitch` bytes,
        // its size checked above.
        let source = unsafe { std::slice::from_raw_parts(base, pitch * height) };
        for (out, row) in rgba.chunks_exact_mut(width * 4).zip(source.chunks(pitch)) {
            for (to, bgra) in out.chunks_exact_mut(4).zip(row.chunks_exact(4)) {
                to.copy_from_slice(&[bgra[2], bgra[1], bgra[0], 255]);
            }
        }
        Ok(())
    };
    // SAFETY: locked above.
    unsafe { CVPixelBufferUnlockBaseAddress(pixels, CVPixelBufferLockFlags::ReadOnly) };
    copied
}

/// A pixel format's four letters, printable — or as hex when it is one of
/// the numeric codes.
fn format_name(format: u32) -> String {
    let code = format.to_be_bytes();
    if code.iter().all(|byte| (0x20..=0x7E).contains(byte)) {
        format!("'{}'", code.iter().map(|&byte| char::from(byte)).collect::<String>())
    } else {
        format!("0x{format:08X}")
    }
}

/// What a served span answers from: media's one reader of a span — opened
/// once and kept, since a loader is asked for small ranges constantly while
/// a movie plays and an open per request would make playback a stream of
/// opens — its length, and the container its first bytes name. The span is
/// none once its movie is closed.
struct Served {
    span: Mutex<Option<Span>>,
    length: i64,
    container: &'static NSString,
}

define_class!(
    // SAFETY: NSObject has no subclassing requirements, and this has no Drop.
    // ⚠️A name of its own: the engine's C, loaded beside this in its tests,
    // registers `QaRangeResourceLoader`, and two classes of one name abort.
    #[unsafe(super(NSObject))]
    #[name = "AnicelServedSpan"]
    #[ivars = Served]
    struct Serving;

    unsafe impl NSObjectProtocol for Serving {}

    // SAFETY: the one method AVFoundation asks of a delegate that loads
    // media data, with the protocol's own signature.
    unsafe impl AVAssetResourceLoaderDelegate for Serving {
        #[unsafe(method(resourceLoader:shouldWaitForLoadingOfRequestedResource:))]
        fn should_wait(&self, _loader: &AVAssetResourceLoader, request: &AVAssetResourceLoadingRequest) -> bool {
            answer(self.ivars(), request)
        }
    }
);

/// The asset that reads `span`, and what serves it to the asset.
///
/// 🚨★★★**A RANGE REACHES AVFOUNDATION AS A URL IT CANNOT RESOLVE.** `AVURLAsset`
/// takes a URL and nothing else — there is no offset to give it — so the
/// range is served rather than addressed. That indirection IS Apple's byte
/// stream; Windows writes an `IMFByteStream`, Android hands over a descriptor
/// and a range. ⚠️The scheme must be one nothing else claims: a recognised
/// one (`file:`, say) AVFoundation loads itself, and never asks the delegate.
fn served(mut span: Span) -> (Retained<AVAsset>, (Retained<Serving>, DispatchRetained<DispatchQueue>)) {
    let length = span.size();
    let (container, extension) = container_of(&mut span, length);
    let serving = Serving::alloc().set_ivars(Served { span: Mutex::new(Some(span)), length, container });
    // SAFETY: NSObject's init.
    let serving: Retained<Serving> = unsafe { msg_send![super(serving), init] };
    let queue = DispatchQueue::new("qa.range.loader", None);
    // ⚠️The name wears the container's extension too, so nothing that reads
    // the URL before asking the loader guesses otherwise.
    let url = NSURL::URLWithString(&NSString::from_str(&format!("qa-anicel-range:///movie.{extension}")));
    let url = url.expect("a URL this file spells");
    // SAFETY: a URL asset, and a delegate and queue the reader keeps for as
    // long as it keeps the asset.
    let asset = unsafe { AVURLAsset::URLAssetWithURL_options(&url, None) };
    unsafe { asset.resourceLoader().setDelegate_queue(Some(ProtocolObject::from_ref(&*serving)), Some(&queue)) };
    (Retained::into_super(asset), (serving, queue))
}

/// Which container `span` holds, read off its first bytes, and the extension
/// its served URL wears to match: an ISO media file says so in its `ftyp`
/// box — `qt  ` is QuickTime, `M4V` an iTunes movie, anything else MPEG-4 —
/// and a QuickTime file older than `ftyp` begins straight with its atoms.
///
/// 🚨★★★**AVFOUNDATION DOES NOT SNIFF WHAT A RESOURCE LOADER SERVES.** The C's
/// loader answered `public.movie`, on the belief that 「the generic type lets
/// it sniff the bytes」: every movie served that way opened with no video
/// track at all on the Apple runner (2026-09-24, the first test ever to open
/// a span on Apple).
fn container_of(span: &mut Span, length: i64) -> (&'static NSString, &'static str) {
    let mut head = [0u8; 12];
    let read = length >= 12 && span.read(0, &mut head) == Some(12);
    let named = |name: Option<&'static NSString>| name.expect("an AVFoundation name");
    // SAFETY: reading the framework's constants.
    let (mpeg4, quicktime, m4v) = unsafe { (named(AVFileTypeMPEG4), named(AVFileTypeQuickTimeMovie), named(AVFileTypeAppleM4V)) };
    if !read {
        (mpeg4, "mp4")
    } else if &head[4..8] != b"ftyp" || &head[8..12] == b"qt  " {
        (quicktime, "mov")
    } else if &head[8..11] == b"M4V" {
        (m4v, "m4v")
    } else {
        (mpeg4, "mp4")
    }
}

/// One request AVFoundation makes of a served span, answered out of it.
fn answer(served: &Served, request: &AVAssetResourceLoadingRequest) -> bool {
    // ⚠️Under the span's lock: a movie closing while a request is answered
    // waits for the answer, rather than freeing the reader under its read.
    let mut span = served.span.lock().unwrap_or_else(PoisonError::into_inner);
    let Some(span) = span.as_mut() else { return false };
    // SAFETY (each): AVFoundation's request, answered on the queue it asked
    // on.
    unsafe {
        if let Some(information) = request.contentInformationRequest() {
            // What the span looks like from outside: a file of its length, of
            // the container its own first bytes name.
            information.setContentLength(served.length);
            information.setByteRangeAccessSupported(true);
            information.setContentType(Some(served.container));
        }
        let Some(data) = request.dataRequest() else {
            request.finishLoading();
            return true;
        };
        let mut at = data.requestedOffset().max(data.currentOffset());
        if at < 0 || at >= served.length {
            request.finishLoading();
            return true;
        }
        let asked = if data.requestsAllDataToEndOfResource() { served.length - at } else { data.requestedLength() as i64 };
        let mut left = asked.min(served.length - at);
        // A chunk at a time, so the largest thing held is one chunk however
        // much was asked for — and a request AVFoundation gave up on stops
        // being read.
        while left > 0 && !request.isCancelled() {
            let mut bytes = vec![0u8; left.min(SERVED_CHUNK) as usize];
            let Some(read) = span.read(at, &mut bytes).filter(|&read| read > 0) else {
                // The file would not read, or a block would not decode: said as
                // a failure rather than served as whatever the buffer held.
                request.finishLoadingWithError(None);
                return true;
            };
            data.respondWithData(&NSData::with_bytes(&bytes[..read]));
            at += read as i64;
            left -= read as i64;
        }
        request.finishLoading();
    }
    true
}
