import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/on_a_worker.dart';
import '../../models/media_asset.dart' show MediaCarry;
import '../../models/project_frame_rate.dart' show noPull;
import '../../services/audio/audio_conform_pipeline.dart';
import '../../services/audio/audio_conform_runner.dart';
import '../../services/audio/audio_equalizer.dart' show EqualizedSpan;
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../../services/audio/equalized_stream.dart';
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
/// A format the decoder chain does not read (the bundled decoders + the
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
    EqualizeRunner? equalizeRunner,
    int Function()? resolveProjectSampleRate,
    int projectSampleRate = 48000,
    ({int numerator, int denominator}) Function()? resolveAudioSpeed,
    this.bucketsPerSecond = 80,
    DateTime Function()? now,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
    void Function(String message)? log,
  }) : _runner = runner ?? runConformInIsolate,
       _resampleRunner = resampleRunner ?? runResampleInIsolate,
       _equalizeRunner = equalizeRunner ?? runEqualizeInIsolate,
       _resolveProjectSampleRate =
           resolveProjectSampleRate ?? (() => projectSampleRate),
       _resolveAudioSpeed =
           resolveAudioSpeed ?? (() => noPull),
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
  final EqualizeRunner _equalizeRunner;

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

  /// A store that conforms each path's FILE as it lies — no carry, no
  /// conform of the project's, nothing kept on disk — at this one's rate
  /// and speed, through its runners: what the import window plays a file
  /// from while the pool carries other bytes at its path (F-550-Q3).
  AudioConformStore ofTheFilesThemselves() => AudioConformStore(
    resolveConformPath: (_) => null,
    runner: _runner,
    resampleRunner: _resampleRunner,
    equalizeRunner: _equalizeRunner,
    resolveProjectSampleRate: _resolveProjectSampleRate,
    resolveAudioSpeed: _resolveAudioSpeed,
    bucketsPerSecond: bucketsPerSecond,
    now: _now,
    maxAttempts: maxAttempts,
    retryDelay: retryDelay,
    log: _log,
  );

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
        _derived.letGoOfWhatWasMade(sourcePath);
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

  /// What is made of the conforms here — conversions, bakes, checkpoints —
  /// kept beside them and let go of with them ([_DerivedSound]).
  late final _derived = _DerivedSound(this);

  /// The listeners told that a result made of a conform landed.
  void _landed() => notifyListeners();

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
    return entry != null && entry.isUsable && entry.samples != null
        ? _derived.convertedTo(sourcePath, entry, sampleRate)
        : null;
  }

  /// Whether [sourcePath] is on its way to being played at [sampleRate]:
  /// its conform, its conversion to that rate, or a span of it baked
  /// through its equalizer ([equalizedAt]) under way — and it will
  /// say so when it lands (a notify).
  ///
  /// 🚨What a run that waits for its sound waits on
  /// (playback-waits-for-its-sound, 유저 2026-10-16: 「소리가 준비될 때까지
  /// 기다린다」). A path with nothing under way is not coming — a failure,
  /// an undecodable file, a source not readable yet inside its retry delay
  /// — and the run plays without it.
  bool isLanding(String sourcePath, int sampleRate) =>
      _pending.contains(sourcePath) ||
      _derived.isLanding(sourcePath, sampleRate);

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
  ///
  /// [equalized]: the span of it a run plays, baked through its equalizer
  /// ([equalizedAt]) — the bake under way, or failed, in place of the
  /// conform's samples.
  SoundCannotPlay? cannotPlayAt(
    String sourcePath,
    int sampleRate, {
    EqualizedSpan? equalized,
  }) {
    if (isStreaming(sourcePath)) {
      if (sampleRate != projectSampleRate) {
        return SoundCannotPlay.deviceRate;
      }
      if (streamReaderFor(sourcePath) == null) {
        return SoundCannotPlay.conform;
      }
      return equalized == null
          ? null
          : _bakedOrComing(
              sourcePath,
              sampleRate,
              equalizerCheckpointsFor(sourcePath, equalized),
            );
    }
    final samples = samplesAtRate(sourcePath, sampleRate);
    if (samples != null && equalized != null) {
      return _bakedOrComing(
        sourcePath,
        sampleRate,
        equalizedAt(sourcePath, sampleRate, equalized),
      );
    }
    if (samples != null || isLanding(sourcePath, sampleRate)) {
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

  /// A span plays its bake or not at all: null while [baked] is there or
  /// on its way ([isLanding]).
  SoundCannotPlay? _bakedOrComing(
    String sourcePath,
    int sampleRate,
    Object? baked,
  ) => baked != null || isLanding(sourcePath, sampleRate)
      ? null
      : SoundCannotPlay.conform;

  /// [sourcePath]'s [span] through its equalizer, at [sampleRate] — baked
  /// ONCE from the span's first sample, whatever part of it a run or an
  /// export plays (board audio-fx-grows-like-the-pros ③), and read by both.
  /// A missing bake is kicked async and lands with a notify, as a rate
  /// conversion does — what a run that waits for its sound waits on
  /// ([isLanding]).
  ///
  /// The span is cut from the samples the device plays at [sampleRate]
  /// ([samplesAtRate]), so a device off the project's rate bakes from the
  /// conversion — null while that is landing.
  Float32List? equalizedAt(
    String sourcePath,
    int sampleRate,
    EqualizedSpan span,
  ) => _derived.bakedAt(sourcePath, sampleRate, span);

  /// [sourcePath]'s [span] through its equalizer where its conform streams
  /// ([isStreaming]): the checkpoints its windows are baked on from
  /// ([readEqualizedWindow]), made once by a pass over the span on a worker
  /// — kicked and landing as [equalizedAt]'s bake does, for a run to wait
  /// on ([isLanding]).
  EqualizerCheckpoints? equalizerCheckpointsFor(
    String sourcePath,
    EqualizedSpan span,
  ) => _derived.checkpointsFor(sourcePath, span);

  /// Awaits [sourcePath]'s [span] baked at [sampleRate]: the bake, or null
  /// once it is not coming — no conform, or a bake that failed. What an
  /// export mixes an equalized span from: the same bake playback reads.
  Future<Float32List?> ensureEqualizedFor(
    String sourcePath,
    int sampleRate,
    EqualizedSpan span,
  ) async => await ensureFor(sourcePath) == null
      ? null
      : _onceLanded(
          sourcePath,
          sampleRate,
          () => equalizedAt(sourcePath, sampleRate, span),
        );

  /// Awaits a streamed [span]'s checkpoints ([equalizerCheckpointsFor]), or
  /// null once they are not coming — what an export streams an equalized
  /// long span through: the checkpoints playback's windows are baked from.
  Future<EqualizerCheckpoints?> ensureEqualizerCheckpointsFor(
    String sourcePath,
    EqualizedSpan span,
  ) async => await ensureFor(sourcePath) == null
      ? null
      : _onceLanded(
          sourcePath,
          projectSampleRate,
          () => equalizerCheckpointsFor(sourcePath, span),
        );

  /// What [look] finds, as soon as it finds it — or once nothing of
  /// [sourcePath] at [sampleRate] is on its way ([isLanding]) to be found.
  Future<T?> _onceLanded<T>(
    String sourcePath,
    int sampleRate,
    T? Function() look,
  ) async {
    while (true) {
      final found = look();
      if (found != null || !isLanding(sourcePath, sampleRate)) {
        return found;
      }
      await _aNotify();
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
      await _aNotify();
    }
  }

  /// The next notify — whatever landed: what [ensureFor] and
  /// [_onceLanded] wait on between their looks.
  Future<void> _aNotify() async {
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
      // Kept as it came: its PCM is where the device plays it already
      // (`conformingInto`).
      _entries[sourcePath] = result;
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
    _derived.forget(sourcePath);
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

/// Where a result made of a conform goes as it lands ([_DerivedSound._land]):
/// [keep] keeps it, [failed] remembers a failure and [saying] says it, and
/// [settled] lets go of it as under way.
typedef _Landing<T> = ({
  void Function(T made) keep,
  void Function() failed,
  String Function(Object error) saying,
  void Function() settled,
});

/// What [AudioConformStore] makes of its conforms, kept beside them and
/// let go of with them: each conversion to a device's rate, each span
/// baked through its equalizer, each long span's checkpoints.
///
/// 🚨PART OF THE STORE, NOT A STORE OF ITS OWN: it reads the conforms the
/// store holds and tells the store's listeners as each result lands. Split
/// from it when the equalizer's bakes and checkpoints came to sit beside
/// the conversions (board audio-fx-grows-like-the-pros ③, 11-17) and the
/// three made one landing ([_land]).
final class _DerivedSound {
  _DerivedSound(this._store);

  final AudioConformStore _store;

  final Map<String, Map<int, Float32List>> _resampledByRate = {};
  final Set<String> _resamplePending = {};

  /// The rates a path could not be converted to — not kicked again for the
  /// session, as a conform that spent its attempts is not: a run that waits
  /// for its sound ([AudioConformStore.isLanding]) would otherwise wait on
  /// a conversion failing again at every landing. [forget] forgets them.
  final Map<String, Set<int>> _conversionsThatFailed = {};

  /// Each span of a path baked through its equalizer, by the rate and the
  /// span — the second result made of a conform, beside
  /// [_resampledByRate].
  final Map<String, Map<(int, EqualizedSpan), Float32List>> _equalized = {};

  /// Each span of a STREAMED path through its equalizer: its checkpoints,
  /// by the span — the long sound's half of [_equalized], under way and
  /// failing under the same keys, at the project's rate, the one a streamed
  /// conform plays at.
  final Map<String, Map<EqualizedSpan, EqualizerCheckpoints>> _checkpoints =
      {};

  final Set<(String, int, EqualizedSpan)> _equalizePending = {};

  /// The bakes and checkpoints that could not be made — not kicked again,
  /// as [_conversionsThatFailed] are not.
  final Map<String, Set<(int, EqualizedSpan)>> _equalizingThatFailed = {};

  String _resampleKey(String sourcePath, int sampleRate) =>
      '$sampleRate|$sourcePath';

  /// [entry]'s samples converted to [sampleRate] — null while that is kicked
  /// ([AudioConformStore.samplesAtRate]).
  Float32List? convertedTo(
    String sourcePath,
    ConformResult entry,
    int sampleRate,
  ) {
    final cached = _resampledByRate[sourcePath]?[sampleRate];
    if (cached != null ||
        (_conversionsThatFailed[sourcePath]?.contains(sampleRate) ?? false)) {
      return cached;
    }
    final key = _resampleKey(sourcePath, sampleRate);
    if (_resamplePending.add(key)) {
      unawaited(
        _land(
          sourcePath,
          entry,
          () => _store._resampleRunner(
            ResampleRequest(
              samples: entry.samples!,
              channels: entry.channels,
              inputRate: entry.sampleRate,
              outputRate: sampleRate,
            ),
          ),
          (
            keep: (Float32List converted) =>
                (_resampledByRate[sourcePath] ??= {})[sampleRate] = converted,
            failed: () =>
                (_conversionsThatFailed[sourcePath] ??= {}).add(sampleRate),
            saying: (error) =>
                'device-rate conversion failed for '
                '$sourcePath → ${sampleRate}Hz: $error',
            settled: () => _resamplePending.remove(key),
          ),
        ),
      );
    }
    return null;
  }

  /// [sourcePath]'s [span] baked at [sampleRate] — null while that is
  /// kicked ([AudioConformStore.equalizedAt]).
  Float32List? bakedAt(String sourcePath, int sampleRate, EqualizedSpan span) {
    final samples = _store.samplesAtRate(sourcePath, sampleRate);
    final entry = _store._entries[sourcePath];
    if (samples == null || entry == null) {
      return null;
    }
    final key = (sampleRate, span);
    final cached = _equalized[sourcePath]?[key];
    if (cached != null || _cannotBeMade(sourcePath, key)) {
      return cached;
    }
    _kickOnce(
      sourcePath,
      key,
      () => _store._equalizeRunner(
        EqualizeRequest(
          samples: samples,
          channels: entry.channels,
          rate: sampleRate,
          span: span,
        ),
      ),
      (baked) => (_equalized[sourcePath] ??= {})[key] = baked,
    );
    return null;
  }

  /// [sourcePath]'s streamed [span]'s checkpoints — null while they are
  /// kicked ([AudioConformStore.equalizerCheckpointsFor]).
  EqualizerCheckpoints? checkpointsFor(String sourcePath, EqualizedSpan span) {
    final reader = _store.streamReaderFor(sourcePath);
    if (reader == null) {
      return null;
    }
    final key = (_store.projectSampleRate, span);
    final cached = _checkpoints[sourcePath]?[span];
    if (cached != null || _cannotBeMade(sourcePath, key)) {
      return cached;
    }
    _kickOnce(
      sourcePath,
      key,
      () => _checkpointsOnAWorker(reader, span),
      (made) => (_checkpoints[sourcePath] ??= {})[span] = made,
    );
    return null;
  }

  bool _cannotBeMade(String sourcePath, (int, EqualizedSpan) key) =>
      _equalizingThatFailed[sourcePath]?.contains(key) ?? false;

  /// [making] [sourcePath]'s span at [key] from the conform it holds now —
  /// once while it is under way, kept by [keep] as it lands.
  void _kickOnce<T>(
    String sourcePath,
    (int, EqualizedSpan) key,
    Future<T> Function() making,
    void Function(T made) keep,
  ) {
    final pending = (sourcePath, key.$1, key.$2);
    if (!_equalizePending.add(pending)) {
      return;
    }
    unawaited(
      _land(sourcePath, _store._entries[sourcePath]!, making, (
        keep: keep,
        failed: () => (_equalizingThatFailed[sourcePath] ??= {}).add(key),
        saying: (error) =>
            'equalizing ${key.$2} of $sourcePath at ${key.$1}Hz '
            'failed: $error',
        settled: () => _equalizePending.remove(pending),
      )),
    );
  }

  /// Whether a conversion of [sourcePath] to [sampleRate], or a span of it
  /// baked or checkpointed at that rate, is under way.
  bool isLanding(String sourcePath, int sampleRate) =>
      _resamplePending.contains(_resampleKey(sourcePath, sampleRate)) ||
      _equalizePending.any(
        (bake) => bake.$1 == sourcePath && bake.$2 == sampleRate,
      );

  /// Lets go of what was made of [sourcePath]'s conform — the conform it
  /// was made of is gone ([AudioConformStore.resultFor]).
  void letGoOfWhatWasMade(String sourcePath) {
    _resampledByRate.remove(sourcePath);
    _equalized.remove(sourcePath);
    _checkpoints.remove(sourcePath);
  }

  /// [letGoOfWhatWasMade], and of what could not be made, so the next
  /// look makes it again ([AudioConformStore.invalidate]).
  void forget(String sourcePath) {
    letGoOfWhatWasMade(sourcePath);
    _conversionsThatFailed.remove(sourcePath);
    _equalizingThatFailed.remove(sourcePath);
  }

  /// What [making] makes of [sourcePath]'s conform [entry], gone where
  /// [landing] says as it lands — and the store's listeners told, either
  /// way.
  ///
  /// 🚨ONTO THE ENTRY IT WAS MADE FROM, OR NOWHERE: one let go of while it
  /// ran — another carry, a rate that moved — would otherwise get the old
  /// sound back. ↩️The conversion spelled this out on its own; the
  /// equalizer's bake and its checkpoints made it three.
  /// 🚨A FAILURE TOO (저장's read of the bake, 11-17): remembered against
  /// the entry it failed on, it would stop the next entry's — never let go
  /// of with a carry that moved — for the session.
  Future<void> _land<T>(
    String sourcePath,
    ConformResult entry,
    Future<T> Function() making,
    _Landing<T> landing,
  ) async {
    final store = _store;
    bool madeOfWhatIsHeld() =>
        !store._disposed && identical(store._entries[sourcePath], entry);
    try {
      final made = await making();
      if (madeOfWhatIsHeld()) {
        landing.keep(made);
      }
    } on Object catch (error) {
      if (madeOfWhatIsHeld()) {
        landing.failed();
        store._log('[AudioConformStore] ${landing.saying(error)}');
      }
    } finally {
      if (!store._disposed) {
        landing.settled();
        store._landed();
      }
    }
  }
}

/// The checkpoints' pass, in a function of its own: [onAWorker] copies the
/// closure's whole context, and this one holds a reader and a span.
Future<EqualizerCheckpoints> _checkpointsOnAWorker(
  ConformPcmStreamReader reader,
  EqualizedSpan span,
) => onAWorker(
  () =>
      equalizerCheckpointsOf(reader, span) ??
      (throw StateError('the conform did not read whole')),
);
