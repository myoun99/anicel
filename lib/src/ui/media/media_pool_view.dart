import 'package:flutter/foundation.dart' show immutable;

/// How the media pool shows its files — the two buttons right of its ＋
/// (🗣️asset-placement-presets Q4 · Q6, 유저 2026-11-17: 「프리미어처럼」 ·
/// 「시안대로 — 위 툴바(＋ 줄 오른쪽)」): a line each or big pictures, and
/// each file as it is or as its preset would place it.
///
/// ⛔Two buttons, two fields: the SHAPE (a line · a picture) and the FACE
/// (the file · its preset) are separate answers and mix freely — one flag
/// answering both would be a flag answering two questions.
@immutable
final class MediaPoolView {
  const MediaPoolView({this.icons = false, this.presets = false});

  /// Big pictures rather than a line each.
  final bool icons;

  /// Each file as its preset would place it rather than as it is.
  final bool presets;

  MediaPoolView copyWith({bool? icons, bool? presets}) => MediaPoolView(
    icons: icons ?? this.icons,
    presets: presets ?? this.presets,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaPoolView &&
      other.icons == icons &&
      other.presets == presets;

  @override
  int get hashCode => Object.hash(icons, presets);
}
