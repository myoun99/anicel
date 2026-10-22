import '../../models/canvas_viewport.dart';
import '../../services/persistence/anicel_project_archive.dart'
    show anicelObjectMapField;

/// THE VIEW EACH FILE WAS LEFT AT IN THE VIEWERS (F-382, 유저 2026-10-17:
/// 「뷰어패널에서 파일을 마지막에 봣던 상태를 기억하게하고싶음 … 줌 상태나
/// 페이지상태등이 기억되서 다른 파일 열엇다가 돌아오면 그대로 열리도록」).
///
/// View state, like `TimelineZoomMemory` — held by the SESSION for its
/// reason (I-7, a project per tab) and saved beside the project
/// (`ProjectResume.mediaFileViews`): looking at a reference is not an edit.
///
/// 🚨THE PAGE IS THE FILE'S, THE FRAMING IS THE VIEWER'S. A file comes back
/// at the page it was last seen at in either viewer — as a swap carries the
/// page across with the file (유저 확정 ⑪⑯⑰: 「page 37 of the conte is still
/// page 37 when it lands on the floor」). How it was framed is kept for each
/// viewer apart: the two are different sizes, which is why a swap frames
/// what arrives anew rather than carrying the other viewer's view.
///
/// Both kinds of file alike — a pooled one by its pool key, a loose one by
/// the path it was opened from (유저: 「참조로 연 파일은 … 간단하면 해도됨」;
/// it is the same key either way).
class MediaFileViews {
  final Map<String, int> _pages = {};
  final Map<String, Map<String, CanvasViewport>> _framings = {};

  /// The page [path] was left at — its first when it never was turned.
  int pageOf(String path) => _pages[path] ?? 0;

  /// The view [viewer] left [path] framed at, or null when it never framed
  /// it — then it is fitted, as any file is the first time.
  CanvasViewport? framingOf(String path, {required String viewer}) =>
      _framings[path]?[viewer];

  /// [path] is now seen at [page].
  void rememberPage(String path, int page) {
    if (page > 0) {
      _pages[path] = page;
    } else {
      _pages.remove(path);
    }
  }

  /// [viewer] now shows [path] framed at [framing].
  void rememberFraming(
    String path, {
    required String viewer,
    required CanvasViewport framing,
  }) => (_framings[path] ??= {})[viewer] = framing;

  /// Every file's view, as a save writes it.
  Map<String, MediaFileView> get views => {
    for (final path in {..._pages.keys, ..._framings.keys})
      path: MediaFileView(
        page: pageOf(path),
        framings: Map.unmodifiable(_framings[path] ?? const {}),
      ),
  };

  /// Each file [saved] names, put back where it was left.
  void standAt(Map<String, MediaFileView> saved) {
    for (final MapEntry(key: path, value: view) in saved.entries) {
      rememberPage(path, view.page);
      for (final MapEntry(key: viewer, value: framing)
          in view.framings.entries) {
        rememberFraming(path, viewer: viewer, framing: framing);
      }
    }
  }
}

/// One file's view as a save writes it — see [MediaFileViews].
class MediaFileView {
  const MediaFileView({this.page = 0, this.framings = const {}});

  final int page;

  /// The view each viewer left the file framed at, by the viewer's panel id
  /// (as `MediaViewerBookmarks` names them).
  final Map<String, CanvasViewport> framings;

  Map<String, Object?> toJson() => {
    if (page > 0) 'page': page,
    if (framings.isNotEmpty)
      'framings': {
        for (final MapEntry(key: viewer, value: framing) in framings.entries)
          viewer: framing.toJson(),
      },
  };

  /// The view [json] holds — null when it holds nothing readable. Each part
  /// answers for itself, as every part of a resume does: a framing nobody
  /// can read is dropped alone, and the page still lands.
  static MediaFileView? fromJson(Object? json) {
    final map = anicelObjectMapField(json);
    final page = switch (map['page']) {
      final int page when page > 0 => page,
      _ => 0,
    };
    final framings = {
      for (final MapEntry(:key, :value)
          in anicelObjectMapField(map['framings']).entries)
        if (CanvasViewport.fromJson(value) case final framing?
            when key.isNotEmpty)
          key: framing,
    };
    return page == 0 && framings.isEmpty
        ? null
        : MediaFileView(page: page, framings: framings);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaFileView &&
      other.page == page &&
      other.framings.length == framings.length &&
      framings.entries.every(
        (entry) => other.framings[entry.key] == entry.value,
      );

  @override
  int get hashCode => Object.hash(
    page,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in framings.entries)
        Object.hash(key, value),
    ]),
  );
}
