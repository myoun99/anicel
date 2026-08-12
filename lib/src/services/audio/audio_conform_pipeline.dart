/// Import → conform (audio program 2B, final wiring).
///
/// What happens when a sound enters a project, in the order professional
/// tools do it: the original is copied in beside the project, decoded once,
/// resampled to the project rate, and written back out as plain PCM. From
/// then on nothing reads the original — playback reads the conform.
///
/// This is what makes the audio callback able to promise anything. A
/// compressed codec decodes in variable time and cannot be asked to finish
/// inside a realtime buffer; a conform is `memcpy`. Pro Tools makes you
/// convert on import, Premiere writes a `.cfa`, Avid transcodes to MXF —
/// all the same move.
///
/// Layout, beside the `.anicel` rather than inside it (user decision,
/// 2026-07-21): the project file stays light, and the parts that CAN be
/// regenerated are visibly separate from the parts that cannot.
///
/// ```
/// 프로젝트.anicel
/// 프로젝트.assets/
///   Media/      대사.m4a      the original — deleting this loses work
///   Conformed/  대사.m4a.wav  regenerable; deleting it costs only time
/// ```
///
/// `Media/` sits under the save directory, so the .anicel's existing
/// relative-path manifest picks it up for free and a folder moved to
/// another machine relinks itself.
library;

import 'dart:io';
import 'dart:typed_data';

import '../persistence/anicel_incremental_writer.dart' show anicelCrc32;
import 'audio_peaks_extractor.dart';
import 'conform_wav_codec.dart';

/// Decodes container bytes to PCM at the file's own rate. The native
/// dr_libs path supplies this; tests supply a fake so the pipeline's logic
/// is exercised without a binary.
typedef AudioDecodeCallback =
    ({Float32List samples, int channels, int sampleRate})? Function(
      Uint8List bytes,
    );

/// Converts PCM to the project rate. The native polyphase resampler
/// supplies this.
typedef AudioResampleCallback =
    Float32List Function({
      required Float32List samples,
      required int channels,
      required int inputRate,
      required int outputRate,
    });

/// Why a conform attempt ended the way it did — enough for a log line that
/// explains itself, instead of a silent missing waveform.
enum ConformOutcome {
  /// Freshly decoded, resampled and written.
  built,

  /// An existing conform still matched the source, so nothing was redone.
  reused,

  /// The source is not there.
  sourceMissing,

  /// The source IS there but could not be read right now — a cloud
  /// placeholder that has not hydrated, a handle held by something else.
  /// Distinct from [sourceMissing] because it is TRANSIENT: retrying later
  /// is the whole plan, so it must not spend the store's attempt budget.
  sourceUnreadable,

  /// No decoder recognized the container.
  undecodable,

  /// Writing failed (permissions, full disk, a cloud folder mid-sync).
  writeFailed,
}

class ConformResult {
  const ConformResult({
    required this.outcome,
    this.conformPath,
    this.peaks,
    this.samples,
    this.channels = 0,
    this.sampleRate = 0,
    this.frames = 0,
    this.speedNumerator = 1,
    this.speedDenominator = 1,
    this.error,
  });

  final ConformOutcome outcome;
  final String? conformPath;

  /// Computed from the conformed PCM, so waveforms no longer need ffmpeg —
  /// which is why they have never appeared on a tablet.
  final AudioPeaks? peaks;

  /// The conformed PCM itself, interleaved float32 at the project rate —
  /// what the device transport uploads. Rides along because the pipeline
  /// already holds it; re-reading the WAV it just wrote would only add a
  /// second copy of the same bytes.
  final Float32List? samples;

  final int channels;
  final int sampleRate;

  /// Samples per channel.
  final int frames;

  /// The audio speed this result was rendered at (EXPORT-AUDIO ④).
  final int speedNumerator;
  final int speedDenominator;

  final String? error;

  bool get isUsable =>
      outcome == ConformOutcome.built || outcome == ConformOutcome.reused;

  /// Whether this failure is worth retrying without cost — the store must
  /// not count it against the attempt budget, or a file that is merely
  /// still downloading goes permanently silent three ticks later.
  ///
  /// A PREDICATE rather than a check on the enum at the call site, so the
  /// next transient reason joins here instead of in the store.
  bool get isTransientFailure => outcome == ConformOutcome.sourceUnreadable;
}

/// Where a project's imported media and conforms live.
class ProjectAssetLayout {
  const ProjectAssetLayout(this.projectFilePath);

  /// The `.anicel` this layout belongs to.
  final String projectFilePath;

  static String _withoutExtension(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final dot = normalized.lastIndexOf('.');
    return dot > slash ? normalized.substring(0, dot) : normalized;
  }

  /// `<project>.assets` — beside the file, not inside it.
  String get assetsDirectory => '${_withoutExtension(projectFilePath)}.assets';

  /// Originals. Deleting this loses work; the name says so.
  String get mediaDirectory => '$assetsDirectory/Media';

  /// Conforms. Regenerable — deleting it costs time, not content.
  String get conformedDirectory => '$assetsDirectory/Conformed';

  /// The conform for [mediaPath], derived by rule rather than recorded in
  /// the project. Nothing to keep in sync, and `project.json` stays small.
  String conformPathFor(String mediaPath) {
    final normalized = mediaPath.replaceAll('\\', '/');
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    return '$conformedDirectory/$name.wav';
  }
}

/// Builds and reuses conforms.
///
/// Every file operation goes through injectable seams so the whole thing
/// is testable without touching a disk — the pipeline's decisions (is this
/// stale? what name avoids a collision?) are the part worth pinning, and
/// they should not need a temp directory to check.
class AudioConformPipeline {
  const AudioConformPipeline({
    required this.decode,
    required this.resample,
    this.projectSampleRate = 48000,
    this.bucketsPerSecond = 40,
    this.speedNumerator = 1,
    this.speedDenominator = 1,
  });

  final AudioDecodeCallback decode;
  final AudioResampleCallback resample;
  final int projectSampleRate;
  final int bucketsPerSecond;

  /// The project's audio speed (EXPORT-AUDIO ④): 1001/1000 is the NTSC
  /// pull that keeps frame alignment across a 23.976↔24 change. Applied
  /// by REINTERPRETING the source rate into the resample — the exact
  /// rational, never a float factor.
  final int speedNumerator;
  final int speedDenominator;

  /// The fingerprint [sourceBytes] carries — the IDENTITY, content-derived
  /// so it survives being copied to another machine.
  ///
  /// Takes BYTES rather than a path because the fingerprint is content, and
  /// because the caller that needs one is about to decode those bytes
  /// anyway: this costs a pass over what is already in hand.
  static ConformSourceFingerprint fingerprintOf(Uint8List sourceBytes) =>
      ConformSourceFingerprint(
        sourceLength: sourceBytes.length,
        sourceCrc32: anicelCrc32(sourceBytes),
      );

  /// What `stat` says about [sourcePath], or null when it is not there.
  ///
  /// The CHEAP half of the reuse question. A hit means "nothing on this
  /// machine has touched it" and the conform stands without a read; a miss
  /// means nothing on its own and falls through to [fingerprintOf].
  /// Asks about the PATH rather than through `File`: `File(dir).existsSync()`
  /// answers false for a directory, which would report "missing" for a path
  /// that plainly has something at it. Null means nothing is there; anything
  /// else is a thing we may or may not be able to read, and that difference
  /// belongs to the caller.
  static ConformSourceStat? statOf(String sourcePath) {
    try {
      final stat = FileStat.statSync(sourcePath);
      if (stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      return ConformSourceStat(
        sourceLength: stat.size,
        sourceModifiedMicros: stat.modified.microsecondsSinceEpoch,
      );
    } on Object {
      return null;
    }
  }

  /// A name inside [directory] that no existing file claims: `x.wav`,
  /// then `x-1.wav`, `x-2.wav`. Pro Tools does the same on import, and the
  /// alternative is one sound silently overwriting another.
  static String uniqueNameIn(
    String directory,
    String fileName, {
    bool Function(String path)? exists,
  }) {
    final taken = exists ?? (path) => File(path).existsSync();
    if (!taken('$directory/$fileName')) {
      return fileName;
    }
    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    final extension = dot <= 0 ? '' : fileName.substring(dot);
    for (var index = 1; index < 10000; index += 1) {
      final candidate = '$stem-$index$extension';
      if (!taken('$directory/$candidate')) {
        return candidate;
      }
    }
    return fileName;
  }

  /// Ensures a usable conform exists for [sourcePath] at [conformPath].
  ///
  /// Reuses the existing one when its recorded fingerprint still matches
  /// the source. A conform with NO fingerprint counts as stale on purpose:
  /// it was not written by us, nothing is known about where it came from,
  /// and guessing wrong plays the wrong sound against someone's drawing.
  ///
  /// A null [conformPath] runs MEMORY-ONLY: decode and resample without
  /// touching the disk. That is the unsaved-project case — there is no
  /// `.assets` directory to write beside a file that does not exist yet,
  /// and a conform is derived data anyway: once the project is saved, the
  /// next ensure writes it beside the `.anicel` like any other.
  /// The reuse answer, from an [existing] conform that has already been
  /// judged current. One place so the fast (stat) and slow (content) paths
  /// cannot drift into returning different shapes for the same decision.
  ConformResult _reuse(ConformAudio existing, String? conformPath) =>
      ConformResult(
        outcome: ConformOutcome.reused,
        conformPath: conformPath,
        peaks: peaksFromSamples(
          samples: existing.samples,
          channels: existing.channels,
          sampleRate: existing.sampleRate,
          bucketsPerSecond: bucketsPerSecond,
        ),
        samples: existing.samples,
        channels: existing.channels,
        sampleRate: existing.sampleRate,
        frames: existing.length,
        speedNumerator: speedNumerator,
        speedDenominator: speedDenominator,
      );

  ConformResult ensureConform({
    required String sourcePath,
    required String? conformPath,
  }) {
    final stat = statOf(sourcePath);
    if (stat == null) {
      return const ConformResult(
        outcome: ConformOutcome.sourceMissing,
        error: 'the source file is missing',
      );
    }

    final existing = conformPath == null ? null : _readConform(conformPath);
    // A conform at another rate is stale even with a matching source: the
    // project's audio rate is a setting now (EXPORT-AUDIO ③), and playing
    // 44.1k PCM on a 48k schedule would shift every clip. The same goes for
    // the audio speed (④) — a pulled conform against an unpulled project is
    // 0.1% of drift back in the door.
    final settingsMatch =
        existing != null &&
        existing.sampleRate == projectSampleRate &&
        existing.speedNumerator == speedNumerator &&
        existing.speedDenominator == speedDenominator;

    // FAST PATH: the source still has the length and timestamp it had when
    // this conform was written, so nothing on this machine has touched it
    // and the bytes need not be looked at. This is the common case on every
    // open, and skipping it made every project pay a full read of every
    // original before it could discover there was nothing to do — on the
    // very devices where a big allocation gets the app killed.
    if (settingsMatch && existing.sourceStat?.matches(stat) == true) {
      return _reuse(existing, conformPath);
    }

    // SLOW PATH: the hint missed, which says nothing by itself — a copied,
    // restored or re-synced project gets fresh timestamps with identical
    // bytes, and that is exactly what a timestamp identity used to answer
    // wrong. The content decides.
    final Uint8List sourceBytes;
    try {
      sourceBytes = File(sourcePath).readAsBytesSync();
    } on Object catch (error) {
      // It EXISTS — statOf just said so — so this is transient: an
      // unhydrated cloud placeholder, or a handle held elsewhere. Calling
      // it "missing" spends one of three attempts on a file that is fine,
      // and three of those silence the clip for the rest of the session.
      return ConformResult(
        outcome: ConformOutcome.sourceUnreadable,
        error: 'could not read the source (retrying): $error',
      );
    }
    final fingerprint = fingerprintOf(sourceBytes);

    if (settingsMatch && conformMatchesSource(existing, fingerprint)) {
      return _reuse(existing, conformPath);
    }

    final decoded = decode(sourceBytes);
    if (decoded == null || decoded.channels <= 0 || decoded.sampleRate <= 0) {
      return const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'no decoder recognized this file',
      );
    }

    // Equal rates at unity speed skip the filter entirely and stay
    // bit-exact — most SE libraries and dialogue are already at the
    // project rate, so this is the common path. A non-unity speed (the
    // NTSC pull) REINTERPRETS the source rate: both sides of the resample
    // scale by the exact rational, so 48k pulled by 1001/1000 is a
    // 48048000→48000000 conversion — integer ratios end to end, and the
    // output lands at the project rate holding 0.1% less time.
    final unitySpeed = speedNumerator == speedDenominator;
    final converted =
        decoded.sampleRate == projectSampleRate && unitySpeed
        ? decoded.samples
        : resample(
            samples: decoded.samples,
            channels: decoded.channels,
            inputRate: decoded.sampleRate * speedNumerator,
            outputRate: projectSampleRate * speedDenominator,
          );

    if (conformPath != null) {
      try {
        final directory = conformPath.substring(
          0,
          conformPath.replaceAll('\\', '/').lastIndexOf('/'),
        );
        Directory(directory).createSync(recursive: true);
        File(conformPath).writeAsBytesSync(
          encodeConformWav(
            samples: converted,
            channels: decoded.channels,
            sampleRate: projectSampleRate,
            fingerprint: fingerprint,
            // Recorded from the stat taken BEFORE the read, so the hint
            // describes the file this conform actually came from. Re-statting
            // now could catch a write that landed mid-build and bless a
            // conform of the previous contents.
            sourceStat: stat,
            speedNumerator: speedNumerator,
            speedDenominator: speedDenominator,
          ),
        );
      } on Object catch (error) {
        return ConformResult(
          outcome: ConformOutcome.writeFailed,
          error: 'could not write the conform: $error',
        );
      }
    }

    return ConformResult(
      outcome: ConformOutcome.built,
      conformPath: conformPath,
      peaks: peaksFromSamples(
        samples: converted,
        channels: decoded.channels,
        sampleRate: projectSampleRate,
        bucketsPerSecond: bucketsPerSecond,
      ),
      samples: converted,
      channels: decoded.channels,
      sampleRate: projectSampleRate,
      frames: decoded.channels <= 0
          ? 0
          : converted.length ~/ decoded.channels,
      speedNumerator: speedNumerator,
      speedDenominator: speedDenominator,
    );
  }

  ConformAudio? _readConform(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      return decodeConformWav(file.readAsBytesSync());
    } on Object {
      // An unreadable or foreign conform is simply rebuilt.
      return null;
    }
  }
}
