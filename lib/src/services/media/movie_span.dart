import 'dart:typed_data';

import '../../core/progress_share.dart';
import '../../models/kept_span.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart';
import '../../native/qa_video_encoder.dart';
import '../audio/sound_span.dart'
    show decodeAudioOfFrames, int16PcmBefore, int16PcmOfFrames;
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
/// ([int16PcmOfFrames]), handed to the encoder frame by frame — behind the
/// movie's own sound just before the span, where the writer puts a frame
/// there ([_fillTheLead]).
///
/// Uses the encoder's own budget, as the export does by default.
///
/// Without [withSound] the piece holds the picture alone — a movie that
/// brings its picture and not its sound (🗣️I-171-Q1, 유저 2026-11-14: 「그림만
/// = 소리를 뺀 MP4」).
///
/// With a [pull] the movie is read on [clockPulledBy] it and [trim] counts
/// that clock's frames: the piece is the movie rewritten at the project's
/// speed, its sound pulled with its pictures (🗣️F-588, [framePullOf]).
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
  bool withSound = true,
  ({int numerator, int denominator}) pull = noPull,
  void Function(double fraction)? onProgress,
}) {
  final decoder = QaVideoDecoder.instance;
  final encoder = QaVideoEncoder.instance;
  if (!decoder.isSupported) {
    return (kept: null, failure: 'no video decoder');
  }
  if (!encoder.isSupported) {
    return (kept: null, failure: 'no video encoder');
  }
  final document = decoder.openDocument(sourcePath);
  if (document == null) {
    return (kept: null, failure: decoder.lastError);
  }
  try {
    final info = document.info;
    final read = clockPulledBy(clock, pull);
    final movie = movieClockFor(
      projectRate: read.rate,
      audioSpeed: read.speed,
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
    final sound = withSound
        ? decodeAudioOfFrames(
            MediaFileBytes(sourcePath),
            (first: kept.first, count: kept.count),
            clock,
            pull: pull,
          )
        : null;
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
      if (sound != null &&
          !_fillTheLead(
            encoder,
            MediaFileBytes(sourcePath),
            // Where the span begins in the movie's own sound.
            before: read.rate
                .inSourceTime(read.speed)
                .frameToSample(kept.first, sound.sampleRate),
          )) {
        return (kept: null, failure: encoder.lastError);
      }
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

/// Fills the frame of sound this build's writer puts before a piece's own
/// ([QaVideoEncoder.audioLead]) with what [source] plays just before its
/// sample [before], the span's first — the piece's past, as an exported
/// movie is handed its mix's (`SoundBefore`, video_export_service.dart;
/// 유저 2026-11-10, board an-mp4-reopened-loses-its-first-9-ms-of-sound-Q2:
/// 「무음, 범위 앞에 소리가 있으면 그 소리」).
///
/// The writer's silence stays where the writer puts no frame, or nothing
/// lies before the span. False means the encoder refused what it was
/// handed.
bool _fillTheLead(
  QaVideoEncoder encoder,
  MediaByteSource source, {
  required int before,
}) {
  final samples = encoder.audioLead;
  if (samples == 0) {
    return true;
  }
  final lead = int16PcmBefore(source, before, count: samples);
  return lead == null || encoder.writeLead(lead, samples);
}
