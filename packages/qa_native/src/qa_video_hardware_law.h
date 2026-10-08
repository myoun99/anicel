// THE HARDWARE LAW — whether a Windows video job may hand its frames to a
// hardware encoder, or stays with the OS's own software H.264.
//
// 🔬Measured 2026-10-08 on a Surface Pro 11 (Intel Core Ultra 7 268V, its
// Arc 140V encoder), card surface-engine-mp4-pieces-fail-to-finalize: the
// hardware H.264 transform ACCEPTS every media type the sink writer offers
// it, then fails a job whose frame has a side of 48 px or less — three
// 16-px macroblocks — with E_FAIL at Finalize (79 bytes on disk, the header
// alone), or at the very first frame when the other side is long
// (1920×48). 50 px and up encode, 1920×1080 included. The software H.264
// transform encodes every one of those sizes; what it cannot take (32 px
// and less) it turns away at SetInputMediaType, before a frame is spent.
// Every engine test that cuts or writes a 64×48 movie was red on that
// machine for this alone.
//
// ⚠️What this does NOT know: other vendors' hardware minimums (nobody has
// measured one). A transform that refuses a size at SetInputMediaType costs
// nothing — the writer falls back to software by itself; the ones this law
// is for are the ones that say yes and fail late.
//
// ⛔Not a speed rule. The same machine encoded 240 frames faster in
// software at every size up to 1920×1080 (1.1 s against 5.2 s at 64×64,
// 3.6 s against 7.6 s at 1920×1080), but which transform a large export
// takes is the export's question, measured on the user's own film — this
// law only keeps the small jobs from a transform that cannot do them.
//
// Pure C with no platform in it: qa_video_encode.c asks it on Windows, and
// qa_video_hardware_law_test.c runs it on every host.

#ifndef QA_VIDEO_HARDWARE_LAW_H
#define QA_VIDEO_HARDWARE_LAW_H

#include <stdint.h>

// The longest side that still failed on the hardware transform above.
#define QA_VIDEO_HARDWARE_FAILED_SIDE 48

// Whether a job of [width]×[height] — the size the encoder is handed, after
// the even pad — may ask for hardware transforms. HEVC always may: Windows
// ships no software HEVC encoder, so without hardware there is no HEVC job.
static int qa_video_hardware_may_encode(int32_t width, int32_t height,
                                        int hevc) {
  if (hevc) {
    return 1;
  }
  return width > QA_VIDEO_HARDWARE_FAILED_SIDE &&
         height > QA_VIDEO_HARDWARE_FAILED_SIDE;
}

#endif
