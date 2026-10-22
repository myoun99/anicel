// Media Foundation, started once for the life of the process — see
// qa_win_media_foundation.c. ⚠️One declaration for every caller: the video
// decoder, the video encoder and its HEVC probe, and the audio decoder.

#ifndef QA_WIN_MEDIA_FOUNDATION_H
#define QA_WIN_MEDIA_FOUNDATION_H

#if defined(_WIN32)

/// Whether Media Foundation is running: started by the first call that finds
/// it is not, and never shut down. 0 when it would not start — the next call
/// tries again.
int qa_win_media_foundation_up(void);

#endif  // _WIN32

#endif  // QA_WIN_MEDIA_FOUNDATION_H
