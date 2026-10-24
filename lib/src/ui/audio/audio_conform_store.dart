import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/media_asset.dart' show MediaCarry;
import '../../services/audio/audio_conform_pipeline.dart';
import '../../services/audio/audio_conform_runner.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../../services/media/media_byte_source.dart';
import 'sound_cannot_play.dart';

class _ConformFailure {
  const _ConformFailure({
    required this.outcome,
    required this.reason,
    required this.attempts,
    required this.lastAttemptAt,
  });

  /// Which failure it was — what [AudioConformStore.cannotPlayAt] tells
  /// the screen.
  final ConformOutcome outcome;
  final String reason;
  final int attempts;
  final DateTime lastAttemptAt;
}

/// Session-level cache of CONFORMED audio per source path — the waveform's
/// peaks, the device transport's PCM, and the clip-length answer, all from
/// the same decode.
///
/// [resultFor] resolves synchronously (null while absent) and kicks ONE
/// async conform per path; listeners are notified when a result lands.
/// Failures are remembered with a retry budget — transient ones (a file
/// still syncing down from a cloud folder) self-heal, and a hard one
/// cannot spin the paint loop.
///
/// A format the decoder chain does not read (dr_libs + stb_vorbis + the
/// OS codec stack) is a DEFINITIVE `undecodable` answer, not a failure:
/// the entry stays, the waveform stays blank, and a run plays without that
/// file, saying so (`OutputArmed.cannotPlay`). ↩️Its playback rode the
/// platform players (playback-waits-for-its-sound, 유저 2026-10-16: 「대체
/// 재생을 안 쓰고」). There is no ffmpeg anywhere behind this — the
/// EXPORT-AUDIO round removed it from every audio path.
class AudioConformStore extends ChangeNotifier {
  AudioConformStore({
    required this.resolveConformPath,
    this.resolveByteSource,
    this.resolveCarriedConform,
    this.resolveCarry,
    ConformRunner? runner,
    ResampleRunner? resampleRunner,
    int Function()? resolveProjectSampleRate,
    int projectSampleRate = 48000,
    ({int numerator, int denominator}) Function()? resolveAudioSpeed,
    this.bucketsPerSecond = 80,
    DateTime Function()? now,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
    void Function(String message)? log,
    this.libraryPathOverride,
    this.placeForPlayback,
  }) : _runner = runner ?? runConformInIsolate,
       _resampleRunner = resampleRunner ?? runResampleInIsolate,
       _resolveProjectSampleRate =
           resolveProjectSampleRate ?? (() => projectSampleRate),
       _resolveAudioSpeed =
           resolveAudioSpeed ?? (() => (numerator: 1, denominator: 1)),
       _now = now ?? DateTime.now,
       _log = log ?? debugPrint;

  /// Where [sourcePath]'s conform lives, or null for memory-only (no
  /// project file yet). Injected rather than computed here because only
  /// the session knows the current `.anicel` path.
  final String? Function(String sourcePath) resolveConformPath;

  /// Where [sourcePath]'s BYTES are right now — an archive range for
  /// media the project carries, so a deleted import original no longer
  /// silences the clip. Injected for the same reason as
  /// [resolveConformPath]: only the session knows the entry names and the
  /// archive path. Null (tests, passive hosts) reads the file at the
  /// path, exactly as before. Resolved per REQUEST, never held — offsets
  /// belong to one layout and a compaction moves them.
  final MediaByteSource Function(String sourcePath)? resolveByteSource;

  /// The conform the PROJECT carries for [sourcePath], when it has one —
  /// a range inside the `.anicel`. Injected for the same reason as the two
  /// above: only the session knows the archive path and its layout.
  ///
  /// Resolved per REQUEST, never held: a compaction moves every byte, and
  /// a range kept from before would read whatever landed on those offsets.
  final MediaByteSource? Function(String sourcePath)? resolveCarriedConform;

  /// Which carry the pool names at [sourcePath] now — what a conform is OF
  /// (`ProjectFile.mediaCarryFor`). Injected like the resolvers above; null
  /// (tests, passive hosts) keys nothing by it.
  ///
  /// 🚨★★★**A CONFORM IS OF ONE CARRY'S BYTES, NOT OF A PATH.** Removed from
  /// the pool and carried again with the original edited in between, a path
  /// means other bytes — and an undo can bring the first ones back. Kept by
  /// the path alone, the first carry's conform answered for the second: the
  /// waveform and the playback were the old sound (card
  /// `recarry-after-remove-reads-the-old`). The carry a conform was made OF
  /// is kept beside it ([_conformedAs]), and one the pool no longer names is
  /// stale at the next lookup — self-healing, like a rate or a speed that
  /// moved, rather than hooked into the history stack.
  final MediaCarry? Function(String sourcePath)? resolveCarry;

  final ConformRunner _runner;
  final ResampleRunner _resampleRunner;

  /// The PROJECT's audio rate, read live (EXPORT-AUDIO ③ made it a
  /// project setting; a fixed int remains as the test-friendly default).
  final int Function() _resolveProjectSampleRate;

  int get projectSampleRate => _resolveProjectSampleRate();

  /// The project's audio speed, read live (EXPORT-AUDIO ④'s NTSC pull).
  final ({int numerator, int denominator}) Function() _resolveAudioSpeed;

  final int bucketsPerSecond;
  final DateTime Function() _now;
  final void Function(String message) _log;
  final int maxAttempts;
  final Duration retryDelay;

  /// Test hook, forwarded into every request (worker isolates start with
  /// fresh statics).
  final String? libraryPathOverride;

  /// [floats] samples in the memory the output device plays where they lie
  /// (`QaAudioDevice.newSamples`), or null to keep them in Dart's — no
  /// device, or none wanted.
  ///
  /// 🚨THE PCM THE DEVICE PLAYS LIVES IN THE DEVICE FROM THE MOMENT IT LANDS
  /// (play-press-first-frame-stall, 10-15). A conform's samples, and each
  /// rate they were converted to, are placed there ONCE, and every schedule
  /// after names them without a copy. ↩️They stayed in Dart memory, and
  /// every upload — each press, seek and streaming advance — copied every
  /// resident sound into the device again, however many takes a project
  /// had.
  final Float32List? Function(int floats)? placeForPlayback;

  /// [samples] where the device plays them ([placeForPlayback]).
  Float32List _placedForPlayback(Float32List samples) {
    final placed = placeForPlayback?.call(samples.length);
    if (placed == null) {
      return samples;
    }
    placed.setAll(0, samples);
    return placed;
  }

  final Map<String, ConformResult> _entries = {};
  final Set<String> _pending = {};
  final Map<String, _ConformFailure> _failures = {};
  bool _disposed = false;

  /// The carry each path's entry — or failure — was made OF ([resolveCarry]).
  final Map<String, MediaCarry?> _conformedAs = {};

  /// Lets go of what [sourcePath] holds when the pool names another carry
  /// there than the one it was made of ([resolveCarry]) — asked first by
  /// every reader of an entry, so none of them answers for other bytes.
  void _dropIfTheCarryMoved(String sourcePath) {
    if (_conformedAs.containsKey(sourcePath) &&
        _conformedAs[sourcePath] != resolveCarry?.call(sourcePath)) {
      invalidate(sourcePath);
    }
  }

  final Map<String, ConformPcmStreamReader> _streamReaders = {};

  /// Whether [sourcePath]'s conform is DISK-BACKED: usable (length, peaks
  /// and the waveform all answer) but with no resident PCM — the
  /// transport streams windows of it instead of uploading the whole file.
  bool isStreaming(String sourcePath) {
    _dropIfTheCarryMoved(sourcePath);
    final entry = _entries[sourcePath];
    return entry != null &&
        entry.isUsable &&
        entry.samples == null &&
        entry.conformBytes != null;
  }

  /// The windowed reader over [sourcePath]'s conform, cached across reads;
  /// null when the entry is not streaming or the bytes will not parse (the
  /// upload leaves its clips out, as for a source that will never be ready —
  /// `WindowedUploadPlan.cannotPlay`).
  ///
  /// ⚠️「The conform」 is wherever its bytes are — a file in the run's
  /// scratch before the project has been saved, a range inside the
  /// `.anicel` after. The reader takes a [MediaByteSource] for exactly
  /// that reason, so nothing here has to know which.
  ConformPcmStreamReader? streamReaderFor(String sourcePath) {
    _dropIfTheCarryMoved(sourcePath);
    final entry = _entries[sourcePath];
    if (entry == null || !entry.isUsable || entry.conformBytes == null) {
      return null;
    }
    final cached = _streamReaders[sourcePath];
    if (cached != null) {
      return cached;
    }
    final reader = ConformPcmStreamReader.over(entry.conformBytes!);
    if (reader != null) {
      _streamReaders[sourcePath] = reader;
    }
    return reader;
  }

  void _closeStreamReader(String sourcePath) {
    _streamReaders.remove(sourcePath);
  }

  /// The conform for [sourcePath]: a usable result, a definitive
  /// `undecodable`, or null while pending/failed (kicking ONE async
  /// conform as a side effect, like [AudioPeaksStore.peaksFor]).
  ConformResult? resultFor(String sourcePath) {
    _dropIfTheCarryMoved(sourcePath);
    final cached = _entries[sourcePath];
    if (cached != null) {
      final speed = _resolveAudioSpeed();
      if (cached.isUsable &&
          (cached.sampleRate != projectSampleRate ||
              cached.speedNumerator != speed.numerator ||
              cached.speedDenominator != speed.denominator)) {
        // The project rate or speed moved under this entry (a setting
        // change, or an undo of one): stale by definition, re-conform.
        // Self-healing here rather than hooked into the history stack.
        _entries.remove(sourcePath);
        _resampledByRate.remove(sourcePath);
      } else {
        return cached;
      }
    }
    if (_pending.contains(sourcePath)) {
      return null;
    }
    final failure = _failures[sourcePath];
    if (failure != null &&
        (failure.attempts >= maxAttempts ||
            _now().difference(failure.lastAttemptAt) < retryDelay)) {
      return null;
    }
    _pending.add(sourcePath);
    unawaited(_ensure(sourcePath));
    return null;
  }

  /// The waveform for [sourcePath], computed from the conformed PCM.
  AudioPeaks? peaksFor(String sourcePath) {
    final entry = resultFor(sourcePath);
    return entry != null && entry.isUsable ? entry.peaks : null;
  }

  /// The clip length in seconds — an EXACT sample count over the rate.
  double? durationSecondsFor(String sourcePath) {
    final entry = resultFor(sourcePath);
    return entry != null && entry.isUsable && entry.sampleRate > 0
        ? entry.frames / entry.sampleRate
        : null;
  }

  /// The conformed PCM (interleaved float32 at [projectSampleRate]), or
  /// null while absent/unusable — what the device transport uploads.
  Float32List? samplesFor(String sourcePath) {
    final entry = resultFor(sourcePath);
    return entry != null && entry.isUsable ? entry.samples : null;
  }

  final Map<String, Map<int, Float32List>> _resampledByRate = {};
  final Set<String> _resamplePending = {};

  /// The rates [_resampleTo] could not convert a path to — not kicked again
  /// for the session, as a conform that spent its attempts is not: a run
  /// that waits for its sound ([isLanding]) would otherwise wait on a
  /// conversion failing again at every landing. [invalidate] forgets them.
  final Map<String, Set<int>> _conversionsThatFailed = {};

  String _resampleKey(String sourcePath, int sampleRate) =>
      '$sampleRate|$sourcePath';

  /// The conformed PCM at [sampleRate] — [samplesFor] when the device runs
  /// at the project rate (the common case, bit-exact, no filter), a cached
  /// rate conversion otherwise (WASAPI shared mode owns its own rate and
  /// may refuse the one asked for). A missing conversion is kicked async
  /// and lands with a notify, exactly like a conform — what a run that
  /// waits for its sound waits on ([isLanding]).
  Float32List? samplesAtRate(String sourcePath, int sampleRate) {
    if (sampleRate == projectSampleRate) {
      return samplesFor(sourcePath);
    }
    final entry = resultFor(sourcePath);
    final samples = entry != null && entry.isUsable ? entry.samples : null;
    if (samples == null) {
      return null;
    }
    final cached = _resampledByRate[sourcePath]?[sampleRate];
    if (cached != null) {
      return cached;
    }
    if (_conversionsThatFailed[sourcePath]?.contains(sampleRate) ?? false) {
      return null;
    }
    final key = _resampleKey(sourcePath, sampleRate);
    if (_resamplePending.add(key)) {
      unawaited(_resampleTo(sourcePath, entry!, sampleRate, key));
    }
    return null;
  }

  /// Whether [sourcePath] is on its way to being played at [sampleRate]:
  /// its conform, or its conversion to that rate, under way — and it will
  /// say so when it lands (a notify).
  ///
  /// 🚨What a run that waits for its sound waits on
  /// (playback-waits-for-its-sound, 유저 2026-10-16: 「소리가 준비될 때까지
  /// 기다린다」). A path with nothing under way is not coming — a failure,
  /// an undecodable file, a source not readable yet inside its retry delay
  /// — and the run plays without it.
  bool isLanding(String sourcePath, int sampleRate) =>
      _pending.contains(sourcePath) ||
      _resamplePending.contains(_resampleKey(sourcePath, sampleRate));

  /// Why [sourcePath] cannot be played at [sampleRate] — null while it can,
  /// and while it is on its way ([isLanding]). Like [resultFor] it kicks
  /// what it finds missing: the conform, or the conversion to the rate.
  ///
  /// 🚨THE ONE PLACE a run (`planWindowedMixUpload`) and the screen (a
  /// sound's cell, playback-says-the-sound-it-cannot-play) ask, so a cell is
  /// red for exactly the sounds a run plays without. ↩️The run's two plans
  /// each decided it in a branch of their own and kept only the path.
  ///
  /// A streamed conform is project-rate PCM read in windows, so a device
  /// off the project's rate cannot play it: resampling windows on the fly
  /// would buy that rare case with a permanent cost, and an arm opens such
  /// a device again at the project's rate before it plans
  /// (`armAudioOutput`).
  SoundCannotPlay? cannotPlayAt(String sourcePath, int sampleRate) {
    if (isStreaming(sourcePath)) {
      if (sampleRate != projectSampleRate) {
        return SoundCannotPlay.deviceRate;
      }
      return streamReaderFor(sourcePath) == null
          ? SoundCannotPlay.conform
          : null;
    }
    if (samplesAtRate(sourcePath, sampleRate) != null ||
        isLanding(sourcePath, sampleRate)) {
      return null;
    }
    // Only a usable conform or an undecodable answer is kept as an entry.
    final entry = _entries[sourcePath];
    if (entry != null) {
      return entry.isUsable
          ? SoundCannotPlay.deviceRate
          : SoundCannotPlay.format;
    }
    return switch (_failures[sourcePath]?.outcome) {
      ConformOutcome.sourceMissing => SoundCannotPlay.missing,
      ConformOutcome.sourceUnreadable => SoundCannotPlay.notReadYet,
      _ => SoundCannotPlay.conform,
    };
  }

  Future<void> _resampleTo(
    String sourcePath,
    ConformResult entry,
    int sampleRate,
    String pendingKey,
  ) async {
    try {
      final converted = await _resampleRunner(
        ResampleRequest(
          samples: entry.samples!,
          channels: entry.channels,
          inputRate: entry.sampleRate,
          outputRate: sampleRate,
          libraryPathOverride: libraryPathOverride,
        ),
      );
      // Onto the entry it was made FROM, or nowhere: one let go of while
      // this ran — another carry, a rate that moved — would otherwise get
      // the old sound back at the device rate.
      if (_disposed || !identical(_entries[sourcePath], entry)) {
        return;
      }
      (_resampledByRate[sourcePath] ??= {})[sampleRate] = _placedForPlayback(
        converted,
      );
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      (_conversionsThatFailed[sourcePath] ??= {}).add(sampleRate);
      _log(
        '[AudioConformStore] device-rate conversion failed for '
        '$sourcePath → ${sampleRate}Hz: $error',
      );
    } finally {
      if (!_disposed) {
        _resamplePending.remove(pendingKey);
        notifyListeners();
      }
    }
  }

  /// The last failure reason, or null while unknown/pending/usable.
  String? failureFor(String sourcePath) {
    _dropIfTheCarryMoved(sourcePath);
    return _failures[sourcePath]?.reason;
  }

  /// Awaits [sourcePath]'s conform: the cached result, or the in-flight
  /// one when it lands. Null once the attempt budget is spent — the export
  /// path uses this to render what it can instead of hanging on a file
  /// that will never decode.
  Future<ConformResult?> ensureFor(String sourcePath) async {
    while (true) {
      final entry = resultFor(sourcePath);
      if (entry != null) {
        return entry;
      }
      final failure = _failures[sourcePath];
      if (failure != null && failure.attempts >= maxAttempts) {
        return null;
      }
      if (!_pending.contains(sourcePath) && failure != null) {
        // Inside the retry delay: the budget remains but nothing is in
        // flight and resultFor will not kick until the delay passes.
        // Waiting out a wall-clock delay is playback's concern, not an
        // export render's — give the answer we have.
        return null;
      }
      final landed = Completer<void>();
      void onChanged() {
        if (!landed.isCompleted) {
          landed.complete();
        }
      }

      addListener(onChanged);
      try {
        await landed.future;
      } finally {
        removeListener(onChanged);
      }
    }
  }

  /// Awaits the peaks of [sourcePath] — its length and its picture:
  /// [ensureFor], then the waveform when the conform is usable; null when
  /// it never will be. The one wait for everything that shows or measures
  /// a sound before it plays: the media viewer's page, the import window's
  /// preview, and a sound's placement.
  Future<AudioPeaks?> ensurePeaksFor(String sourcePath) async {
    final result = await ensureFor(sourcePath);
    return result != null && result.isUsable ? result.peaks : null;
  }

  Future<void> _ensure(String sourcePath) async {
    // The carry the bytes below are resolved as — read in the same breath.
    final carry = resolveCarry?.call(sourcePath);
    ConformResult result;
    try {
      final speed = _resolveAudioSpeed();
      result = await _runner(
        ConformRequest(
          sourcePath: sourcePath,
          conformPath: resolveConformPath(sourcePath),
          source: resolveByteSource?.call(sourcePath),
          carriedConform: resolveCarriedConform?.call(sourcePath),
          projectSampleRate: projectSampleRate,
          bucketsPerSecond: bucketsPerSecond,
          speedNumerator: speed.numerator,
          speedDenominator: speed.denominator,
          libraryPathOverride: libraryPathOverride,
        ),
      );
    } on Object catch (error) {
      result = ConformResult(
        outcome: ConformOutcome.writeFailed,
        error: 'unexpected error: $error',
      );
    }
    if (_disposed) {
      return;
    }
    _pending.remove(sourcePath);
    // Whatever lands below — an entry or a failure — is of THIS carry. One
    // the pool has moved off since is dropped at the next lookup.
    _conformedAs[sourcePath] = carry;
    if (result.isUsable || result.outcome == ConformOutcome.undecodable) {
      // Undecodable is an ANSWER (a run plays without it; ↩️it routed this
      // format to the fallback), not a retry candidate — the same bytes
      // will not decode differently next time.
      _failures.remove(sourcePath);
      // A conform past the streaming threshold comes with NO PCM (AUDIO-PRO
      // R6): the conform on disk is the copy of record and playback reads
      // windows of it — out of the run's scratch, or out of the project
      // file once a save has absorbed it. 🪦It was dropped HERE, after the
      // worker had held it whole and carried it across; the pipeline now
      // decides before it holds any ([conformStaysOnDisk]), and the store
      // keeps what it is given.
      _closeStreamReader(sourcePath);
      final samples = result.samples;
      _entries[sourcePath] = samples == null
          ? result
          : result.withSamples(_placedForPlayback(samples));
    } else if (result.isTransientFailure) {
      // Records the ATTEMPT TIME but not the attempt: a source that is
      // there and merely not readable yet (a cloud placeholder still
      // downloading) must not spend the budget — three of those and the
      // clip renders silent for the rest of the session, in an export,
      // with no error anywhere. Keeping the entry still throttles through
      // `retryDelay`, so "retry forever" costs one attempt per delay
      // rather than one per paint.
      _failures[sourcePath] = _ConformFailure(
        outcome: result.outcome,
        reason: result.error ?? 'source not readable yet',
        attempts: _failures[sourcePath]?.attempts ?? 0,
        lastAttemptAt: _now(),
      );
      _log(
        '[AudioConformStore] conform deferred for $sourcePath: ${result.error}',
      );
    } else {
      final attempts = (_failures[sourcePath]?.attempts ?? 0) + 1;
      _failures[sourcePath] = _ConformFailure(
        outcome: result.outcome,
        reason: result.error ?? 'unknown failure',
        attempts: attempts,
        lastAttemptAt: _now(),
      );
      _log(
        '[AudioConformStore] conform failed '
        '(attempt $attempts/$maxAttempts) for $sourcePath: ${result.error}',
      );
    }
    notifyListeners();
  }

  /// Forgets a path (re-import, relink, the file changed on disk) so the
  /// next lookup conforms again with a fresh attempt budget.
  void invalidate(String sourcePath) {
    _entries.remove(sourcePath);
    _failures.remove(sourcePath);
    _conformedAs.remove(sourcePath);
    _resampledByRate.remove(sourcePath);
    _conversionsThatFailed.remove(sourcePath);
    _closeStreamReader(sourcePath);
  }

  /// Kicks a conform for every path that has none yet — called on project
  /// open so waveforms and playback PCM are ready before the first play.
  void warmPaths(Iterable<String> sourcePaths) {
    for (final path in sourcePaths) {
      resultFor(path);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _streamReaders.clear();
    super.dispose();
  }
}
