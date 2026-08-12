import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/audio/audio_conform_pipeline.dart';
import '../../services/audio/audio_conform_runner.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/audio/conform_wav_stream.dart';

class _ConformFailure {
  const _ConformFailure({
    required this.reason,
    required this.attempts,
    required this.lastAttemptAt,
  });

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
/// the entry stays, the waveform stays blank, and playback of that file
/// rides the platform players. There is no ffmpeg anywhere behind this —
/// the EXPORT-AUDIO round removed it from every audio path.
class AudioConformStore extends ChangeNotifier {
  AudioConformStore({
    required this.resolveConformPath,
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

  final Map<String, ConformResult> _entries = {};
  final Set<String> _pending = {};
  final Map<String, _ConformFailure> _failures = {};
  bool _disposed = false;

  /// Length past which a conform's PCM stays ON DISK and playback streams
  /// windows of it (AUDIO-PRO R6). Two stereo minutes resident is 23 MB;
  /// a guide dialogue track is easily fifteen times that, which on a
  /// tablet is the whole memory budget. Under the threshold nothing
  /// changes — residency is a policy the mixer never sees.
  static const int streamingThresholdSeconds = 120;

  final Map<String, ConformWavStreamReader> _streamReaders = {};

  /// Whether [sourcePath]'s conform is DISK-BACKED: usable (length, peaks
  /// and the waveform all answer) but with no resident PCM — the
  /// transport streams windows of it instead of uploading the whole file.
  bool isStreaming(String sourcePath) {
    final entry = _entries[sourcePath];
    return entry != null &&
        entry.isUsable &&
        entry.samples == null &&
        entry.conformPath != null;
  }

  /// The windowed reader over [sourcePath]'s conform WAV, cached across
  /// reads; null when the entry is not streaming or the file will not
  /// parse (the caller stands down exactly as for missing PCM).
  ConformWavStreamReader? streamReaderFor(String sourcePath) {
    final entry = _entries[sourcePath];
    if (entry == null || !entry.isUsable || entry.conformPath == null) {
      return null;
    }
    final cached = _streamReaders[sourcePath];
    if (cached != null) {
      return cached;
    }
    final reader = ConformWavStreamReader.open(entry.conformPath!);
    if (reader != null) {
      _streamReaders[sourcePath] = reader;
    }
    return reader;
  }

  void _closeStreamReader(String sourcePath) {
    _streamReaders.remove(sourcePath)?.close();
  }

  /// The conform for [sourcePath]: a usable result, a definitive
  /// `undecodable`, or null while pending/failed (kicking ONE async
  /// conform as a side effect, like [AudioPeaksStore.peaksFor]).
  ConformResult? resultFor(String sourcePath) {
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

  /// The conformed PCM at [sampleRate] — [samplesFor] when the device runs
  /// at the project rate (the common case, bit-exact, no filter), a cached
  /// rate conversion otherwise (WASAPI shared mode owns its own rate and
  /// may refuse the one asked for). A missing conversion is kicked async
  /// and lands with a notify, exactly like a conform: the transport stands
  /// down for THIS run and carries the next one.
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
    final key = '$sampleRate|$sourcePath';
    if (_resamplePending.add(key)) {
      unawaited(_resampleTo(sourcePath, entry!, sampleRate, key));
    }
    return null;
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
      if (_disposed) {
        return;
      }
      (_resampledByRate[sourcePath] ??= {})[sampleRate] = converted;
    } catch (error) {
      if (_disposed) {
        return;
      }
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
  String? failureFor(String sourcePath) => _failures[sourcePath]?.reason;

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

  Future<void> _ensure(String sourcePath) async {
    ConformResult result;
    try {
      final speed = _resolveAudioSpeed();
      result = await _runner(
        ConformRequest(
          sourcePath: sourcePath,
          conformPath: resolveConformPath(sourcePath),
          projectSampleRate: projectSampleRate,
          bucketsPerSecond: bucketsPerSecond,
          speedNumerator: speed.numerator,
          speedDenominator: speed.denominator,
          libraryPathOverride: libraryPathOverride,
        ),
      );
    } catch (error) {
      result = ConformResult(
        outcome: ConformOutcome.writeFailed,
        error: 'unexpected error: $error',
      );
    }
    if (_disposed) {
      return;
    }
    _pending.remove(sourcePath);
    if (result.isUsable || result.outcome == ConformOutcome.undecodable) {
      // Undecodable is an ANSWER (route this format to the fallback), not
      // a retry candidate — the same bytes will not decode differently
      // next time.
      _failures.remove(sourcePath);
      // Past the streaming threshold the PCM is DROPPED here (AUDIO-PRO
      // R6): the conform WAV on disk is the copy of record and playback
      // reads windows of it. Memory-only conforms (unsaved project) have
      // no disk copy to stream from and stay resident.
      var kept = result;
      if (result.isUsable &&
          result.conformPath != null &&
          result.sampleRate > 0 &&
          result.frames > result.sampleRate * streamingThresholdSeconds) {
        kept = ConformResult(
          outcome: result.outcome,
          conformPath: result.conformPath,
          peaks: result.peaks,
          samples: null,
          channels: result.channels,
          sampleRate: result.sampleRate,
          frames: result.frames,
          speedNumerator: result.speedNumerator,
          speedDenominator: result.speedDenominator,
          error: result.error,
        );
      }
      _closeStreamReader(sourcePath);
      _entries[sourcePath] = kept;
    } else if (result.isTransientFailure) {
      // Records the ATTEMPT TIME but not the attempt: a source that is
      // there and merely not readable yet (a cloud placeholder still
      // downloading) must not spend the budget — three of those and the
      // clip renders silent for the rest of the session, in an export,
      // with no error anywhere. Keeping the entry still throttles through
      // `retryDelay`, so "retry forever" costs one attempt per delay
      // rather than one per paint.
      _failures[sourcePath] = _ConformFailure(
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
    _resampledByRate.remove(sourcePath);
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
    for (final reader in _streamReaders.values) {
      reader.close();
    }
    _streamReaders.clear();
    super.dispose();
  }
}
