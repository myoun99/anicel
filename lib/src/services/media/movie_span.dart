import 'dart:typed_data';

import '../../core/progress_share.dart';
import '../../models/kept_span.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart';
import '../../native/qa_video_encoder.dart';
import '../audio/sound_span.dart' show decodeAudioOfFrames, int16PcmOfFrames;
import 'media_byte_source.dart';

/// Writes the movie at [sourcePath] over the project frames [trim] keeps of
/// it to [piecePath] as an MP4 — the piece a trimmed movie is carried as
/// (유저 2026-09-23: 「잘라낸 동영상으로 다시 인코딩」, and 「비디오든
/// 이미지든 오디오든 관계없이 법 하나로」). Answers the span it kept, or why
/// it could not.
///
/// 🚨★★★**THE FRAMES THE PROJECT SHOWS, AT THE PROJECT'S OWN PACE.** A movie
/// plays on the sound's clock ([MovieClock]), so project frame n shows
/// movie frame `movieFrameAt(n)` — not movie frame n. The piece is those
/// exact pictures, one per project frame, at the project's rate in the
/// movie's own time ([ProjectFrameRate.inSourceTime]): placed from its
/// start it maps frame n to frame n and shows, frame for frame, what the
/// trimmed original showed. Cut at the movie's own rate instead, its first
/// frame would fall a fraction of a frame from where the span began and a
/// frame here and there would come out one late — on the reference someone
/// is drawing against.
///
/// Its sound is the same span in the source's own time
/// ([int16PcmOfFrames]), handed to the encoder frame by frame.
///
/// Uses the encoder's own budget, as the export does by default.
///
/// [onProgress] hears the frames written, as 0–1 — the work there is
/// (🔬F-494, 2026-10-28: two minutes of a 3.4GB 1080p movie took 61 s here,
/// 55 of them this loop, the decode and the encode half each; reading the
/// span's sound before it, 5).
({KeptSpan? kept, String? failure}) writeMovieSpan(
  String sourcePath,
  String piecePath, {
  required ({int inFrame, int? outFrame}) trim,
  required ProjectClock clock,
  void Function(double fraction)? onProgress,
}) {
  final decoder = QaVideoDecoder.instance;
  final encoder = QaVideoEncoder.instance;
  if (decoder == null || !decoder.isSupported) {
    return (kept: null, failure: 'no video decoder');
  }
  if (encoder == null || !encoder.isSupported) {
    return (kept: null, failure: 'no video encoder');
  }
  final document = decoder.openDocument(sourcePath);
  if (document == null) {
    return (kept: null, failure: decoder.lastError);
  }
  try {
    final info = document.info;
    final movie = movieClockFor(
      projectRate: clock.rate,
      audioSpeed: clock.speed,
      movie: info,
    );
    // The same span the placement would have kept of the whole movie.
    final kept = KeptSpan(
      length: movie.projectFramesCovering(info.frameCount),
      inFrame: trim.inFrame,
      outFrame: trim.outFrame,
    );
    final pace = clock.rate.inSourceTime(clock.speed);
    // Only the span's own samples: a minute cut from a two-hour reel holds
    // a minute (Q5).
    final sound = decodeAudioOfFrames(
      MediaFileBytes(sourcePath),
      (first: kept.first, count: kept.count),
      pace,
    );
    if (!encoder.open(
      path: piecePath,
      width: info.width,
      height: info.height,
      fpsNumerator: pace.numerator,
      fpsDenominator: pace.denominator,
      sampleRate: sound?.sampleRate ?? 0,
      channels: sound?.channels ?? 0,
    )) {
      return (kept: null, failure: encoder.lastError);
    }
    // The source samples project frame [at] plays, handed to the encoder —
    // the sound was decoded from the span's first frame on.
    bool writeSoundOf(int at) {
      final heard = sound;
      if (heard == null) {
        return true;
      }
      final pcm = int16PcmOfFrames(
        heard,
        (first: at, count: 1),
        pace,
        from: kept.first,
      );
      return encoder.writeAudio(pcm, pcm.length ~/ heard.channels);
    }

    var finished = false;
    try {
      final frame = Uint8List(info.width * info.height * 4);
      for (var at = kept.first; at <= kept.last; at += 1) {
        final rgba = decoder.frameOf(
          document,
          movie.movieFrameAt(at),
          into: frame,
        );
        if (rgba == null) {
          return (kept: null, failure: decoder.lastError);
        }
        if (!encoder.writeFrame(rgba) || !writeSoundOf(at)) {
          return (kept: null, failure: encoder.lastError);
        }
        onProgress?.call(doneShare(at - kept.first + 1, kept.count));
      }
      finished = encoder.finish();
      return finished
          ? (kept: kept, failure: null)
          : (kept: null, failure: encoder.lastError);
    } finally {
      if (!finished) {
        encoder.abort();
      }
    }
  } finally {
    decoder.closeDocument(document);
  }
}
