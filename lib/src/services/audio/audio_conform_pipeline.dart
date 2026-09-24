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
/// Layout. ONE copy, and its address says how far along it is.
///
/// ```
/// 프로젝트.anicel
///   media/<hash>-대사.m4a[.z]                    the sound itself
///   conform/<hash>-대사.m4a[.z]                  its decoded PCM
/// <app container>/Sessions/<run>/Staged/
///   대사.m4a.<hash>.wav[.z]                      built, not yet absorbed
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
/// 🪦**AND THE 「CACHE vs CARRIED COPY」 DUALISM IS GONE.** This file used
/// to insist the two were not redundant — 「the cache is what playback
/// reads, the carried copy is what a machine with an empty cache restores
/// FROM」— and an asset with both「genuinely costs both」. 유저 2026-09-07
/// looked at that and asked the obvious question: 「디코드된 PCM이 그럼
/// 두벌 존재하는거지? 진짜 그냥 사본파일인거아니야?」. It was. Playback
/// now reads a [MediaByteSource], so the copy inside the project IS what
/// it reads and nothing is restored out of the archive to make a file for
/// it. What is left in the container is only what has not been saved yet,
/// in the run's own scratch room ([SessionScratch]) — the same lifetime
/// carried media has, for the same reason.
///
/// ⚠️The address keys on the sample rate and audio speed. Change either
/// and the conform for the new settings is at a different address, nothing
/// is found there, and the save carries none — which is how the entry for
/// the old one gets removed rather than accumulating (유저: 「레이트 변경
/// 등 죽은파일만 깔끔하게 잘 걷어낼것」).
///
/// 🔑 It is keyed by the SOURCE and the settings it was rendered under —
/// never by the project, which is what an earlier layout did back when
/// this was a folder beside the `.anicel`. Keying by the project meant a
/// Save As abandoned every conform it had built, two projects using one
/// sound each paid for their own copy, and a project with no name yet got
/// nowhere to put one. See [ConformCacheLayout].
library;

import 'dart:io';
import 'dart:typed_data';

import '../../models/media_asset.dart' show normalizedMediaPath;
import '../media/media_byte_source.dart';
import '../persistence/anicel_incremental_writer.dart'
    show anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;
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
/// span ([MediaByteSource.span]), and the native decoder takes exactly
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
  /// NOT the ordinary "nowhere to write it" case any more: permissions, a
  /// full disk or a cloud folder mid-sync leave the decoded audio intact,
  /// so [AudioConformPipeline.ensureConform] returns [built] with null
  /// [ConformResult.conformBytes] and the reason in `error`. Losing the
  /// sound over a place to put it was the bug. What is left here is the
  /// store's catch-all wrapper.
  writeFailed,
}

class ConformResult {
  const ConformResult({
    required this.outcome,
    this.conformBytes,
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

  /// WHERE THIS CONFORM'S BYTES ARE — a file in the run's scratch before
  /// the project has been saved, a range inside the `.anicel` after.
  ///
  /// 🚨★★★**ONE FIELD, BECAUSE IT IS ONE QUESTION.** This used to be a
  /// `conformPath` string, which could only name a file — so a conform the
  /// project already carried had to be COPIED OUT of the archive into the
  /// container before anything could read it. That copy was the second
  /// copy of the same PCM (유저 2026-09-07: 「디코드된 PCM이 그럼 두벌
  /// 존재하는거지? 진짜 그냥 사본파일인거아니야?」), and there is no such
  /// thing as a file that is「in the project」and「in the cache」without
  /// somebody deciding which one is the truth.
  ///
  /// [MediaByteSource] already says 「wherever these bytes are」 for media;
  /// saying it for conforms too is what lets playback read straight out of
  /// the project file — [ConformPcmStreamReader.over] takes exactly this.
  final MediaByteSource? conformBytes;

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
    final normalized = normalizedMediaPath(mediaPath);
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

  /// The fingerprint [source] carries — the IDENTITY, content-derived so it
  /// survives being copied to another machine — without holding the source.
  ///
  /// 🪦A twin that took the bytes whole, `fingerprintOf(Uint8List)`, went
  /// with its last caller (2026-09-24): 「a caller holding bytes has already
  /// paid for them」, and no caller should be holding them.
  ///
  /// 🚨★★★**A FINGERPRINT MUST NOT COST AN ALLOCATION THE SIZE OF THE FILE.**
  /// This is the identity of a possibly-enormous container, and the whole
  /// point of the range decode is undone if the check in front of it reads
  /// the file into memory first. `anicelCrc32Update` exists for exactly this
  /// — the archive writer folds a streamed entry the same way, for the same
  /// reason.
  ///
  /// ⚠️It reads the source's OWN bytes a window at a time
  /// ([MediaByteSource.openWindowReader]) — for a framed source, decoded, so
  /// the identity is the medium's whichever way it is stored. 🪦A framed
  /// source used to be read whole here, on the grounds that 「nothing
  /// enormous is stored framed … a movie does not shrink」. Both halves were
  /// guesses, and wrong: compression is decided per file and an MP4 shrinks
  /// 6.7% (2026-09-24).
  static ConformSourceFingerprint fingerprintOfSource(MediaByteSource source) {
    var state = anicelCrc32Start;
    final buffer = Uint8List(_fingerprintChunkBytes);
    var read = 0;
    final reader = source.openWindowReader();
    try {
      while (true) {
        final got = reader.readIntoSync(buffer, read, buffer.length);
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
      reader.close();
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
  /// [readFrom] is where the conform was actually read — the scratch file
  /// in the `.z` spelling or the plain one, or a range inside the project
  /// file — never the base name the request carried.
  ///
  /// 🪦It used to TOUCH that file's mtime, because eviction order was
  /// 「least recently used」 and the mtime was the only record of wanting.
  /// There is no eviction any more: a conform lives in the run's scratch
  /// until the save absorbs it, and the room goes when the run does.
  ConformResult _reuse(ConformAudio existing, MediaByteSource? readFrom) {
    return ConformResult(
      outcome: ConformOutcome.reused,
      conformBytes: readFrom,
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

    // 🚨★★★**THE PROJECT'S OWN COPY IS READ WHERE IT LIES.** 유저
    // 2026-08-30 chose to carry conforms inside the `.anicel`
    // (`conform-in-project` = always), and on another machine — where the
    // scratch is empty and the project holds the conform — that is now
    // simply the place the bytes are read from.
    //
    // 🪦It used to be COPIED OUT of the archive into the container first,
    // so that「the ordinary path」could find a file. That copy was a second
    // copy of the same PCM, which is what the user objected to (2026-09-07:
    // 「디코드된 PCM이 그럼 두벌 존재하는거지? 진짜 그냥 사본파일인거
    // 아니야?」), and it also meant an hour of dialogue was written twice
    // on every open. ⛔The scratch is asked FIRST all the same: a conform
    // built since the last save is newer than the carried one.
    final cached =
        (conformPath == null ? null : _readConform(conformPath)) ??
        (carriedConform == null ? null : _readConformFrom(carriedConform));
    final existing = cached?.audio;
    // Where the conform was READ from — the scratch file in either
    // spelling, or the range inside the project file.
    final reusableAt = cached?.bytes;
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
    if (settingsMatch && stat != null && existing.sourceStat == stat) {
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
          sourceStat: stat,
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
      conformBytes: cachedAt == null ? null : mediaAppFileSource(cachedAt),
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


  /// The conform cached under [basePath], and WHICH of its two names it is
  /// actually under.
  ///
  /// A cached conform is compressed when that was worth it, so it wears
  /// `.z` or it does not — [mediaFramedOrPlainPaths] is the one place that
  /// knows the order to ask in, and [mediaAppFileSource] the one place that
  /// knows the name decides how to read it.
  /// The conform sitting beside [basePath] in either spelling, or null.
  ({ConformAudio audio, MediaByteSource bytes})? _readConform(
    String basePath,
  ) {
    for (final candidate in mediaFramedOrPlainPaths(basePath)) {
      if (!File(candidate).existsSync()) {
        continue;
      }
      return _readConformFrom(mediaAppFileSource(candidate));
    }
    return null;
  }

  /// The same read, from wherever the bytes are.
  ///
  /// 🚨This is what lets a conform the project CARRIES be played without
  /// being copied out first: an archive range answers `readSync` like a
  /// file does, and everything below judges it by the same settings and
  /// fingerprint checks a locally built one faces. ⛔It is read, not
  /// trusted — deciding staleness twice is how two answers drift apart.
  ({ConformAudio audio, MediaByteSource bytes})? _readConformFrom(
    MediaByteSource source,
  ) {
    try {
      return (audio: decodeConform(source.readSync()), bytes: source);
    } on Object {
      // Unreadable, foreign, or framed with no engine on this build:
      // rebuilt, exactly as a missing one would be.
      return null;
    }
  }
}
