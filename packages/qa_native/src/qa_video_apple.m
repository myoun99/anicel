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

#include <stdint.h>
#include <string.h>

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
    g_video_input =
        [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                       outputSettings:video_settings];
    g_video_input.expectsMediaDataInRealTime = NO;
    g_adaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc]
        initWithAssetWriterInput:g_video_input
     sourcePixelBufferAttributes:@{
       (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
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
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    uint8_t* base = (uint8_t*)CVPixelBufferGetBaseAddress(pixel_buffer);
    const size_t stride = CVPixelBufferGetBytesPerRow(pixel_buffer);
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
      const uint8_t* in_row =
          rgba + (size_t)y * (size_t)g_apple.src_width * 4;
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
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);

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
// The DECODE half (ABI v27): AVAssetImageGenerator.
//
// The reader half of this file is deliberately NOT AVAssetReader. A reader
// is sequential — it is the right tool for "play this through once" and
// the wrong one for "the picture at frame N", which is the only question
// this app asks. The image generator seeks for us and, with both
// tolerances set to zero, returns the exact frame rather than the nearest
// keyframe. That "exact" is not free (it decodes forward from the keyframe
// internally), and it is the same work the Windows path does by hand.
//
// One document at a time, matching qa_video_decode.c's contract.

static AVAsset* g_decode_asset = nil;
static AVAssetImageGenerator* g_decode_generator = nil;
static int32_t g_decode_width = 0;
static int32_t g_decode_height = 0;
static int32_t g_decode_fps_num = 0;
static int32_t g_decode_fps_den = 0;
static int64_t g_decode_frames = 0;

void qa_video_apple_decode_close(void) {
  g_decode_generator = nil;
  g_decode_asset = nil;
  g_decode_width = 0;
  g_decode_height = 0;
  g_decode_frames = 0;
}

int32_t qa_video_apple_decode_open(const char* utf8_path,
                                   char* error,
                                   int32_t error_capacity) {
  @autoreleasepool {
    qa_video_apple_decode_close();
    if (utf8_path == NULL || utf8_path[0] == '\0') {
      qa_apple_set_error(error, error_capacity, "no path");
      return 0;
    }
    NSString* path = [NSString stringWithUTF8String:utf8_path];
    NSURL* url = [NSURL fileURLWithPath:path];
    AVAsset* asset = [AVAsset assetWithURL:url];
    NSArray<AVAssetTrack*>* tracks =
        [asset tracksWithMediaType:AVMediaTypeVideo];
    if (asset == nil || tracks.count == 0) {
      qa_apple_set_error(error, error_capacity,
                         "this file has no readable video stream");
      return 0;
    }
    AVAssetTrack* track = tracks.firstObject;
    CGSize size = track.naturalSize;
    // The stored size is before the display transform: a phone video
    // recorded upright is 1920x1080 with a 90° rotation, and a decoder
    // that ignores that hands back a sideways picture.
    CGSize display = CGSizeApplyAffineTransform(size, track.preferredTransform);
    g_decode_width = (int32_t)fabs(display.width);
    g_decode_height = (int32_t)fabs(display.height);
    if (g_decode_width <= 0 || g_decode_height <= 0) {
      qa_apple_set_error(error, error_capacity,
                         "the video stream has no frame size");
      return 0;
    }

    float rate = track.nominalFrameRate;
    if (rate <= 0) {
      rate = 24.0f;
    }
    // A fraction, not a float: 30000/1001 is not 29.97, and rounding it is
    // how a frame index drifts a second out over a long take.
    if (fabsf(rate - roundf(rate)) < 0.001f) {
      g_decode_fps_num = (int32_t)roundf(rate);
      g_decode_fps_den = 1;
    } else {
      g_decode_fps_num = (int32_t)roundf(rate * 1001.0f);
      g_decode_fps_den = 1001;
    }

    Float64 seconds = CMTimeGetSeconds(asset.duration);
    if (!isfinite(seconds) || seconds <= 0) {
      seconds = 0;
    }
    g_decode_frames =
        (int64_t)(seconds * (double)g_decode_fps_num / (double)g_decode_fps_den);
    if (g_decode_frames < 1) {
      g_decode_frames = 1;
    }

    AVAssetImageGenerator* generator =
        [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = kCMTimeZero;
    generator.requestedTimeToleranceAfter = kCMTimeZero;
    g_decode_asset = asset;
    g_decode_generator = generator;
    return 1;
  }
}

int32_t qa_video_apple_decode_info(int32_t* width,
                                   int32_t* height,
                                   int64_t* frame_count,
                                   int32_t* fps_num,
                                   int32_t* fps_den) {
  if (g_decode_generator == nil) {
    return 0;
  }
  if (width != NULL) *width = g_decode_width;
  if (height != NULL) *height = g_decode_height;
  if (frame_count != NULL) *frame_count = g_decode_frames;
  if (fps_num != NULL) *fps_num = g_decode_fps_num;
  if (fps_den != NULL) *fps_den = g_decode_fps_den;
  return 1;
}

int32_t qa_video_apple_decode_frame(int64_t index,
                                    uint8_t* rgba,
                                    int32_t capacity,
                                    char* error,
                                    int32_t error_capacity) {
  @autoreleasepool {
    if (g_decode_generator == nil) {
      qa_apple_set_error(error, error_capacity, "no document is open");
      return 0;
    }
    const int32_t needed = g_decode_width * g_decode_height * 4;
    if (rgba == NULL || capacity < needed) {
      qa_apple_set_error(error, error_capacity, "frame buffer too small");
      return 0;
    }
    if (index < 0) {
      index = 0;
    }
    CMTime time = CMTimeMake(index * (int64_t)g_decode_fps_den,
                             g_decode_fps_num);
    NSError* failure = nil;
    CGImageRef image = [g_decode_generator copyCGImageAtTime:time
                                                  actualTime:NULL
                                                       error:&failure];
    if (image == NULL) {
      qa_apple_set_error(
          error, error_capacity,
          failure == nil ? "that frame could not be read"
                         : failure.localizedDescription.UTF8String);
      return 0;
    }

    // Straight into RGBA: a CGBitmapContext converts colour space and
    // component order for us, which is the same job the Windows path does
    // by hand on BGRA rows.
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        rgba, (size_t)g_decode_width, (size_t)g_decode_height, 8,
        (size_t)g_decode_width * 4, space,
        kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (context == NULL) {
      CGImageRelease(image);
      qa_apple_set_error(error, error_capacity, "could not make a bitmap");
      return 0;
    }
    CGContextDrawImage(
        context, CGRectMake(0, 0, g_decode_width, g_decode_height), image);
    CGContextRelease(context);
    CGImageRelease(image);
    // The context skipped alpha; the app's convention is opaque 255.
    for (int32_t i = 0; i < g_decode_width * g_decode_height; i += 1) {
      rgba[i * 4 + 3] = 255;
    }
    return 1;
  }
}
