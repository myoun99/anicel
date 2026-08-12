import 'media_asset.dart';

/// What ONE viewer was looking at, remembered with the film (유저 확정 ⑤
/// ㉑, 2026-08-12).
///
/// PROJECT data, not app data: which reference belongs beside which
/// drawing is a fact about the work, and the app-level workspace layout
/// file is shared by every project. It rides the same rule
/// `ExportProjectOverrides` does — it travels with the film, but it is
/// not a document EDIT, so it is written straight through the repository
/// with no history entry. Turning a reference page must never land in
/// undo, and it must never make the project dirty on its own.
///
/// That last part has a consequence the user accepted: open a reference,
/// draw nothing, close — and the choice is not saved, because nothing
/// asked to save. Draw one stroke and it rides along.
class MediaViewerBookmark {
  const MediaViewerBookmark({
    required this.path,
    required this.kind,
    this.name,
    this.position = 0,
  });

  /// The file. For a pooled asset this is its pool key; for a file opened
  /// straight from the picker it is an absolute path that means nothing
  /// on another machine — remembered anyway (유저 확정 ⑭), because a
  /// reference that fails to come back costs a person one reopen, while
  /// forgetting half of them costs a rule nobody can predict.
  final String path;

  final MediaAssetKind kind;

  /// The pooled asset's display name, when it had one.
  final String? name;

  /// How far into the document — see `MediaViewerTabHost.position`.
  final int position;

  MediaViewerBookmark copyWith({
    String? path,
    MediaAssetKind? kind,
    String? name,
    int? position,
  }) => MediaViewerBookmark(
    path: path ?? this.path,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    position: position ?? this.position,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.name,
    if (name != null) 'name': name,
    if (position != 0) 'position': position,
  };

  /// Null for anything this build cannot make sense of — a hand-edited
  /// file or one from a version that spelled a kind differently must lose
  /// a bookmark, never the project.
  static MediaViewerBookmark? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final path = json['path'];
    if (path is! String || path.isEmpty) {
      return null;
    }
    final kindName = json['kind'];
    final kind = MediaAssetKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    if (kind == null) {
      return null;
    }
    final name = json['name'];
    final position = json['position'];
    return MediaViewerBookmark(
      path: path,
      kind: kind,
      name: name is String ? name : null,
      position: position is int && position >= 0 ? position : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaViewerBookmark &&
      other.path == path &&
      other.kind == kind &&
      other.name == name &&
      other.position == position;

  @override
  int get hashCode => Object.hash(path, kind, name, position);
}

/// The remembered documents of every viewer, keyed by the viewer's panel
/// id. A map rather than two fields: the ids are the panel registry's
/// already, and a viewer that no longer exists simply has no reader.
typedef MediaViewerBookmarks = Map<String, MediaViewerBookmark>;

MediaViewerBookmarks mediaViewerBookmarksFromJson(Object? json) {
  if (json is! Map) {
    return const {};
  }
  return {
    for (final entry in json.entries)
      if (entry.key is String)
        entry.key as String: ?MediaViewerBookmark.fromJson(entry.value),
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
