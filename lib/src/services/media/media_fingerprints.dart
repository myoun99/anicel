import '../../models/media_identity.dart';

/// Content fingerprints for the project's media, held OUTSIDE the project.
///
/// 🔑 Why they live out here rather than on [MediaAsset.identity], where the
/// length already sits: **recording one is not something the user did.** The
/// length is imprinted by an import, which is an edit and may dirty the
/// project. A CRC arrives later — the moment anything reads an asset's bytes
/// for its own reasons — and a viewer showing a picture must not raise a
/// save prompt. The same law the security-scoped bookmarks follow, and the
/// same shape: the session holds the map, the save is handed it, and the
/// format layer writes plain JSON it does not have to understand.
///
/// The whole point is answering "is THIS the file that went missing?" for a
/// path that no longer resolves. That question is only ever asked about a
/// REFERENCE — what the project carries inside itself cannot go missing —
/// so a fingerprint has to be recorded while the file is still there, which
/// is why every free chance to record one is taken.
class MediaFingerprints {
  const MediaFingerprints(this._byPath);

  const MediaFingerprints.empty() : _byPath = const {};

  final Map<String, MediaIdentity> _byPath;

  bool get isEmpty => _byPath.isEmpty;

  MediaIdentity? operator [](String poolPath) =>
      _byPath[normalizeFingerprintPath(poolPath)];

  /// What is known about [poolPath], preferring a recorded fingerprint over
  /// [recorded] — the length an import imprinted.
  ///
  /// 🚨 A fingerprint answers with ITS OWN length, never [recorded]'s. The
  /// two are taken at different moments and a file can change between them:
  /// `MediaAsset.identity` is written once, at first registration, while a
  /// fingerprint is re-taken every time something reads the bytes. Welding
  /// a stale length onto a fresh CRC describes a revision that never
  /// existed, and relink would then rule OUT the very file it is hunting —
  /// its length disagrees with the record, which `compare` treats as
  /// decisive. Both halves have to come from one read or they are not one
  /// fact.
  MediaIdentity? identityFor(String poolPath, MediaIdentity? recorded) =>
      this[poolPath] ?? recorded;

  /// This map plus [identity] for [poolPath], or this map unchanged when it
  /// already said exactly that.
  ///
  /// Returning the same instance on a no-op is what lets a caller skip
  /// storing anything at all — promotion happens on a read path, and a
  /// picture the user flips back to should cost nothing the second time.
  MediaFingerprints remembering(String poolPath, MediaIdentity identity) {
    final key = normalizeFingerprintPath(poolPath);
    if (_byPath[key] == identity) {
      return this;
    }
    return MediaFingerprints({..._byPath, key: identity});
  }

  /// The same facts under new paths.
  ///
  /// 🚨 EVERY place a pool path changes has to come through here, or the
  /// fact is silently dropped at the next save — the store is keyed by path
  /// and the save keeps only keys the pool still holds. There are three
  /// such places and they were not obvious: opening a project whose folder
  /// traveled, a bookmark resolving to a file the user moved, and RELINK
  /// itself. The last one is the cruel case: relink is the feature these
  /// exist for, and it was throwing away the fingerprint it had just used.
  MediaFingerprints moved(Map<String, String> moves) {
    if (moves.isEmpty || isEmpty) {
      return this;
    }
    final next = <String, MediaIdentity>{};
    for (final entry in _byPath.entries) {
      final to = moves[entry.key];
      next[to == null ? entry.key : normalizeFingerprintPath(to)] = entry.value;
    }
    return MediaFingerprints(next);
  }

  /// Only the entries for [keep], with [moved] paths renamed.
  ///
  /// Both halves matter on open. A project that traveled has its references
  /// resolved to where they landed, and a fingerprint filed under the old
  /// path would then describe nothing; and an asset removed from the pool
  /// must not keep a row here for ever, or the file grows a fingerprint per
  /// asset the project has ever held.
  MediaFingerprints narrowedTo(
    Set<String> keep, {
    Map<String, String> moved = const {},
  }) {
    final kept = <String, MediaIdentity>{};
    for (final entry in this.moved(moved)._byPath.entries) {
      if (keep.contains(entry.key)) {
        kept[entry.key] = entry.value;
      }
    }
    return MediaFingerprints(kept);
  }

  /// `{path: "<length>:<crc32 hex>"}` — the same short spelling
  /// [MediaIdentity] already uses, so `project.json` gains one string per
  /// asset rather than an object, and the round trip is code that already
  /// exists rather than a second parser to keep in step.
  Map<String, Object?> toJson() => {
    for (final entry in _byPath.entries) entry.key: entry.value.toJson(),
  };

  /// Reads back [toJson], skipping anything unrecognized so a file written
  /// by a future build cannot make an older one throw on open.
  static MediaFingerprints fromJson(Object? json) {
    if (json is! Map) {
      return const MediaFingerprints.empty();
    }
    final parsed = <String, MediaIdentity>{};
    for (final entry in json.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        continue;
      }
      final identity = MediaIdentity.fromJson(entry.value);
      // Length-only rows are dropped rather than kept: the length already
      // lives on the asset, so a row without a CRC is a row that says
      // nothing new and would only be a second place to disagree from.
      if (identity?.crc32 == null) {
        continue;
      }
      parsed[normalizeFingerprintPath(key)] = identity!;
    }
    return MediaFingerprints(parsed);
  }
}

/// One spelling, the way the media pool itself is keyed — `C:\a\b.wav` and
/// `C:/a/b.wav` are one file and must not be two rows.
String normalizeFingerprintPath(String path) => path.replaceAll('\\', '/');
