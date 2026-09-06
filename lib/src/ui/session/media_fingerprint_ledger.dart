// What the session knows about the CONTENT of the files its media pool
// names — kept beside the project rather than inside it, because learning
// it is not an edit the user made.
//
// Its own object since round 8 (G1, 2026-09-06): the map and the four
// verbs over it were host members that nothing but each other touched,
// and the import doors and the save both need them.

import 'package:flutter/foundation.dart';

import '../../models/media_asset.dart';
import '../../services/media/media_fingerprints.dart';
import '../../services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;
import 'session_roles.dart';

/// Content fingerprints for the pool, held OUT of the project.
///
/// 🚨 Out here because recording one is not an edit. The length on
/// [MediaAsset.identity] is imprinted by an import, which the user did;
/// a CRC arrives whenever something reads an asset's bytes for its own
/// reasons, which the user did not — and a viewer showing a picture must
/// not put a dot on the title bar. Same law as the session's stored
/// grants, same shape: this map rides to the writer as an argument, never
/// through `Project`.
class MediaFingerprintLedger {
  MediaFingerprintLedger({required ProjectAccess project}) : _project = project;

  final ProjectAccess _project;

  MediaFingerprints _fingerprints = const MediaFingerprints.empty();

  List<MediaAsset> get _pool =>
      _project.repository.requireProject().mediaAssets;

  /// What is known about [poolPath]'s content: the length the import
  /// imprinted, plus the CRC if anyone has paid for one.
  ///
  /// Null when the pool has no such asset, or when even the length is
  /// missing — which is every asset registered by a build that predates
  /// [MediaIdentity], and is exactly the case that must answer "unknown"
  /// rather than guess.
  MediaIdentity? recordedMediaIdentity(String poolPath) {
    final wanted = normalizedMediaPath(poolPath);
    for (final asset in _pool) {
      if (normalizedMediaPath(asset.path) == wanted) {
        return _fingerprints.identityFor(wanted, asset.identity);
      }
    }
    return null;
  }

  /// Records that [poolPath]'s bytes hash to [crc32], because something
  /// read them anyway.
  ///
  /// 🔑 Deliberately NOT an edit: no command, no undo entry, no dirty
  /// flag, no notify. Flipping through the media pool must not make the
  /// project look unsaved. The price is that a fingerprint learned in a
  /// session that never saves is forgotten, which is the right way round —
  /// it is a cache of something re-derivable, and the file it describes is
  /// still there to be read again.
  ///
  /// Takes any path, registered or not. An import reads the bytes BEFORE
  /// it knows whether the import will happen, so demanding the asset exist
  /// first would forfeit the one reading that is guaranteed free. What
  /// reaches the FILE is narrowed to the pool at save time instead, which
  /// is where the same filter has to run anyway for assets since removed.
  void rememberMediaFingerprint(String poolPath, Uint8List bytes) {
    _fingerprints = _fingerprints.remembering(
      poolPath,
      // Both halves from THESE bytes. Taking the length off the asset
      // instead would weld a value imprinted at first registration onto a
      // hash taken now, and a file edited in between would be described as
      // a revision that never existed.
      MediaIdentity(lengthBytes: bytes.length, crc32: anicelCrc32(bytes)),
    );
  }

  /// Follows [moves] (old pool path → new) so a fingerprint survives its
  /// asset being pointed somewhere else.
  ///
  /// 🚨 Called from every place a pool path changes. The store is keyed by
  /// path and the save keeps only keys the pool still holds, so a move that
  /// skips this does not merely mislay the fact — the next save DELETES it.
  void moveMediaFingerprints(Map<String, String> moves) {
    _fingerprints = _fingerprints.moved(moves);
  }

  /// What an opened file said this project knows about its media.
  void restoreFromFile(MediaFingerprints loaded) {
    _fingerprints = loaded;
  }

  /// The fingerprints as the file should keep them: only for media the
  /// project still references.
  Map<String, Object?> crcsToStore() => _fingerprints.narrowedTo({
    for (final asset in _pool) normalizedMediaPath(asset.path),
  }).toJson();

  @visibleForTesting
  MediaFingerprints get debugMediaFingerprints => _fingerprints;
}
