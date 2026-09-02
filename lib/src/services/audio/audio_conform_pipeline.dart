/// Import → conform (audio program 2B, final wiring).
///
/// What happens when a sound enters a project, in the order professional
/// tools do it: decoded once, resampled to the project rate, and written
/// back out as plain PCM. From then on nothing reads the original —
/// playback reads the conform.
///
/// This is what makes the audio callback able to promise anything. A
/// compressed codec decodes in variable time and cannot be asked to finish
/// inside a realtime buffer; a conform is `memcpy`. Pro Tools makes you
/// convert on import, Premiere writes a `.cfa`, Avid transcodes to MXF —
/// all the same move.
///
/// Layout. Both live in the project now, and the conform ALSO has a cache.
///
/// ```
/// 프로젝트.anicel
///   media/<hash>-대사.m4a[.z]                    the sound itself
///   conform/<hash>-대사.m4a[.z]                  its decoded PCM
/// <app container>/Conformed/
///   대사.m4a.<hash>.wav[.z]                      what playback reads
/// ```
///
/// 🚨★★★**THE CONFORM RIDES IN THE PROJECT** (유저 2026-08-30,
/// `conform-in-project` = always). This paragraph used to say the opposite
/// — that a conform is「a cache with no business following anyone to
/// another machine」— and that was true while it cost 12× the source
/// uncompressed. Compressed it is ~7×, which on a project that already
/// weighs gigabytes is under a tenth, and what it buys is that opening it
/// somewhere else PLAYS instead of decoding every sound first.
///
/// ⛔Do not read the cache as redundant with the carried copy. The cache is
/// what playback reads and what the collector bounds; the carried copy is
/// what a machine with an empty cache restores FROM. An asset with both
/// genuinely costs both, and only the cache half is ever reclaimed.
///
/// ⚠️The two are kept honest by the CACHE PATH, which keys on the sample
/// rate and audio speed. Change either and the conform for the new
/// settings is at a different address, nothing is found there, and the
/// save carries none — which is how the entry for the old one gets
/// removed rather than accumulating (유저: 「레이트 변경 등 죽은파일만
/// 깔끔하게 잘 걷어낼것」).
///
/// 🔑 The cache is keyed by the SOURCE and the settings it was rendered
/// under — never by the project, which is what an earlier layout did back
/// when the cache was a folder beside the `.anicel`. Keying by the project
/// meant a Save As abandoned every conform it had built, two projects
/// using one sound each paid for their own copy, and a project with no
/// name yet got no cache at all. See [ConformCacheLayout].
///
/// The root moves with a Preferences setting, and the cache has a size
/// bound and a collector — see `conform_cache_maintenance.dart`.
library;

import 'dart:io';
import 'dart:typed_data';

import '../media/media_byte_source.dart';
import '../persistence/anicel_incremental_writer.dart'
    show anicelCrc32, anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;
import '../persistence/app_save_settings.dart' show AppSave;
import '../persistence/media_blob_codec.dart';
import 'audio_peaks_extractor.dart';
import 'conform_pcm_codec.dart';

/// Decodes a container to PCM at the file's own rate. The native decoder
/// supplies this; tests supply a fake so the pipeline's logic is exercised
/// without a binary.
///
/// 🚨★★★**IT TAKES THE SOURCE, NOT THE BYTES.** It used to take a
/// `Uint8List`, which meant the whole container was in memory before any
/// decoder was asked to look at it — and that, not the decoders, is why a
/// movie's soundtrack could not be conformed: a three-gigabyte reference
/// video is not a byte array. A source can name itself as a path plus a
/// span ([MediaByteSource.range]), and the native decoder takes exactly
/// that.
typedef AudioDecodeCallback =
    ({Float32List samples, int channels, int sampleRate})? Function(
      MediaByteSource source,
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
  bool get hasLegacyAssetsDirectory => Directory(assetsDirectory).existsSync();
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
  /// because a caller holding bytes has already paid for them.
  static ConformSourceFingerprint fingerprintOf(Uint8List sourceBytes) =>
      ConformSourceFingerprint(
        sourceLength: sourceBytes.length,
        sourceCrc32: anicelCrc32(sourceBytes),
      );

  /// The same identity, without holding the source.
  ///
  /// 🚨★★★**A FINGERPRINT MUST NOT COST AN ALLOCATION THE SIZE OF THE FILE.**
  /// This is the identity of a possibly-enormous container, and the whole
  /// point of the range decode is undone if the check in front of it reads
  /// the file into memory first. `anicelCrc32Update` exists for exactly this
  /// — the archive writer folds a streamed entry the same way, for the same
  /// reason.
  ///
  /// ⚠️Falls back to bytes for a FRAMED source, and that is not a shortcut:
  /// its stored blocks are compressed, so the only way to see its content is
  /// to have it assembled. Nothing enormous is stored framed — compression
  /// is decided per file by measurement, and a movie does not shrink.
  static ConformSourceFingerprint fingerprintOfSource(MediaByteSource source) {
    final span = source.range;
    if (span == null) {
      return fingerprintOf(source.readSync());
    }
    var state = anicelCrc32Start;
    final buffer = Uint8List(_fingerprintChunkBytes);
    var read = 0;
    final handle = File(span.path).openSync();
    try {
      handle.setPositionSync(span.offset);
      while (read < span.length) {
        final want = span.length - read < buffer.length
            ? span.length - read
            : buffer.length;
        final got = handle.readIntoSync(buffer, 0, want);
        if (got <= 0) {
          break;
        }
        state = anicelCrc32Update(
          state,
          got == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, got),
        );
        read += got;
      }
    } finally {
      handle.closeSync();
    }
    return ConformSourceFingerprint(
      sourceLength: read,
      sourceCrc32: anicelCrc32Finish(state),
    );
  }

  /// The refusal owed when an archive range no longer holds what it did, or
  /// null when it still does.
  ///
  /// ⛔ONE function because it is asked from two places now — before the
  /// decode when a reuse is possible, and after it when one was not. Two
  /// copies of a tripwire is one copy of a tripwire.
  static ConformResult? _archiveMovedUnderUs(
    int? knownCrc,
    ConformSourceFingerprint fingerprint,
  ) {
    // An archive range read under a COMPACTION reads whatever moved into
    // those bytes — the offsets were resolved when the request was built.
    // A mismatch is transient (the next attempt resolves fresh offsets),
    // never a decode of the wrong sound.
    if (knownCrc == null || fingerprint.sourceCrc32 == knownCrc) {
      return null;
    }
    return const ConformResult(
      outcome: ConformOutcome.sourceUnreadable,
      error: 'the archive changed underneath this read (retrying)',
    );
  }

  /// How much of a source is held at once while fingerprinting it.
  ///
  /// ⚠️Small on purpose: this runs on an import isolate on a tablet, and the
  /// number that matters is the PEAK, not the throughput — a 64KB window
  /// reads a gigabyte just as correctly as a 16MB one.
  static const int _fingerprintChunkBytes = 64 * 1024;

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
  /// [cachedAt] is the file the conform was actually READ from — the `.z`
  /// spelling or the plain one — never the base name the request carried.
  /// Touching the wrong one would leave the real entry looking cold and
  /// evict the sound someone uses in every cut.
  ConformResult _reuse(ConformAudio existing, String? cachedAt) {
    if (cachedAt != null) {
      try {
        File(cachedAt).setLastModifiedSync(DateTime.now());
      } on Object {
        // A read-only cache still reuses; it just evicts in a worse
        // order. Never worth failing a conform over.
      }
    }
    return ConformResult(
      outcome: ConformOutcome.reused,
      conformPath: cachedAt,
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
    MediaByteSource? source,
    MediaByteSource? carriedConform,
  }) {
    // Where the bytes actually are: the file at the path unless the caller
    // says otherwise — an archive range for media the project carries.
    // This is the read side carrying grew in the audit round: the save
    // could always stream an embedded asset forward, but THIS pipeline
    // kept asking the filesystem, so deleting the import original — the
    // act carrying exists to survive — reported sourceMissing, burned the
    // retry budget, and silenced the clip for the session and the export.
    final src = source ?? MediaFileBytes(sourcePath);
    if (!src.existsSync()) {
      return const ConformResult(
        outcome: ConformOutcome.sourceMissing,
        error: 'the source file is missing',
      );
    }
    // Null is "no cheap facts", not "missing" — an archive entry has no
    // stat to give and skips straight to the content answer (which it
    // happens to hold for free: ZIP wrote the CRC in the entry header).
    final stat = src.statSync();

    // 🚨★★★**THE PROJECT'S OWN COPY, BROUGHT IN BEFORE ANYTHING IS
    // DECIDED.** 유저 2026-08-30 chose to carry conforms inside the
    // `.anicel` (`conform-in-project` = always), and this is what that buys
    // on the other machine: the cache is empty, the project holds the
    // conform, so it is copied out VERBATIM — framed bytes stay framed, no
    // decode, no re-encode — and every path below is then the ordinary one.
    //
    // ⛔It is restored, not trusted. What comes back is read by
    // [_readConform] and judged by the same settings and fingerprint checks
    // a locally built conform faces; a carried one that no longer matches
    // its source is simply rebuilt over. Deciding staleness twice is how
    // two answers drift apart.
    var cached = conformPath == null ? null : _readConform(conformPath);
    if (cached == null && carriedConform != null && conformPath != null) {
      _restoreCarriedConform(carriedConform, conformPath);
      cached = _readConform(conformPath);
    }
    final existing = cached?.audio;
    // The file the conform was READ from — `.z` or plain. Every reuse
    // below touches THIS, never the base name it was looked up under.
    final reusableAt = cached?.path;
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
    if (settingsMatch &&
        stat != null &&
        (existing.sourceStat?.matches(
              ConformSourceStat(
                sourceLength: stat.lengthBytes,
                sourceModifiedMicros: stat.modifiedMicros,
              ),
            ) ?? false)) {
      return _reuse(existing, reusableAt);
    }

    // The archive's fast path: the entry header already knows the CRC, so
    // the whole identity question is answered without reading a byte.
    final knownCrc = src.knownCrc32;
    if (settingsMatch &&
        knownCrc != null &&
        conformMatchesSource(
          existing,
          ConformSourceFingerprint(
            sourceLength: src.lengthSync(),
            sourceCrc32: knownCrc,
          ),
        )) {
      return _reuse(existing, reusableAt);
    }

    // SLOW PATH: the hint missed, which says nothing by itself — a copied,
    // restored or re-synced project gets fresh timestamps with identical
    // bytes, and that is exactly what a timestamp identity used to answer
    // wrong. The content decides.
    //
    // 🚨★★★**THE FINGERPRINT IS ONLY TAKEN WHEN IT CAN CHANGE THE ANSWER.**
    // It is a full pass over the source, and the decode below is a second
    // one — so on a FIRST conform, where there is nothing to be reused, the
    // first pass buys nothing at all. On a three-gigabyte movie that is
    // three gigabytes of reading to learn what the next line was going to do
    // anyway. It is taken after the decode instead, where it is still needed
    // (the conform records it, so the next open can skip both passes).
    //
    // ⚠️The archive tripwire moves with it, and stays a tripwire: what it
    // promises is that a compaction that moved bytes under a resolved offset
    // never becomes a WRONG SOUND, and checking after the decode still keeps
    // that promise — the decode is thrown away.
    // ⚠️`settingsMatch` already says there IS an existing conform — it is
    // defined as `existing != null && …`. A second null test here reads as
    // if it could be otherwise.
    ConformSourceFingerprint? fingerprint;
    if (settingsMatch) {
      try {
        fingerprint = fingerprintOfSource(src);
      } on Object catch (error) {
        // It EXISTS — the check above just said so — so this is transient:
        // an unhydrated cloud placeholder, or a handle held elsewhere.
        // Calling it "missing" spends one of three attempts on a file that
        // is fine, and three of those silence the clip for the session.
        return ConformResult(
          outcome: ConformOutcome.sourceUnreadable,
          error: 'could not read the source (retrying): $error',
        );
      }
      final wrongBytes = _archiveMovedUnderUs(knownCrc, fingerprint);
      if (wrongBytes != null) {
        return wrongBytes;
      }
      if (conformMatchesSource(existing, fingerprint)) {
        return _reuse(existing, reusableAt);
      }
    }

    // 🚨★★★**IS IT READABLE RIGHT NOW — asked in one byte.**
    //
    // The fingerprint used to answer this on its way past, and moving it
    // after the decode took the answer with it. It matters more than it
    // looks: 「could not read it right now」 is TRANSIENT (a cloud placeholder
    // that has not hydrated, a handle held elsewhere) and must be retried,
    // while 「no decoder recognized it」 is DEFINITIVE and must not be. The
    // decoder cannot tell them apart — it answers null either way — so three
    // ticks would have silenced a file that was merely still downloading.
    //
    // ⚠️One byte, not one pass: whatever makes a source unreadable makes the
    // first byte unreadable.
    try {
      src.readIntoSync(Uint8List(1), 0, 1);
    } on Object catch (error) {
      return ConformResult(
        outcome: ConformOutcome.sourceUnreadable,
        error: 'could not read the source (retrying): $error',
      );
    }

    final decoded = decode(src);
    if (decoded == null || decoded.channels <= 0 || decoded.sampleRate <= 0) {
      return const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'no decoder recognized this file',
      );
    }
    if (fingerprint == null) {
      try {
        fingerprint = fingerprintOfSource(src);
      } on Object catch (error) {
        return ConformResult(
          outcome: ConformOutcome.sourceUnreadable,
          error: 'could not read the source (retrying): $error',
        );
      }
      final wrongBytes = _archiveMovedUnderUs(knownCrc, fingerprint);
      if (wrongBytes != null) {
        return wrongBytes;
      }
    }

    // Equal rates at unity speed skip the filter entirely and stay
    // bit-exact — most SE libraries and dialogue are already at the
    // project rate, so this is the common path. A non-unity speed (the
    // NTSC pull) REINTERPRETS the source rate: both sides of the resample
    // scale by the exact rational, so 48k pulled by 1001/1000 is a
    // 48048000→48000000 conversion — integer ratios end to end, and the
    // output lands at the project rate holding 0.1% less time.
    final unitySpeed = speedNumerator == speedDenominator;
    final converted = decoded.sampleRate == projectSampleRate && unitySpeed
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
    //
    // 🚨★★★**AND IT IS WRITTEN COMPRESSED.** A conform is ~12× its source
    // and zstd takes 38–51% of it back, measured on the user's own audio
    // (see [writeMediaBlob]). 유저 2026-08-30 chose this against the
    // alternative — 「다른 앱으로 들을 필요성을 못느끼겟고 그럴거면
    // 압축해제시켜서 내보내기 기능 만들면 되는거아닌가?」 — which is why
    // `conform_pcm_codec.dart`'s「any audio tool can open it」is now a
    // property of the EXPORT, not of the cache file.
    //
    // ⛔Block-framed, never one frame: a long conform is read as a sliding
    // WINDOW by [ConformPcmStreamReader], and a whole frame has no random
    // access. This is the same codec media uses, so「how do I read this」
    // has one answer for both.
    var cachedAt = conformPath;
    String? cacheError;
    if (conformPath != null) {
      try {
        final directory = conformPath.substring(
          0,
          conformPath.replaceAll('\\', '/').lastIndexOf('/'),
        );
        Directory(directory).createSync(recursive: true);
        final wav = encodeConform(
          samples: converted,
          channels: decoded.channels,
          sampleRate: projectSampleRate,
          fingerprint: fingerprint,
          // Recorded from the stat taken BEFORE the read, so the hint
          // describes the file this conform actually came from. Re-statting
          // now could catch a write that landed mid-build and bless a
          // conform of the previous contents. Null for an archive range —
          // no stat exists, and the content fingerprint above is the
          // whole identity there anyway.
          sourceStat: stat == null
              ? null
              : ConformSourceStat(
                  sourceLength: stat.lengthBytes,
                  sourceModifiedMicros: stat.modifiedMicros,
                ),
          speedNumerator: speedNumerator,
          speedDenominator: speedDenominator,
        );
        // Streamed out rather than compressed whole: an hour of dialogue
        // is hundreds of megabytes, and holding every compressed block
        // beside the PCM to find out whether they were worth keeping is
        // the allocation this build exists not to make.
        cachedAt = writeMediaBlob(
          basePath: conformPath,
          length: wav.length,
          readInto: mediaBytesReader(wav),
        ).path;
        // ⛔The OTHER spelling goes. A rebuild that flips framedness — a
        // build without an engine, or audio that stopped shrinking — would
        // otherwise leave both, and [mediaFramedOrPlainPaths] asks framed
        // first, so the stale one is the one the next open would find.
        for (final other in mediaFramedOrPlainPaths(conformPath)) {
          if (other != cachedAt && File(other).existsSync()) {
            File(other).deleteSync();
          }
        }
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
      frames: decoded.channels <= 0 ? 0 : converted.length ~/ decoded.channels,
      speedNumerator: speedNumerator,
      speedDenominator: speedDenominator,
    );
  }

  /// Writes the project's carried conform into the cache at [basePath], so
  /// the ordinary reuse path can pick it up.
  ///
  /// The bytes go across AS THEY ARE, which is why [carried] is a stored
  /// source rather than a decoded one: a carried conform was framed when
  /// it went in, and decompressing it here only to compress it again would
  /// burn the whole reason it was compressed. [MediaByteSource.storedIsFramed]
  /// is what names the file, exactly as it names an archive entry.
  ///
  /// Failure is silent on purpose. This is an optimisation — the source is
  /// still there and still decodes — so an unwritable cache costs a
  /// re-decode, never the sound. Same reasoning as the cache write below.
  void _restoreCarriedConform(MediaByteSource carried, String basePath) {
    try {
      final path = mediaPathFramed(basePath, framed: carried.storedIsFramed);
      final directory = path.substring(
        0,
        path.replaceAll('\\', '/').lastIndexOf('/'),
      );
      Directory(directory).createSync(recursive: true);
      // ⛔Written STRAIGHT to the final name, not through a `.part`
      // neighbour like the staging store uses. Staging can afford one
      // because its sweep is age-based over every file in its folder; the
      // conform collector only ever deletes files it can PROVE are
      // conforms, so a `.part` here would be invisible to it and sit in
      // the user's cache folder for ever.
      //
      // A kill mid-write is safe without one: a conform's length is
      // declared in its own fixed header, so [decodeConform] refuses a
      // file that is「short of the PCM it claims」and it is rebuilt like
      // any other unreadable one. (This used to say「breaks its chunk walk
      // … missing data chunk」— true while a conform was a WAV, and #1397
      // replaced the chunk walk with the header.)
      //
      // 🚨**A BLOCK AT A TIME.** This read the whole thing to write the
      // whole thing — bytes in, the same bytes out, with an hour of
      // dialogue (~428MB compressed) resident in between to achieve
      // nothing. That is the shape the carry and staging rounds removed
      // everywhere else; it was still here.
      if (!copyMediaBytesToFile(
        destinationPath: path,
        length: carried.lengthSync(),
        readInto: carried.readIntoSync,
      )) {
        throw const FileSystemException('the carried conform ran short');
      }
    } on Object {
      // Leave nothing half-written behind under a name the collector will
      // later believe. The decode below is the fallback, and it always
      // works.
      try {
        final path = mediaPathFramed(basePath, framed: carried.storedIsFramed);
        if (File(path).existsSync()) {
          File(path).deleteSync();
        }
      } on Object {
        // Nothing more to try; a leftover is rejected on read anyway.
      }
    }
  }

  /// The conform cached under [basePath], and WHICH of its two names it is
  /// actually under.
  ///
  /// A cached conform is compressed when that was worth it, so it wears
  /// `.z` or it does not — [mediaFramedOrPlainPaths] is the one place that
  /// knows the order to ask in, and [mediaAppFileSource] the one place that
  /// knows the name decides how to read it.
  ({ConformAudio audio, String path})? _readConform(String basePath) {
    for (final candidate in mediaFramedOrPlainPaths(basePath)) {
      if (!File(candidate).existsSync()) {
        continue;
      }
      try {
        final audio = decodeConform(mediaAppFileSource(candidate).readSync());
        return (audio: audio, path: candidate);
      } on Object {
        // Unreadable, foreign, or framed with no engine on this build:
        // rebuilt, exactly as a missing one would be.
        return null;
      }
    }
    return null;
  }
}
