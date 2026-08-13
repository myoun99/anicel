/// Whether two files are the SAME FILE — the question relink asks.
///
/// Deliberately not [MediaAsset.sourceStamp], which answers a different
/// question that looks identical from a distance: "did the original change
/// since we took our copy?" (the re-import badge, §6-g). That stamp carries
/// the modification time, so it stops matching the moment a file is moved,
/// copied or restored from a backup — which is precisely the situation
/// relink exists for. One field cannot answer both: the badge NEEDS to
/// notice a touched file, and identity needs to survive one.
///
/// So identity carries only what travels with the bytes.
library;

/// What comparing two identities is allowed to conclude.
///
/// Three values rather than a bool, because "we have no evidence" is a real
/// and common answer here and it must not be spelled `false`. Equal lengths
/// alone do not make two files the same file; a caller that treats them as
/// a match picks a wrong drawing for someone.
enum MediaIdentityMatch {
  /// Same bytes, as far as anything recorded can tell.
  same,

  /// Provably not the same file.
  different,

  /// Not enough was recorded to say. The caller must not guess — the
  /// relink rule is that an unforced choice is not made.
  unknown,
}

/// What is known about a file's content, cheap parts first.
class MediaIdentity {
  const MediaIdentity({required this.lengthBytes, this.crc32});

  /// Size in bytes. Always recorded: `stat` answers it without reading a
  /// byte, and a mismatch here is a decisive NO for free. Two different
  /// drawings that happen to share the name `A1.png` almost always differ
  /// here, which is what makes the cheap half worth having on its own.
  final int lengthBytes;

  /// CRC-32 of the content, or null when nobody has paid for one.
  ///
  /// Null is the ordinary state, not a defect. Reading a file end to end to
  /// record this at import time would cost a full pass over every reference
  /// — and after the media move the files that STAY references are the big
  /// ones (video is reference-only by kind), so that pass is exactly the
  /// one nobody can afford. It gets filled in later, by whoever happens to
  /// read the bytes for another reason.
  final int? crc32;

  /// What [other] is to this, as far as both sides recorded.
  ///
  /// Length disagreeing is decisive; length agreeing is not. A CRC decides
  /// only when BOTH sides have one, because a null on either side means no
  /// one ever looked.
  MediaIdentityMatch compare(MediaIdentity other) {
    if (lengthBytes != other.lengthBytes) {
      return MediaIdentityMatch.different;
    }
    final mine = crc32;
    final theirs = other.crc32;
    if (mine == null || theirs == null) {
      return MediaIdentityMatch.unknown;
    }
    return mine == theirs
        ? MediaIdentityMatch.same
        : MediaIdentityMatch.different;
  }

  /// `<length>` or `<length>:<crc32 hex>` — a string like the stamp beside
  /// it, so `project.json` gains a short value rather than an object.
  String toJson() =>
      crc32 == null ? '$lengthBytes' : '$lengthBytes:${crc32!.toRadixString(16)}';

  /// Reads back [toJson]; null for anything unrecognized, so a file written
  /// by a future build cannot make an older one throw on open.
  static MediaIdentity? fromJson(Object? json) {
    if (json is! String || json.isEmpty) {
      return null;
    }
    final colon = json.indexOf(':');
    final lengthText = colon < 0 ? json : json.substring(0, colon);
    final length = int.tryParse(lengthText);
    if (length == null || length < 0) {
      return null;
    }
    if (colon < 0) {
      return MediaIdentity(lengthBytes: length);
    }
    final crc = int.tryParse(json.substring(colon + 1), radix: 16);
    return MediaIdentity(lengthBytes: length, crc32: crc);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaIdentity &&
          other.lengthBytes == lengthBytes &&
          other.crc32 == crc32;

  @override
  int get hashCode => Object.hash(lengthBytes, crc32);

  @override
  String toString() => 'MediaIdentity(${toJson()})';
}
