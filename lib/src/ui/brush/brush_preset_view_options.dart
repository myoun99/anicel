import 'package:flutter/foundation.dart' show immutable;

/// How the brush library panel shows its rows and its rail — the five view
/// toggles of the panel's options menu.
///
/// 🚨F-73 ① (유저 2026-09-11): 「브러시 탭 그룹 이름이나 스트로크 프리뷰 상태가
/// 저장안됨. 그룹 이름을 해제하거나 스트로크 이름이랑 프리뷰 해제하고 패널닫고
/// 다시열면 리셋되있음」. They lived in the panel's State, and the Tool Library
/// tab keeps no State once it closes — every close forgot them. They are view
/// preferences, not library data (a library handed to someone else must not
/// carry how you like your rail), so they are kept where the panel layout is:
/// the workspace file.
@immutable
class BrushPresetViewOptions {
  const BrushPresetViewOptions({
    this.showTipIcon = true,
    this.showStrokePreview = true,
    this.showName = true,
    this.railShowIcon = true,
    this.railShowName = true,
  });

  /// Reads what [toJson] wrote. A key that is missing or not a bool is its
  /// default, so a file from before a toggle existed opens as it always did.
  ///
  /// ⚠️A row or a tab that shows NOTHING is not an arrangement the menu can
  /// make — it keeps one of a row's three and one of a tab's two on — so a
  /// file that says so opens that group of toggles at its defaults rather
  /// than as blank rows.
  factory BrushPresetViewOptions.fromJson(Map<String, Object?> json) {
    bool read(String key) => switch (json[key]) {
      final bool value => value,
      _ => true,
    };
    var tipIcon = read('tipIcon');
    var strokePreview = read('strokePreview');
    var name = read('name');
    if (!tipIcon && !strokePreview && !name) {
      tipIcon = strokePreview = name = true;
    }
    var railIcon = read('railIcon');
    var railName = read('railName');
    if (!railIcon && !railName) {
      railIcon = railName = true;
    }
    return BrushPresetViewOptions(
      showTipIcon: tipIcon,
      showStrokePreview: strokePreview,
      showName: name,
      railShowIcon: railIcon,
      railShowName: railName,
    );
  }

  final bool showTipIcon;
  final bool showStrokePreview;
  final bool showName;
  final bool railShowIcon;

  /// 🚨NAMES ARE ON BY DEFAULT (유저 2026-09-08: 「그룹쪽은 대신 아이콘
  /// 버튼이아니라 **아이콘+이름**으로 해서, 이름 넣을수있게 가로로 좀 더
  /// 길게해주고」).
  ///
  /// ⚠️Nothing was built for this — the named rail has existed since
  /// 2026-07-27 (`_BrushGroupTab.namedWidth`, 96px) and only ever opened
  /// closed. The toggle stays: 유저 confirmed 「토글은 그대로 남김」, so a
  /// narrow screen can still trade the names back for 70px of brush list.
  /// (Moved here from the panel's State with the default it explains.)
  final bool railShowName;

  BrushPresetViewOptions copyWith({
    bool? showTipIcon,
    bool? showStrokePreview,
    bool? showName,
    bool? railShowIcon,
    bool? railShowName,
  }) => BrushPresetViewOptions(
    showTipIcon: showTipIcon ?? this.showTipIcon,
    showStrokePreview: showStrokePreview ?? this.showStrokePreview,
    showName: showName ?? this.showName,
    railShowIcon: railShowIcon ?? this.railShowIcon,
    railShowName: railShowName ?? this.railShowName,
  );

  Map<String, Object?> toJson() => {
    'tipIcon': showTipIcon,
    'strokePreview': showStrokePreview,
    'name': showName,
    'railIcon': railShowIcon,
    'railName': railShowName,
  };

  @override
  bool operator ==(Object other) =>
      other is BrushPresetViewOptions &&
      other.showTipIcon == showTipIcon &&
      other.showStrokePreview == showStrokePreview &&
      other.showName == showName &&
      other.railShowIcon == railShowIcon &&
      other.railShowName == railShowName;

  @override
  int get hashCode => Object.hash(
    showTipIcon,
    showStrokePreview,
    showName,
    railShowIcon,
    railShowName,
  );
}
