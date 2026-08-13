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
/// Layout. What can be regenerated and what cannot no longer live next to
/// each other, because they do not travel together: the original is the
/// user's content and belongs with the project, while a conform is a cache
/// roughly twelve times its source's size that has no business syncing to
/// a cloud folder or riding along to another machine.
///
/// ```
/// 프로젝트.anicel
/// 프로젝트.assets/
///   Media/                        대사.m4a      deleting this loses work
/// <app container>/Conformed/
///   프로젝트.anicel.<hash>/       대사.m4a.wav  costs only time
/// ```
///
/// `Media/` sits under the save directory, so the .anicel's existing
/// relative-path manifest picks it up for free and a folder moved to
/// another machine relinks itself. The conform folder is named by
/// `AppSave.encodeProjectKey` so two projects called `C-045.anicel` cannot
/// share one cache, and the root moves with a Preferences setting.
library;

import 'dart:io';
import 'dart:typed_data';

import '../persistence/anicel_incremental_writer.dart' show anicelCrc32;
import '../persistence/app_save_settings.dart' show AppSave;
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

  /// The attempt failed in a way nothing anticipated.
  ///
  /// NOT the ordinary "could not write the cache" case any more: permissions,
  /// a full disk or a cloud folder mid-sync leave the decoded audio intact,
  /// so [AudioConformPipeline.ensureConform] returns [built] with a null
  /// `conformPath` and the reason in `error`. Losing the sound over a cache
  /// was the bug. What is left here is the store's catch-all wrapper.
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

/// Where a project's imported media USED to live.
///
/// Nothing writes here any more — a `.anicel` carries its own media, and
/// the import that used to copy files into `Media/` records the original
/// in place. This survives because absorbing an old project still means
/// knowing the old address: the files sitting there are ordinary sources,
/// so opening such a project and saving it takes them inside, and the
/// notice that says the folder can go needs to find it first.
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

  /// Originals, from the builds that copied them here.
  String get mediaDirectory => '$assetsDirectory/Media';

  /// Whether this project still has the sibling folder beside it.
  ///
  /// ⛔ Answering yes is not permission to delete it. The app does not
  /// remove the user's files (user direction) — it says the folder is no
  /// longer used and leaves the decision where it belongs. Which also
  /// means this keeps answering yes until they act, and that is honest:
  /// the folder really is still there.
  bool get hasLegacyAssetsDirectory =>
      Directory(assetsDirectory).existsSync();
}

/// Where conforms are cached, and what they are called.
///
/// A directory plus a naming rule, kept apart from [ProjectAssetLayout]
/// because the two stopped answering the same question: media is the
/// project's own content and a conform is a regenerable cache.
///
/// 🔑 Keyed by the SOURCE and the settings it was rendered under, never by
/// the project. What decides a conform's contents is the file, the sample
/// rate and the audio speed — not who happens to be using it. The old
/// per-project folder was inherited from `<project>.assets/Conformed`,
/// where the project WAS the folder, and carrying that shape into a common
/// cache cost three things:
///
/// - Save As, a rename or a move produced a brand new key, and every
///   conform the project had built became unreachable garbage nobody
///   would ever collect.
/// - Two projects using the same sound each built their own copy of a
///   cache entry twelve times the size of the source.
/// - A project that had never been saved had no key at all, so it got no
///   cache and re-decoded its audio on every launch.
///
/// All three are the same mistake, and keying by source ends all three.
class ConformCacheLayout {
  const ConformCacheLayout({
    required this.directory,
    required this.sampleRate,
    required this.speedNumerator,
    required this.speedDenominator,
  });

  /// The cache for audio rendered at these settings — the whole
  /// composition in one place so a caller cannot assemble a different one
  /// by hand.
  ///
  /// The session used to hold the halves itself, and nothing could see the
  /// result: every test that builds a session injects its own conform
  /// store, so the production path assembly had no observer at all. Naming
  /// the composition gives it one.
  factory ConformCacheLayout.forAudio({
    required int sampleRate,
    required int speedNumerator,
    required int speedDenominator,
  }) => ConformCacheLayout(
    directory: AppSave.conformRootDirectory,
    sampleRate: sampleRate,
    speedNumerator: speedNumerator,
    speedDenominator: speedDenominator,
  );

  /// The cache root, already resolved.
  final String directory;

  /// The project's audio settings, which a conform's contents depend on.
  ///
  /// ⚠️ Both belong in the KEY, not merely in the file. A 44.1k conform
  /// played against a 48k schedule slides every clip, and a pull-down
  /// speed difference drifts by a thousandth — small enough to survive a
  /// listen and wrong by the end of a reel. They are recorded inside the
  /// conform as well, so a mismatch is caught either way; putting them in
  /// the name means the two never meet in the first place, and a project
  /// that switches rate back and forth keeps both conforms instead of
  /// rebuilding at every change.
  final int sampleRate;
  final int speedNumerator;
  final int speedDenominator;

  /// The conform for [mediaPath], derived by rule rather than recorded in
  /// the project. Nothing to keep in sync, and `project.json` stays small.
  ///
  /// The source's own name is kept in front of the hash so a person
  /// looking in the cache folder can tell what they are looking at — the
  /// hash is what makes it unique, the name is what makes it legible.
  ///
  /// ⚠️ What a hash collision costs, stated honestly. Two sources whose
  /// (path | rate | speed) hashes collide AND whose basenames match land
  /// on one file, and the reuse check that decides it is the CHEAP one:
  /// source length plus mtime, with the content fingerprint reached only
  /// when that hint misses (PR-1's fast path, deliberately — the
  /// alternative is reading every source on every open). So the two would
  /// also have to share a length and a modification time to the
  /// microsecond before the wrong sound could be served; anything less
  /// and the file is rebuilt.
  ///
  /// ⛔ Do not "fix" this by checking the fingerprint first. That trades a
  /// probability nobody will meet for a full read of every source at every
  /// open, which is the cost that path was built to remove.
  String conformPathFor(String mediaPath) {
    final normalized = mediaPath.replaceAll('\\', '/');
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    final key = AppSave.pathHash(
      '$normalized|$sampleRate|$speedNumerator/$speedDenominator',
    );
    return '$directory/$name.${key.toRadixString(16).padLeft(8, '0')}.wav';
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

  /// Ensures a usable conform exists for [sourcePath] at [conformPath].
  ///
  /// Reuses the existing one when its recorded fingerprint still matches
  /// the source. A conform with NO fingerprint counts as stale on purpose:
  /// it was not written by us, nothing is known about where it came from,
  /// and guessing wrong plays the wrong sound against someone's drawing.
  ///
  /// A null [conformPath] runs MEMORY-ONLY: decode and resample without
  /// touching the disk — the FALLBACK when the cache cannot be written, so
  /// a cache that is missing, full or unreachable costs a re-decode rather
  /// than the sound. (It used to be the unsaved-project case too, back
  /// when the cache was named after the project. Keying by source ended
  /// that: an unsaved project caches like any other.)
  ///
  /// The reuse answer, from an [existing] conform that has already been
  /// judged current. One place so the fast (stat) and slow (content) paths
  /// cannot drift into returning different shapes for the same decision.
  ///
  /// Reuse TOUCHES the file. It is the only record of when an entry was
  /// last wanted, and without it the eviction order would be "oldest
  /// built" — which throws out the sound someone uses in every cut and
  /// keeps the one they imported once by mistake.
  ConformResult _reuse(ConformAudio existing, String? conformPath) {
    if (conformPath != null) {
      try {
        File(conformPath).setLastModifiedSync(DateTime.now());
      } on Object {
        // A read-only cache still reuses; it just evicts in a worse
        // order. Never worth failing a conform over.
      }
    }
    return ConformResult(
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
  }

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

    // Failing to CACHE a conform is not failing to CONFORM one. The decoded,
    // resampled PCM is already in hand at this point — the very bytes the
    // success below returns — so throwing it away because a directory could
    // not be created costs the user their sound to save nothing.
    //
    // That mattered less when the cache lived under the project's own
    // folder, which the app already had a grant for. The cache root is a
    // setting now, and Preferences invites the user to point it at another
    // drive; an unplugged one, a folder they deleted, or a macOS path whose
    // sandbox scope did not survive the relaunch all land here. The store
    // spends one of three attempts per failure and then returns null
    // forever, so the old answer was: the clip goes silent for the session
    // and exports silent, over a cache.
    //
    // Uncached is a normal state — a never-saved project runs this way on
    // purpose. So report exactly that: built, cached nowhere, with the
    // reason. The next ensure tries the write again, which is what lets a
    // volume coming back fix itself.
    var cachedAt = conformPath;
    String? cacheError;
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
        cachedAt = null;
        cacheError = 'could not cache the conform: $error';
      }
    }

    return ConformResult(
      outcome: ConformOutcome.built,
      conformPath: cachedAt,
      error: cacheError,
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
