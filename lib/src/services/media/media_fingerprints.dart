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
  const MediaFingerprints(this._crc32ByPath);

  const MediaFingerprints.empty() : _crc32ByPath = const {};

  final Map<String, int> _crc32ByPath;

  bool get isEmpty => _crc32ByPath.isEmpty;

  int? crc32For(String poolPath) => _crc32ByPath[normalizeFingerprintPath(poolPath)];

  /// [recorded] with whatever content fingerprint is known for [poolPath].
  ///
  /// Returns null when the project never recorded even a length, because a
  /// CRC with no length beside it cannot answer "different" cheaply and this
  /// type promises the cheap half first.
  MediaIdentity? identityFor(String poolPath, MediaIdentity? recorded) {
    if (recorded == null) {
      return null;
    }
    final crc = crc32For(poolPath);
    if (crc == null || recorded.crc32 == crc) {
      return recorded;
    }
    return MediaIdentity(lengthBytes: recorded.lengthBytes, crc32: crc);
  }

  /// This map plus [crc32] for [poolPath], or this map unchanged when it
  /// already said so.
  ///
  /// Returning the same instance on a no-op is what lets a caller skip
  /// storing anything at all — promotion happens on a read path, and a
  /// picture the user flips back to should cost nothing the second time.
  MediaFingerprints remembering(String poolPath, int crc32) {
    final key = normalizeFingerprintPath(poolPath);
    if (_crc32ByPath[key] == crc32) {
      return this;
    }
    return MediaFingerprints({..._crc32ByPath, key: crc32});
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
    final kept = <String, int>{};
    for (final entry in _crc32ByPath.entries) {
      final path = normalizeFingerprintPath(moved[entry.key] ?? entry.key);
      if (keep.contains(path)) {
        kept[path] = entry.value;
      }
    }
    return MediaFingerprints(kept);
  }

  /// `{path: "<crc32 hex>"}` — hex strings rather than ints because a CRC
  /// fills 32 bits and JSON numbers are doubles in enough readers that
  /// writing one is asking for a value that comes back rounded.
  Map<String, Object?> toJson() => {
    for (final entry in _crc32ByPath.entries)
      entry.key: entry.value.toRadixString(16),
  };

  /// Reads back [toJson], skipping anything unrecognized so a file written
  /// by a future build cannot make an older one throw on open.
  static MediaFingerprints fromJson(Object? json) {
    if (json is! Map) {
      return const MediaFingerprints.empty();
    }
    final parsed = <String, int>{};
    for (final entry in json.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty) {
        continue;
      }
      final crc = value is int ? value : int.tryParse('$value', radix: 16);
      if (crc == null) {
        continue;
      }
      parsed[normalizeFingerprintPath(key)] = crc;
    }
    return MediaFingerprints(parsed);
  }
}

/// One spelling, the way the media pool itself is keyed — `C:\a\b.wav` and
/// `C:/a/b.wav` are one file and must not be two rows.
String normalizeFingerprintPath(String path) => path.replaceAll('\\', '/');
