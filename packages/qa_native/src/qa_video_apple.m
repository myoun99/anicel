// The Apple half of the OS video encoder (AUDIO-PRO R7): AVAssetWriter.
//
// Objective-C on purpose — AVAssetWriter IS the OS's MP4 writer on both
// macOS and iOS (hardware H.264 through VideoToolbox, AAC through
// AudioToolbox, muxing included), and it has no C surface. The portable
// export API stays in qa_video_encode.c; this file implements the
// qa_video_apple_* functions it forwards to on __APPLE__.
//
// Compiled two ways, like the other Apple sources: CMake adds it to the
// standalone dylib (CI parity builds), and the ios/macos pods pick it up
// through a Classes/ forwarder.

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

// ⛔ARC ONLY. The globals below hold AVFoundation objects with no retain,
// which is correct under ARC and a use-after-free without it — see the
// COMPILE_OPTIONS beside this file in CMakeLists.txt for the crash that
// proved it.
#if !__has_feature(objc_arc)
#error "qa_video_apple.m must be compiled with ARC (-fobjc-arc)"
#endif

#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "qa_media_span.h"
#include "qa_yuv601.h"

// Mirrors qa_video_encode.c's ABI v21 values.
#define QA_VIDEO_CONTAINER_MP4 0
#define QA_VIDEO_CONTAINER_MOV 1
#define QA_VIDEO_CODEC_H264 0
#define QA_VIDEO_CODEC_HEVC 1
#define QA_VIDEO_CODEC_PRORES_PROXY 2
#define QA_VIDEO_CODEC_PRORES_LT 3
#define QA_VIDEO_CODEC_PRORES_422 4
#define QA_VIDEO_CODEC_PRORES_HQ 5
#define QA_VIDEO_CODEC_PRORES_4444 6

typedef struct {
  int32_t src_width;
  int32_t src_height;
  int32_t width;
  int32_t height;
  int64_t fps_num;
  int64_t fps_den;
  int64_t frame_index;
  int64_t audio_samples;
  int32_t sample_rate;
  int32_t channels;
  int32_t open;
  int32_t preserve_alpha;
  // Frames go to the encoder as NV12 this file made (`qa_yuv601.h`) rather
  // than BGRA for VideoToolbox to convert — every codec but ProRes.
  int32_t writes_ycbcr;
} qa_video_apple_state;

// The v10 pair matrix on Apple: H.264 in both containers, H.265 in MP4,
// ProRes in MOV. Legality alone — device support (an iPad without the
// ProRes engine) answers at open, where the writer can refuse.
static int qa_apple_pair_legal(int32_t container, int32_t codec) {
  switch (codec) {
    case QA_VIDEO_CODEC_H264:
      return 1;
    case QA_VIDEO_CODEC_HEVC:
      return container == QA_VIDEO_CONTAINER_MP4;
    case QA_VIDEO_CODEC_PRORES_PROXY:
    case QA_VIDEO_CODEC_PRORES_LT:
    case QA_VIDEO_CODEC_PRORES_422:
    case QA_VIDEO_CODEC_PRORES_HQ:
    case QA_VIDEO_CODEC_PRORES_4444:
      return container == QA_VIDEO_CONTAINER_MOV;
    default:
      return 0;
  }
}

int32_t qa_video_apple_probe(int32_t container, int32_t codec) {
  return qa_apple_pair_legal(container, codec);
}

// The AVFoundation codec identifiers ARE these fourcc strings; literals
// dodge SDK-availability guards on the newer named constants (ProRes
// Proxy/LT gained names only in macOS 12 / iOS 15 SDKs).
static NSString* qa_apple_codec_id(int32_t codec) {
  switch (codec) {
    case QA_VIDEO_CODEC_HEVC:
      return @"hvc1";
    case QA_VIDEO_CODEC_PRORES_PROXY:
      return @"apco";
    case QA_VIDEO_CODEC_PRORES_LT:
      return @"apcs";
    case QA_VIDEO_CODEC_PRORES_422:
      return @"apcn";
    case QA_VIDEO_CODEC_PRORES_HQ:
      return @"apch";
    case QA_VIDEO_CODEC_PRORES_4444:
      return @"ap4h";
    default:
      return AVVideoCodecTypeH264;
  }
}

static qa_video_apple_state g_apple;
static AVAssetWriter* g_writer;
static AVAssetWriterInput* g_video_input;
static AVAssetWriterInput* g_audio_input;
static AVAssetWriterInputPixelBufferAdaptor* g_adaptor;
static CMAudioFormatDescriptionRef g_audio_format;

static void qa_apple_set_error(char* error,
                               int32_t capacity,
                               const char* message) {
  if (error == NULL || capacity <= 1) {
    return;
  }
  int32_t index = 0;
  while (message[index] != '\0' && index < capacity - 1) {
    error[index] = message[index];
    index += 1;
  }
  error[index] = '\0';
}

static void qa_apple_teardown(void) {
  g_writer = nil;
  g_video_input = nil;
  g_audio_input = nil;
  g_adaptor = nil;
  if (g_audio_format != NULL) {
    CFRelease(g_audio_format);
    g_audio_format = NULL;
  }
  memset(&g_apple, 0, sizeof(g_apple));
}

int32_t qa_video_apple_open(const char* utf8_path,
                            int32_t width,
                            int32_t height,
                            int32_t fps_num,
                            int32_t fps_den,
                            int32_t sample_rate,
                            int32_t channels,
                            int32_t container,
                            int32_t codec,
                            int32_t alpha,
                            int32_t bitrate_bps,
                            char* error,
                            int32_t error_capacity) {
  if (g_apple.open || utf8_path == NULL || width <= 0 || height <= 0 ||
      fps_num <= 0 || fps_den <= 0 || channels < 0) {
    qa_apple_set_error(error, error_capacity,
                       "video export: bad open parameters");
    return 0;
  }
  if (!qa_apple_pair_legal(container, codec)) {
    qa_apple_set_error(error, error_capacity,
                       "video export: that container/codec pair is not in "
                       "the lineup");
    return 0;
  }
  @autoreleasepool {
    memset(&g_apple, 0, sizeof(g_apple));
    g_apple.src_width = width;
    g_apple.src_height = height;
    g_apple.width = width + (width & 1);
    g_apple.height = height + (height & 1);
    g_apple.fps_num = fps_num;
    g_apple.fps_den = fps_den;
    g_apple.sample_rate = sample_rate;
    g_apple.channels = channels;
    g_apple.preserve_alpha =
        (codec == QA_VIDEO_CODEC_PRORES_4444 && alpha != 0) ? 1 : 0;
    const int is_prores = codec >= QA_VIDEO_CODEC_PRORES_PROXY;

    NSString* path = [NSString stringWithUTF8String:utf8_path];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSError* writer_error = nil;
    g_writer = [[AVAssetWriter alloc]
        initWithURL:[NSURL fileURLWithPath:path]
           fileType:container == QA_VIDEO_CONTAINER_MOV
                        ? AVFileTypeQuickTimeMovie
                        : AVFileTypeMPEG4
              error:&writer_error];
    if (g_writer == nil) {
      qa_apple_set_error(error, error_capacity,
                         "video export: the output file could not be created");
      qa_apple_teardown();
      return 0;
    }

    NSMutableDictionary* video_settings = [@{
      AVVideoCodecKey : qa_apple_codec_id(codec),
      AVVideoWidthKey : @(g_apple.width),
      AVVideoHeightKey : @(g_apple.height),
    } mutableCopy];
    if (!is_prores && bitrate_bps > 0) {
      video_settings[AVVideoCompressionPropertiesKey] =
          @{AVVideoAverageBitRateKey : @(bitrate_bps)};
    }
    // 🚨★★★**THE H.26x PICTURES ARE MADE YCbCr HERE, IN THE APP'S COLOUR
    // LAW, AND THE FILE SAYS SO** (`qa_yuv601.h`, BT.601 studio range —
    // what the Android writer has always written). They used to go in as
    // BGRA for VideoToolbox to convert, and what the Apple reader turned
    // back had lost red in exact proportion — 0.9136 of it, BT.709 in and
    // BT.601 out: red 110 came back 101, and a piece cut from a take 168
    // where the take showed 185 (2026-09-25, board
    // `trimmed-piece-apple-parity`). Naming BT.601 in these properties
    // alone moved none of those numbers, so the pictures are converted
    // before the encoder sees them, and these properties now describe what
    // was really written. ⚠️ProRes stays BGRA: 4444 carries alpha, and its
    // conversion is still VideoToolbox's to choose.
    if (!is_prores) {
      g_apple.writes_ycbcr = 1;
      video_settings[AVVideoColorPropertiesKey] = @{
        AVVideoColorPrimariesKey : AVVideoColorPrimaries_SMPTE_C,
        AVVideoTransferFunctionKey : AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_601_4,
      };
    }
    g_video_input =
        [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                       outputSettings:video_settings];
    g_video_input.expectsMediaDataInRealTime = NO;
    // 🚨THE TRACK KEEPS TIME IN A UNIT THAT HOLDS ONE FRAME EXACTLY. Frame
    // i is appended at exactly i * den / num seconds, but an input left at
    // its default time scale lets the writer pick its own, and in 1/600 s a
    // 24000/1001 frame is 25.025 units: it rounds to 25, every frame lasts
    // exactly 1/24 s, and the file says 24.0 fps. A trimmed 23.976 take came
    // back as 24 on the Apple engine only (2026-09-25, first run of
    // `a_trimmed_file_is_carried_as_its_piece_test` on a Mac). A multiple
    // of the rate's numerator holds every frame time exactly; it is lifted
    // to at least 600 so a 12 or 24 fps track keeps a conventional unit.
    //
    // ⚠️Guarded: AVFoundation raises when the output file type has no media
    // time scale to set, and an exception here would take the process down
    // over a property that only ever refines the timing.
    {
      int64_t scale = g_apple.fps_num;
      if (scale > 0 && scale < 600) {
        scale *= (600 + scale - 1) / scale;
      }
      if (scale > 0 && scale <= INT32_MAX) {
        @try {
          g_video_input.mediaTimeScale = (CMTimeScale)scale;
        } @catch (NSException* ignored) {
          (void)ignored;
        }
      }
    }
    g_adaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc]
        initWithAssetWriterInput:g_video_input
     sourcePixelBufferAttributes:@{
       (id)kCVPixelBufferPixelFormatTypeKey : g_apple.writes_ycbcr
           ? @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
           : @(kCVPixelFormatType_32BGRA),
       (id)kCVPixelBufferWidthKey : @(g_apple.width),
       (id)kCVPixelBufferHeightKey : @(g_apple.height),
     }];
    if (![g_writer canAddInput:g_video_input]) {
      qa_apple_set_error(error, error_capacity,
                         "video export: this machine's encoder refused the "
                         "codec");
      qa_apple_teardown();
      return 0;
    }
    [g_writer addInput:g_video_input];

    if (channels > 0) {
      // ProRes deliveries carry PCM (the master convention); the H.26x
      // containers keep AAC.
      NSDictionary* audio_settings = is_prores
          ? @{
              AVFormatIDKey : @(kAudioFormatLinearPCM),
              AVSampleRateKey : @(sample_rate),
              AVNumberOfChannelsKey : @(channels),
              AVLinearPCMBitDepthKey : @16,
              AVLinearPCMIsFloatKey : @NO,
              AVLinearPCMIsBigEndianKey : @NO,
              AVLinearPCMIsNonInterleaved : @NO,
            }
          : @{
              AVFormatIDKey : @(kAudioFormatMPEG4AAC),
              AVSampleRateKey : @(sample_rate),
              AVNumberOfChannelsKey : @(channels),
              AVEncoderBitRateKey : @192000,
            };
      g_audio_input = [[AVAssetWriterInput alloc]
          initWithMediaType:AVMediaTypeAudio
             outputSettings:audio_settings];
      g_audio_input.expectsMediaDataInRealTime = NO;
      if (![g_writer canAddInput:g_audio_input]) {
        qa_apple_set_error(error, error_capacity,
                           "video export: no AAC encoder accepted the mix");
        qa_apple_teardown();
        return 0;
      }
      [g_writer addInput:g_audio_input];

      AudioStreamBasicDescription pcm;
      memset(&pcm, 0, sizeof(pcm));
      pcm.mSampleRate = (Float64)sample_rate;
      pcm.mFormatID = kAudioFormatLinearPCM;
      pcm.mFormatFlags =
          kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
      pcm.mBytesPerPacket = (UInt32)(channels * 2);
      pcm.mFramesPerPacket = 1;
      pcm.mBytesPerFrame = (UInt32)(channels * 2);
      pcm.mChannelsPerFrame = (UInt32)channels;
      pcm.mBitsPerChannel = 16;
      if (CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &pcm, 0, NULL, 0,
                                         NULL, NULL,
                                         &g_audio_format) != noErr) {
        qa_apple_set_error(error, error_capacity,
                           "video export: the PCM description failed");
        qa_apple_teardown();
        return 0;
      }
    }

    if (![g_writer startWriting]) {
      qa_apple_set_error(error, error_capacity,
                         "video export: the writer refused to begin");
      qa_apple_teardown();
      return 0;
    }
    [g_writer startSessionAtSourceTime:kCMTimeZero];
    g_apple.open = 1;
    return 1;
  }
}

/// [rgba] into [pixel_buffer] as BGRA — the ProRes road, where VideoToolbox
/// still makes the YCbCr (4444 carries alpha). 0 when the buffer is not the
/// shape asked for.
static int qa_apple_fill_bgra(CVPixelBufferRef pixel_buffer,
                              const uint8_t* rgba) {
  uint8_t* base = (uint8_t*)CVPixelBufferGetBaseAddress(pixel_buffer);
  const size_t stride = CVPixelBufferGetBytesPerRow(pixel_buffer);
  if (base == NULL || stride < (size_t)g_apple.width * 4 ||
      CVPixelBufferGetHeight(pixel_buffer) < (size_t)g_apple.height) {
    return 0;
  }
  // Opaque codecs bake white pad pixels and force A=0xFF; ProRes 4444
  // with alpha keeps the real channel and pads TRANSPARENT (a hairline
  // of paper would read as content in a compositing master).
  const int keep_alpha = g_apple.preserve_alpha;
  const uint8_t pad_value = keep_alpha ? 0x00 : 0xFF;
  for (int32_t y = 0; y < g_apple.height; y += 1) {
    uint8_t* out_row = base + (size_t)y * stride;
    if (y >= g_apple.src_height) {
      memset(out_row, pad_value, (size_t)g_apple.width * 4);
      continue;
    }
    const uint8_t* in_row = rgba + (size_t)y * (size_t)g_apple.src_width * 4;
    for (int32_t x = 0; x < g_apple.src_width; x += 1) {
      out_row[x * 4 + 0] = in_row[x * 4 + 2];  // B
      out_row[x * 4 + 1] = in_row[x * 4 + 1];  // G
      out_row[x * 4 + 2] = in_row[x * 4 + 0];  // R
      out_row[x * 4 + 3] = keep_alpha ? in_row[x * 4 + 3] : 0xFF;
    }
    for (int32_t x = g_apple.src_width; x < g_apple.width; x += 1) {
      out_row[x * 4 + 0] = pad_value;
      out_row[x * 4 + 1] = pad_value;
      out_row[x * 4 + 2] = pad_value;
      out_row[x * 4 + 3] = pad_value;
    }
  }
  return 1;
}

/// [rgba] into [pixel_buffer] as NV12 in the app's colour law
/// (`qa_yuv601.h`) — the H.26x road — and the buffer TOLD what it holds,
/// so nothing between here and the encoder converts it again. 0 when the
/// buffer is not the two-plane shape asked for.
static int qa_apple_fill_ycbcr(CVPixelBufferRef pixel_buffer,
                               const uint8_t* rgba) {
  if (!CVPixelBufferIsPlanar(pixel_buffer) ||
      CVPixelBufferGetPlaneCount(pixel_buffer) != 2) {
    return 0;
  }
  uint8_t* luma =
      (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 0);
  uint8_t* chroma =
      (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 1);
  const size_t luma_stride =
      CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer, 0);
  const size_t chroma_stride =
      CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer, 1);
  if (luma == NULL || chroma == NULL ||
      luma_stride < (size_t)g_apple.width ||
      chroma_stride < (size_t)g_apple.width ||
      CVPixelBufferGetHeightOfPlane(pixel_buffer, 0) <
          (size_t)g_apple.height ||
      CVPixelBufferGetHeightOfPlane(pixel_buffer, 1) <
          (size_t)g_apple.height / 2) {
    return 0;
  }
  qa_yuv601_from_rgba(rgba, g_apple.src_width, g_apple.src_height,
                      g_apple.width, g_apple.height, luma,
                      (int32_t)luma_stride, chroma, chroma + 1,
                      (int32_t)chroma_stride, 2);
  CVBufferSetAttachment(pixel_buffer, kCVImageBufferYCbCrMatrixKey,
                        kCVImageBufferYCbCrMatrix_ITU_R_601_4,
                        kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixel_buffer, kCVImageBufferColorPrimariesKey,
                        kCVImageBufferColorPrimaries_SMPTE_C,
                        kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixel_buffer, kCVImageBufferTransferFunctionKey,
                        kCVImageBufferTransferFunction_ITU_R_709_2,
                        kCVAttachmentMode_ShouldPropagate);
  return 1;
}

int32_t qa_video_apple_write_frame(const uint8_t* rgba) {
  if (!g_apple.open || rgba == NULL) {
    return 0;
  }
  @autoreleasepool {
    // Offline render: waiting for the writer is correct, and bounded in
    // practice by the encoder draining.
    int spins = 0;
    while (!g_video_input.readyForMoreMediaData) {
      usleep(1000);
      if (++spins > 10000) {
        return 0;
      }
    }
    CVPixelBufferRef pixel_buffer = NULL;
    CVPixelBufferPoolRef pool = g_adaptor.pixelBufferPool;
    if (pool == NULL ||
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool,
                                           &pixel_buffer) != kCVReturnSuccess) {
      return 0;
    }
    // 🚨The same check the reader makes, for the same reason: on a machine
    // without the media hardware a pool can hand back a buffer that will not
    // lock, or one smaller than asked, and writing a whole frame into it was
    // a segmentation fault instead of a refused frame.
    if (CVPixelBufferLockBaseAddress(pixel_buffer, 0) != kCVReturnSuccess) {
      CVPixelBufferRelease(pixel_buffer);
      return 0;
    }
    const int filled = g_apple.writes_ycbcr
                           ? qa_apple_fill_ycbcr(pixel_buffer, rgba)
                           : qa_apple_fill_bgra(pixel_buffer, rgba);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    if (!filled) {
      CVPixelBufferRelease(pixel_buffer);
      return 0;
    }

    // frame i shows at i * den / num seconds — exact fraction, like every
    // other timing conversion in this program.
    const CMTime time = CMTimeMake(g_apple.frame_index * g_apple.fps_den,
                                   (int32_t)g_apple.fps_num);
    const BOOL appended = [g_adaptor appendPixelBuffer:pixel_buffer
                                  withPresentationTime:time];
    CVPixelBufferRelease(pixel_buffer);
    if (!appended) {
      return 0;
    }
    g_apple.frame_index += 1;
    return 1;
  }
}

int32_t qa_video_apple_write_audio(const int16_t* interleaved,
                                   int32_t frames) {
  if (!g_apple.open || g_audio_input == nil || interleaved == NULL ||
      frames <= 0) {
    return 0;
  }
  @autoreleasepool {
    int spins = 0;
    while (!g_audio_input.readyForMoreMediaData) {
      usleep(1000);
      if (++spins > 10000) {
        return 0;
      }
    }
    const size_t bytes = (size_t)frames * (size_t)g_apple.channels * 2;
    CMBlockBufferRef block = NULL;
    if (CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, bytes,
                                           kCFAllocatorDefault, NULL, 0, bytes,
                                           0, &block) != noErr) {
      return 0;
    }
    CMBlockBufferReplaceDataBytes(interleaved, block, 0, bytes);
    CMSampleBufferRef sample = NULL;
    const CMTime pts =
        CMTimeMake(g_apple.audio_samples, g_apple.sample_rate);
    const OSStatus status = CMAudioSampleBufferCreateWithPacketDescriptions(
        kCFAllocatorDefault, block, true, NULL, NULL, g_audio_format,
        (CMItemCount)frames, pts, NULL, &sample);
    CFRelease(block);
    if (status != noErr || sample == NULL) {
      return 0;
    }
    const BOOL appended = [g_audio_input appendSampleBuffer:sample];
    CFRelease(sample);
    if (!appended) {
      return 0;
    }
    g_apple.audio_samples += frames;
    return 1;
  }
}

int32_t qa_video_apple_finish(void) {
  if (!g_apple.open) {
    return 0;
  }
  @autoreleasepool {
    [g_video_input markAsFinished];
    if (g_audio_input != nil) {
      [g_audio_input markAsFinished];
    }
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL completed = NO;
    [g_writer finishWritingWithCompletionHandler:^{
      completed = (g_writer.status == AVAssetWriterStatusCompleted);
      dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    qa_apple_teardown();
    return completed ? 1 : 0;
  }
}

void qa_video_apple_abort(void) {
  if (!g_apple.open) {
    return;
  }
  @autoreleasepool {
    [g_writer cancelWriting];
    qa_apple_teardown();
  }
}

// ---------------------------------------------------------------------------
// The DECODE half (ABI v27): AVAssetReader, positioned by the shared law.
//
// 🔄**THIS USED TO SAY THE OPPOSITE, AND THE PREMISE IT RESTED ON IS GONE.**
// It read: 「the reader half of this file is deliberately NOT AVAssetReader.
// A reader is sequential — it is the right tool for 『play this through
// once』 and the wrong one for 『the picture at frame N』, which is the only
// question this app asks.」 That last clause stopped being true the day the
// viewer grew a play button: playing IS asking for frame N, then N+1, then
// N+2, and `copyCGImageAtTime` answers each of them with a fresh random
// access. 유저 2026-08-31: 「재생하고있는데 화면이 첫 프레임 그림에서 전혀
// 안바뀜」 — a decoder that cannot keep up, on the platform that was paying
// a seek per frame while the other two had stopped.
//
// The generator's real advantage — exact frames rather than the nearest
// keyframe — is not lost: a reader started at frame N's time delivers the
// pictures from N onward in order, and `qa_video_decode.c` matches each one
// by its presentation stamp with the same half-frame slack Media Foundation
// and MediaCodec use. The generator's zero tolerances did that work
// internally; now it is done once, where all three platforms can see it.
//
// ⛔A reader cannot seek: it is started over a time RANGE and walks
// forward. That is exactly the `reposition` hook — repositioning here means
// building a new reader — and it is why the hook existed before this file
// changed rather than being invented with it.
//
// One document at a time, matching qa_video_decode.c's contract.

// ---------------------------------------------------------------------------
// Serving a SPAN of a file to AVFoundation.
//
// 🚨★★★**AVFoundation HAS NO 「open this file from byte N」.** `AVURLAsset`
// takes a URL; there is no offset parameter anywhere. Its answer is a URL
// with a scheme it does not recognise plus a delegate that answers every
// request for it — so where Windows writes an `IMFByteStream` and Android
// passes a descriptor with a range, Apple SERVES the bytes.
//
// 🚨The bytes come from `qa_media_span`, the library's one reader of a span
// (2026-09-24) — the movie as it is, or FRAMED (compressed in blocks by the
// save), decompressed a block at a time as AVFoundation asks. This used to
// read through an `NSFileHandle` at `base + wanted`, the third copy of those
// three lines, and could serve only a span that held the movie as it is.
//
// ⛔The span is opened once and kept: a resource loader is asked for small
// ranges constantly while a movie plays, and opening the archive per request
// would turn playback into a stream of opens.
@interface QaRangeResourceLoader : NSObject <AVAssetResourceLoaderDelegate>
@property(nonatomic, readonly) BOOL opened;
@property(nonatomic, readonly) dispatch_queue_t queue;
/// The container the span holds, as a type AVFoundation can pick a reader
/// for ([qa_apple_container_type]) — and the extension the served URL
/// wears to match it.
@property(nonatomic, readonly) NSString* containerType;
@property(nonatomic, readonly) NSString* containerExtension;
- (instancetype)initWithPath:(NSString*)path
                      offset:(int64_t)offset
                      length:(int64_t)length
                      framed:(BOOL)framed;
- (void)close;
@end

/// The most one response hands AVFoundation at a time. A request 「to the end
/// of the resource」 is the whole rest of the movie, and answering it in one
/// piece was one allocation the size of the movie.
static const int64_t kQaServedChunkBytes = 1024 * 1024;

/// Which container [span] holds, read off its first bytes: an ISO media file
/// says so in its `ftyp` box — `qt  ` is QuickTime, `M4V` an iTunes movie,
/// anything else MPEG-4 — and a QuickTime file older than `ftyp` begins
/// straight with its atoms.
///
/// 🚨★★★**AVFOUNDATION DOES NOT SNIFF WHAT A RESOURCE LOADER SERVES.** The
/// loader used to answer `public.movie` — an abstract type — on the stated
/// belief that 「the generic type lets it sniff the bytes」. It does not: on
/// the Apple runner every movie served that way opened with no video track
/// at all (2026-09-25, `a_movie_kept_compressed_plays_where_it_lies_test`,
/// the first test ever to open a span on Apple). A plain span took the same
/// road, so a movie carried inside a saved project had the same answer.
static NSString* qa_apple_container_type(qa_media_span* span,
                                         int64_t length) {
  uint8_t head[12];
  if (length < 12 || qa_media_span_read(span, 0, head, 12) != 12) {
    return AVFileTypeMPEG4;
  }
  if (memcmp(head + 4, "ftyp", 4) != 0) {
    return AVFileTypeQuickTimeMovie;
  }
  if (memcmp(head + 8, "qt  ", 4) == 0) {
    return AVFileTypeQuickTimeMovie;
  }
  if (memcmp(head + 8, "M4V", 3) == 0) {
    return AVFileTypeAppleM4V;
  }
  return AVFileTypeMPEG4;
}

@implementation QaRangeResourceLoader {
  qa_media_span* _span;
  int64_t _length;
}

- (instancetype)initWithPath:(NSString*)path
                      offset:(int64_t)offset
                      length:(int64_t)length
                      framed:(BOOL)framed {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _queue = dispatch_queue_create("qa.range.loader", DISPATCH_QUEUE_SERIAL);
  // ⛔The span refuses itself when it is not INSIDE the file, or when a
  // framed header does not hold together: a loader that promised bytes the
  // file cannot supply would produce a truncated movie, which reads as a
  // corrupt one rather than as a span that was wrong.
  _span = qa_media_span_open([path fileSystemRepresentation], offset, length,
                             framed ? 1 : 0);
  _length = qa_media_span_size(_span);
  _opened = _span != NULL;
  if (_opened) {
    _containerType = qa_apple_container_type(_span, _length);
    _containerExtension =
        [_containerType isEqualToString:AVFileTypeQuickTimeMovie] ? @"mov"
        : [_containerType isEqualToString:AVFileTypeAppleM4V]     ? @"m4v"
                                                                  : @"mp4";
  }
  return self;
}

- (void)close {
  // ⚠️On the loader's own queue: a request being answered is reading the
  // span, and closing it under that read is a read on a freed reader.
  dispatch_sync(_queue, ^{
    qa_media_span_close(self->_span);
    self->_span = NULL;
  });
}

- (void)dealloc {
  qa_media_span_close(_span);
}

/// What the span looks like from outside: a file of [_length] bytes of the
/// container its own first bytes name ([qa_apple_container_type]).
///
/// 🪦This answered `public.movie`, with the reason 「claiming a specific
/// container we have not parsed would be a guess … the generic type lets it
/// sniff the bytes」. The first half was fair and the second was never
/// true; the container is now read, not guessed.
- (void)fillInformation:(AVAssetResourceLoadingRequest*)request {
  request.contentInformationRequest.contentLength = _length;
  request.contentInformationRequest.byteRangeAccessSupported = YES;
  request.contentInformationRequest.contentType = _containerType;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader*)resourceLoader
    shouldWaitForLoadingOfRequestedResource:
        (AVAssetResourceLoadingRequest*)loadingRequest {
  (void)resourceLoader;
  if (_span == NULL) {
    return NO;
  }
  if (loadingRequest.contentInformationRequest != nil) {
    [self fillInformation:loadingRequest];
  }
  AVAssetResourceLoadingDataRequest* data = loadingRequest.dataRequest;
  if (data == nil) {
    [loadingRequest finishLoading];
    return YES;
  }
  int64_t wanted = data.requestedOffset;
  if (data.currentOffset > wanted) {
    wanted = data.currentOffset;
  }
  if (wanted < 0 || wanted >= _length) {
    [loadingRequest finishLoading];
    return YES;
  }
  int64_t take = data.requestedLength;
  if (data.requestsAllDataToEndOfResource) {
    take = _length - wanted;
  }
  if (take > _length - wanted) {
    take = _length - wanted;
  }
  // A chunk at a time, so the largest thing held is one chunk however much
  // was asked for — and a request AVFoundation gave up on stops being read.
  while (take > 0 && !loadingRequest.isCancelled) {
    const int64_t chunk = take < kQaServedChunkBytes ? take
                                                     : kQaServedChunkBytes;
    NSMutableData* bytes = [NSMutableData dataWithLength:(NSUInteger)chunk];
    const int64_t read =
        qa_media_span_read(_span, wanted, [bytes mutableBytes], chunk);
    if (read <= 0) {
      // The file would not read, or a block would not decode: said as a
      // failure rather than served as whatever the buffer held.
      [loadingRequest finishLoadingWithError:nil];
      return YES;
    }
    [bytes setLength:(NSUInteger)read];
    [data respondWithData:bytes];
    wanted += read;
    take -= read;
  }
  [loadingRequest finishLoading];
  return YES;
}

@end

/// ONE ROW PER DOCUMENT the law can hold open — `qa_video_decode.c`'s slots,
/// mirrored one layer down. That file names the document by INDEX before
/// every call below ([qa_video_apple_decode_select]), so every name here
/// still means 「the document being worked on」, exactly as it did when there
/// was only ever one.
///
/// ⚠️Rows rather than a struct: these are ARC references, and an array of
/// object pointers keeps them strong without a single ownership qualifier
/// in any of the bodies.
#define QA_APPLE_DECODE_DOCS 8

static AVAsset* g_decode_asset_of[QA_APPLE_DECODE_DOCS];
static AVAssetTrack* g_decode_track_of[QA_APPLE_DECODE_DOCS];
/// Held for as long as the asset is open — AVFoundation keeps only a WEAK
/// reference to a resource-loader delegate, so letting this go is how a
/// carried movie stops answering mid-play.
static QaRangeResourceLoader* g_decode_serving_of[QA_APPLE_DECODE_DOCS];
static AVAssetReader* g_decode_reader_of[QA_APPLE_DECODE_DOCS];
static AVAssetReaderTrackOutput* g_decode_output_of[QA_APPLE_DECODE_DOCS];
static int32_t g_decode_width_of[QA_APPLE_DECODE_DOCS];
static int32_t g_decode_height_of[QA_APPLE_DECODE_DOCS];
static int64_t g_decode_duration_us_of[QA_APPLE_DECODE_DOCS];
static int32_t g_decode_rotation_of[QA_APPLE_DECODE_DOCS];
static double g_decode_nominal_rate_of[QA_APPLE_DECODE_DOCS];

/// Which row the calls below are about.
static int32_t g_decode_slot = 0;

void qa_video_apple_decode_select(int32_t slot) {
  g_decode_slot = (slot >= 0 && slot < QA_APPLE_DECODE_DOCS) ? slot : 0;
}

#define g_decode_asset g_decode_asset_of[g_decode_slot]
#define g_decode_track g_decode_track_of[g_decode_slot]
#define g_decode_serving g_decode_serving_of[g_decode_slot]
#define g_decode_reader g_decode_reader_of[g_decode_slot]
#define g_decode_output g_decode_output_of[g_decode_slot]
#define g_decode_width g_decode_width_of[g_decode_slot]
#define g_decode_height g_decode_height_of[g_decode_slot]
#define g_decode_duration_us g_decode_duration_us_of[g_decode_slot]
#define g_decode_rotation g_decode_rotation_of[g_decode_slot]
#define g_decode_nominal_rate g_decode_nominal_rate_of[g_decode_slot]

/// Tears down the reader without touching the asset — [qa_backend_reposition]
/// builds a fresh one over the same asset for every jump.
static void qa_apple_decode_release_reader(void) {
  if (g_decode_reader != nil) {
    [g_decode_reader cancelReading];
  }
  g_decode_reader = nil;
  g_decode_output = nil;
}

void qa_video_apple_decode_close(void) {
  qa_apple_decode_release_reader();
  g_decode_track = nil;
  g_decode_asset = nil;
  // ⚠️The reader goes FIRST: it is what is still asking the loader for
  // bytes, and closing the file under a live reader is a read on a closed
  // handle rather than a clean stop.
  [g_decode_serving close];
  g_decode_serving = nil;
  g_decode_width = 0;
  g_decode_height = 0;
  g_decode_duration_us = 0;
  g_decode_rotation = 0;
  g_decode_nominal_rate = 0.0;
}

int32_t qa_video_apple_decode_open(const char* utf8_path,
                                   int64_t range_offset,
                                   int64_t range_length,
                                   int32_t framed,
                                   char* error,
                                   int32_t error_capacity) {
  @autoreleasepool {
    qa_video_apple_decode_close();
    if (utf8_path == NULL || utf8_path[0] == '\0') {
      qa_apple_set_error(error, error_capacity, "no path");
      return 0;
    }
    NSString* path = [NSString stringWithUTF8String:utf8_path];
    AVAsset* asset;
    if (range_length > 0) {
      // 🚨★★★**A RANGE REACHES AVFOUNDATION AS A URL IT CANNOT RESOLVE.**
      //
      // `AVURLAsset` takes a URL and nothing else — there is no offset to
      // give it — so the range is served rather than addressed: the asset is
      // built on a URL with a scheme AVFoundation does not know, and the
      // resource loader below answers every request for it out of the file.
      // That indirection IS Apple's byte-stream equivalent; Windows writes
      // an `IMFByteStream`, Android hands over a descriptor and a range.
      //
      // ⚠️The scheme must be one nothing else claims. A recognised one (a
      // `file:` URL, say) is loaded by AVFoundation itself and the delegate
      // is never asked.
      g_decode_serving =
          [[QaRangeResourceLoader alloc] initWithPath:path
                                               offset:range_offset
                                               length:range_length
                                               framed:framed != 0];
      if (g_decode_serving == nil || !g_decode_serving.opened) {
        g_decode_serving = nil;
        qa_apple_set_error(error, error_capacity,
                           "that span does not hold a readable movie");
        return 0;
      }
      // ⚠️The name wears the container's extension too, so nothing that
      // reads the URL before asking the loader guesses otherwise.
      NSString* served_name = [@"qa-anicel-range:///movie."
          stringByAppendingString:g_decode_serving.containerExtension];
      NSURL* served = [NSURL URLWithString:served_name];
      AVURLAsset* urlAsset = [AVURLAsset URLAssetWithURL:served options:nil];
      [urlAsset.resourceLoader setDelegate:g_decode_serving
                                     queue:g_decode_serving.queue];
      asset = urlAsset;
    } else {
      asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:path]];
    }
    NSArray<AVAssetTrack*>* tracks =
        [asset tracksWithMediaType:AVMediaTypeVideo];
    if (asset == nil || tracks.count == 0) {
      qa_apple_set_error(error, error_capacity,
                         "this file has no readable video stream");
      return 0;
    }
    AVAssetTrack* track = tracks.firstObject;
    CGSize size = track.naturalSize;
    // 🚨★★★**THE STORED SIZE, AND THE TURN REPORTED SEPARATELY.**
    //
    // This used to hand back the DISPLAY size and let the image generator
    // apply the transform for us (`appliesPreferredTrackTransform`). It was
    // correct and it was the only place in the program that was: Media
    // Foundation and MediaCodec never asked about rotation at all, so one
    // phone video played upright here and sideways on the other two.
    //
    // ⛔Fixing that by teaching the other two to pre-apply would have made
    // the same knowledge live in three places. The turn is now a FACT this
    // backend reports and `qa_video_decode.c` acts on, once, for everyone.
    //
    // ⚠️It also has to happen BEFORE `AVAssetReader` replaces the generator:
    // a reader's track output does not apply the transform either, so a
    // swap made first would have taken the one working rotation away.
    g_decode_width = (int32_t)fabs(size.width);
    g_decode_height = (int32_t)fabs(size.height);
    // atan2 over the matrix rather than four hard-coded shapes: it reads a
    // rotation that carries a scale or a flip alongside it, which the
    // literal comparisons quietly answered「none」for.
    const CGAffineTransform transform = track.preferredTransform;
    const double radians = atan2((double)transform.b, (double)transform.a);
    g_decode_rotation = (int32_t)lround(radians * 180.0 / M_PI);
    if (g_decode_width <= 0 || g_decode_height <= 0) {
      qa_apple_set_error(error, error_capacity,
                         "the video stream has no frame size");
      return 0;
    }

    // ⚠️The rate goes back RAW. The fraction this file used to reconstruct
    // here is now `qa_rate_to_fraction` in `qa_video_decode.c`, where every
    // backend shares it — Android had no such conversion at all and turned
    // 29.97 into 30 for exactly as long as this one had its own copy.
    float rate = track.nominalFrameRate;
    g_decode_nominal_rate = (double)rate;

    // 🚨★★★**THE VIDEO TRACK'S duration, not the ASSET'S.** An asset is as
    // long as its longest track and that is almost never the video: AAC
    // frames are 1024 samples, so an MP4's audio ends tens of milliseconds
    // past the last picture. Counting from the asset turned that overshoot
    // into a frame with no picture in it — 유저 2026-08-31: 「72프레임짜리
    // 비디오인데 73프레임째의 빈 화면이 생성되어있음」.
    //
    // ⚠️It read as a PLATFORM difference — 「아이패드에선 73번째 프레임이
    // 존재하는데 윈도우에선 흰화면」 — because the two ends fail
    // differently: the image generator clamps and returns the last picture
    // again, while Media Foundation has no sample there and returns
    // nothing. Same wrong count, two symptoms; `qa_video_decode.c` asks
    // its video stream for the same reason.
    Float64 seconds = CMTimeGetSeconds(track.timeRange.duration);
    if (!isfinite(seconds) || seconds <= 0) {
      // ⛔A track with no usable range still has pictures. The asset's
      // duration is the honest upper bound rather than zero frames.
      seconds = CMTimeGetSeconds(asset.duration);
    }
    if (!isfinite(seconds) || seconds <= 0) {
      seconds = 0;
    }
    // ⚠️The COUNT is not computed here any more. It was the third copy of
    // one sum, and the copy that took seconds as a double — which is how a
    // whole number of frames comes back one short (`qa_frame_count_for`
    // carries the case now, in integers, for all three).
    g_decode_duration_us = (int64_t)(seconds * 1000000.0 + 0.5);

    // ⛔No reader is built HERE. A reader owns a time RANGE, and which
    // range depends on the frame asked for — so it belongs in
    // `qa_video_apple_decode_reposition`, which the portable law calls
    // exactly when the position it wants is not the one already loaded.
    g_decode_asset = asset;
    g_decode_track = track;
    return 1;
  }
}

/// Starts a fresh reader delivering pictures from [start] onward.
///
/// 🚨★★★**REPOSITIONING IS BUILDING A NEW READER — there is no seek.** An
/// `AVAssetReader` walks forward from the range it was started over and
/// cannot be rewound, which is exactly why the portable law asks for a
/// reposition ONLY when the index it wants is not the one the backend is
/// already standing on. Sequential playback therefore builds one reader per
/// PLAY, not one per frame.
///
/// ⚠️`kCMTimePositiveInfinity` for the duration: the range is 「from here to
/// the end」, and asking for a finite one would need the length again.
static int32_t qa_apple_start_reader(CMTime start,
                                     char* error,
                                     int32_t error_capacity) {
  qa_apple_decode_release_reader();
  if (g_decode_asset == nil || g_decode_track == nil) {
    qa_apple_set_error(error, error_capacity, "no document is open");
    return 0;
  }
  NSError* failure = nil;
  AVAssetReader* reader = [[AVAssetReader alloc] initWithAsset:g_decode_asset
                                                         error:&failure];
  if (reader == nil) {
    qa_apple_set_error(error, error_capacity,
                       failure == nil
                           ? "that movie could not be read"
                           : failure.localizedDescription.UTF8String);
    return 0;
  }
  reader.timeRange = CMTimeRangeMake(start, kCMTimePositiveInfinity);
  // 32BGRA so the pixel job is the byte swap Media Foundation's path
  // already does — one conversion shape rather than a second one written
  // in Core Graphics.
  AVAssetReaderTrackOutput* output = [AVAssetReaderTrackOutput
      assetReaderTrackOutputWithTrack:g_decode_track
                       outputSettings:@{
                         (id)kCVPixelBufferPixelFormatTypeKey :
                             @(kCVPixelFormatType_32BGRA)
                       }];
  // ⛔The buffer is read and copied out before the next pull, so there is
  // nothing to protect from being reused.
  output.alwaysCopiesSampleData = NO;
  if (![reader canAddOutput:output]) {
    qa_apple_set_error(error, error_capacity,
                       "no decoder for this codec");
    return 0;
  }
  [reader addOutput:output];
  if (![reader startReading]) {
    qa_apple_set_error(error, error_capacity,
                       reader.error == nil
                           ? "that movie could not be read"
                           : reader.error.localizedDescription.UTF8String);
    return 0;
  }
  g_decode_reader = reader;
  g_decode_output = output;
  return 1;
}

int32_t qa_video_apple_decode_reposition(int64_t index,
                                         int32_t fps_num,
                                         int32_t fps_den,
                                         char* error,
                                         int32_t error_capacity) {
  @autoreleasepool {
    if (fps_num <= 0 || fps_den <= 0) {
      qa_apple_set_error(error, error_capacity, "no document is open");
      return 0;
    }
    return qa_apple_start_reader(
        CMTimeMake(index * (int64_t)fps_den, fps_num), error, error_capacity);
  }
}

/// What this backend KNOWS, not what it concluded.
///
/// ⚠️[stored_width]/[stored_height] are the size the pictures come out at,
/// BEFORE the display transform, and [rotation] is that transform in
/// degrees. 🚨[duration_us] and [nominal_rate] are RAW: the frame count and
/// the rate-as-a-fraction were both computed here once, and both were the
/// third copy of a sum `qa_video_decode.c` now owns for every backend.
int32_t qa_video_apple_decode_info(int32_t* stored_width,
                                   int32_t* stored_height,
                                   int32_t* rotation,
                                   int64_t* duration_us,
                                   double* nominal_rate) {
  if (g_decode_track == nil) {
    return 0;
  }
  if (stored_width != NULL) *stored_width = g_decode_width;
  if (stored_height != NULL) *stored_height = g_decode_height;
  if (rotation != NULL) *rotation = g_decode_rotation;
  if (duration_us != NULL) *duration_us = g_decode_duration_us;
  if (nominal_rate != NULL) *nominal_rate = g_decode_nominal_rate;
  return 1;
}

/// A pixel format's four-character code, printable — or as hex when it is
/// one of the numeric codes.
static void qa_apple_format_name(OSType format, char* out, size_t capacity) {
  const unsigned char code[4] = {
      (unsigned char)((format >> 24) & 0xFF),
      (unsigned char)((format >> 16) & 0xFF),
      (unsigned char)((format >> 8) & 0xFF),
      (unsigned char)(format & 0xFF),
  };
  for (int i = 0; i < 4; i += 1) {
    if (code[i] < 0x20 || code[i] > 0x7E) {
      snprintf(out, capacity, "0x%08X", (unsigned int)format);
      return;
    }
  }
  snprintf(out, capacity, "'%c%c%c%c'", code[0], code[1], code[2], code[3]);
}

/// Copies one BGRA pixel buffer out as straight RGBA at the stored size.
///
/// ⚠️`bytesPerRow` is NOT width×4. A hardware decoder pads rows, and reading
/// them as if it did not is the Apple twin of the stride bug the Windows
/// path already carries a comment about.
///
/// 🚨★★★**IT CHECKS WHAT IT WAS HANDED BEFORE IT READS A BYTE.** The BGRA the
/// reader asks for comes out of a hardware scaler, and a machine without one
/// hands back something else — Codemagic's Mac is a VM (`IOServiceMatching
/// failed for: AppleM2ScalerParavirtDriver`, 2026-09-10). This used to read
/// the STORED size out of whatever arrived: past the end of a smaller or
/// planar buffer, or through a base address that was never mapped. The test
/// process died of a segmentation fault and no sentence anywhere said why.
/// A picture it cannot copy is now an error naming what it was, and the
/// asker gets no frame — the answer every other unreadable frame gives.
static int qa_apple_copy_bgra(CVPixelBufferRef buffer,
                              uint8_t* rgba,
                              char* error,
                              int32_t error_capacity) {
  const int32_t width = g_decode_width;
  const int32_t height = g_decode_height;
  const OSType format = CVPixelBufferGetPixelFormatType(buffer);
  const size_t have_width = CVPixelBufferGetWidth(buffer);
  const size_t have_height = CVPixelBufferGetHeight(buffer);
  if (format != kCVPixelFormatType_32BGRA || CVPixelBufferIsPlanar(buffer) ||
      have_width < (size_t)width || have_height < (size_t)height) {
    char name[16];
    char why[160];
    qa_apple_format_name(format, name, sizeof name);
    snprintf(why, sizeof why,
             "the reader handed back a %s picture of %zux%zu, not the BGRA "
             "%dx%d this copy reads",
             name, have_width, have_height, (int)width, (int)height);
    qa_apple_set_error(error, error_capacity, why);
    return 0;
  }
  if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) !=
      kCVReturnSuccess) {
    qa_apple_set_error(error, error_capacity,
                       "the reader's picture would not lock for reading");
    return 0;
  }
  const uint8_t* base = (const uint8_t*)CVPixelBufferGetBaseAddress(buffer);
  const size_t pitch = CVPixelBufferGetBytesPerRow(buffer);
  if (base == NULL || pitch < (size_t)width * 4) {
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    qa_apple_set_error(error, error_capacity,
                       "the reader's picture has no readable rows");
    return 0;
  }
  for (int32_t y = 0; y < height; y += 1) {
    const uint8_t* row = base + (size_t)y * pitch;
    uint8_t* out = rgba + (size_t)y * (size_t)width * 4;
    for (int32_t x = 0; x < width; x += 1) {
      out[x * 4 + 0] = row[x * 4 + 2];
      out[x * 4 + 1] = row[x * 4 + 1];
      out[x * 4 + 2] = row[x * 4 + 0];
      out[x * 4 + 3] = 255;
    }
  }
  CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
  return 1;
}

/// Walks the reader forward until the picture for [index] is in hand.
///
/// 🚨★★★**FORWARD, NOT A SEEK.** The generator this replaces answered every
/// call with a fresh random access — correct for one frame, quadratic for
/// playback, and the reason 유저 2026-08-31 saw a first play stall on Apple
/// while the other two had stopped flashing. The reader is already standing
/// on the next picture whenever the law asks for it, which is what makes
/// the walk below empty in the common case.
///
/// ⚠️The half-frame slack is [qa_video_decode.c]'s, passed in as
/// [reaches_target]: this file must not grow a second spelling of the rule
/// Media Foundation and MediaCodec already share.
int32_t qa_video_apple_decode_read(int64_t index,
                                   int32_t fps_num,
                                   int32_t fps_den,
                                   uint8_t* rgba,
                                   int32_t capacity,
                                   int32_t (*reaches_target)(int64_t stamp_us,
                                                             int64_t target_us,
                                                             int64_t frame_us),
                                   char* error,
                                   int32_t error_capacity) {
  @autoreleasepool {
    if (g_decode_output == nil || g_decode_reader == nil) {
      qa_apple_set_error(error, error_capacity, "no document is open");
      return 0;
    }
    const int32_t needed = g_decode_width * g_decode_height * 4;
    if (rgba == NULL || capacity < needed || fps_num <= 0 || fps_den <= 0) {
      qa_apple_set_error(error, error_capacity, "frame buffer too small");
      return 0;
    }
    const int64_t frame_us = (1000000LL * (int64_t)fps_den) / (int64_t)fps_num;
    const int64_t target_us =
        (index * 1000000LL * (int64_t)fps_den) / (int64_t)fps_num;

    // The same guard the other two carry: a stream that never reaches the
    // target must end rather than spin.
    for (int guard = 0; guard < 600; guard += 1) {
      CMSampleBufferRef sample = [g_decode_output copyNextSampleBuffer];
      if (sample == NULL) {
        qa_apple_set_error(error, error_capacity,
                           g_decode_reader.status == AVAssetReaderStatusFailed
                               ? "the reader failed mid-stream"
                               : "past the end of the stream");
        return 0;
      }
      const CMTime stamp = CMSampleBufferGetPresentationTimeStamp(sample);
      const int64_t stamp_us =
          CMTIME_IS_NUMERIC(stamp)
              ? (int64_t)(CMTimeGetSeconds(stamp) * 1000000.0 + 0.5)
              : target_us;
      if (!reaches_target(stamp_us, target_us, frame_us)) {
        CFRelease(sample);
        continue;
      }
      CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
      if (pixels == NULL) {
        CFRelease(sample);
        qa_apple_set_error(error, error_capacity,
                           "that frame could not be read");
        return 0;
      }
      const int copied =
          qa_apple_copy_bgra(pixels, rgba, error, error_capacity);
      CFRelease(sample);
      return copied;
    }
    qa_apple_set_error(error, error_capacity, "that frame could not be read");
    return 0;
  }
}
