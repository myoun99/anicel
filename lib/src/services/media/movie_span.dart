import 'dart:typed_data';

import '../../models/kept_span.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart';
import '../../native/qa_video_encoder.dart';
import '../audio/audio_conform_runner.dart' show decodeAudioSource;
import '../audio/sound_span.dart' show int16SamplesOf, sourceSamplesOfFrames;
import 'media_byte_source.dart';

/// Writes the movie at [sourcePath] over the project frames [inFrame] ..
/// [outFrame] (null: to its end) to [piecePath] as an MP4 — the piece a
/// trimmed movie is carried as (유저 2026-09-23: 「잘라낸 동영상으로 다시
/// 인코딩」, and 「비디오든 이미지든 오디오든 관계없이 법 하나로」). Answers
/// the span it kept, or why it could not.
///
/// 🚨★★★**THE FRAMES THE PROJECT SHOWS, AT THE PROJECT'S OWN PACE.** A movie
/// plays on the sound's clock ([MovieClock]), so project frame n shows
/// movie frame `movieFrameAt(n)` — not movie frame n. The piece is those
/// exact pictures, one per project frame, at rate / speed: placed from its
/// start it maps frame n to frame n and shows, frame for frame, what the
/// trimmed original showed. Cut at the movie's own rate instead, its first
/// frame would fall a fraction of a frame from where the span began and a
/// frame here and there would come out one late — on the reference someone
/// is drawing against.
///
/// Its sound is the same span in the source's own time
/// ([sourceSamplesOfFrames]), handed to the encoder frame by frame.
///
/// Uses the encoder's own budget, as the export does by default.
({KeptSpan? kept, String? failure}) writeMovieSpan({
  required String sourcePath,
  required String piecePath,
  required int inFrame,
  int? outFrame,
  required ProjectFrameRate rate,
  required ({int numerator, int denominator}) speed,
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
    final clock = movieClockFor(
      projectRate: rate,
      audioSpeed: speed,
      movie: info,
    );
    // The same span the placement would have kept of the whole movie.
    final kept = KeptSpan(
      length: clock.projectFramesCovering(info.frameCount),
      inFrame: inFrame,
      outFrame: outFrame,
    );
    final pace = _pace(rate, speed);
    final sound = decodeAudioSource(MediaFileBytes(sourcePath));
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
    var finished = false;
    try {
      final frame = Uint8List(info.width * info.height * 4);
      for (var at = kept.first; at <= kept.last; at += 1) {
        final rgba = decoder.frameOf(
          document,
          clock.movieFrameAt(at),
          into: frame,
        );
        if (rgba == null) {
          return (kept: null, failure: decoder.lastError);
        }
        if (!encoder.writeFrame(rgba) ||
            (sound != null &&
                !_writeSoundOf(encoder, sound, at, rate, speed))) {
          return (kept: null, failure: encoder.lastError);
        }
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

/// rate / speed as a reduced fraction — the pace at which the piece's own
/// clock maps project frame n to its frame n.
({int numerator, int denominator}) _pace(
  ProjectFrameRate rate,
  ({int numerator, int denominator}) speed,
) {
  final numerator = rate.numerator * speed.denominator;
  final denominator = rate.denominator * speed.numerator;
  final divisor = numerator.gcd(denominator);
  return (numerator: numerator ~/ divisor, denominator: denominator ~/ divisor);
}

/// The source samples project frame [frame] plays, handed to [encoder].
bool _writeSoundOf(
  QaVideoEncoder encoder,
  ({Float32List samples, int channels, int sampleRate}) sound,
  int frame,
  ProjectFrameRate rate,
  ({int numerator, int denominator}) speed,
) {
  final pcm = int16SamplesOf(
    sound,
    sourceSamplesOfFrames(
      first: frame,
      count: 1,
      rate: rate,
      speed: speed,
      sampleRate: sound.sampleRate,
    ),
  );
  return pcm.isEmpty || encoder.writeAudio(pcm, pcm.length ~/ sound.channels);
}
