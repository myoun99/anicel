import 'package:flutter/foundation.dart';

import '../../models/brush_group_id.dart';

/// The tab a brush library is LOOKING INTO while the hand cannot say it —
/// null, which is nearly always, while the library shows the tab of the
/// brush in hand.
///
/// 🗣️F-319 (유저 2026-10-08): 「브러시는 항상 선택된그룹/브러시 를 보여줌.
/// 지금 브러시 선택하다 지우개 선택하면 도구라이브러리에서 다른곳에 있는
/// 브러시로 바껴야하는데 바뀌지않음. 계속해서 이런 선택된걸 제대로
/// 표시안하는걸 몇번째 피드백하는지모르겟는데」 · 「이상한건 됫다가 말았다가
/// 함」.
///
/// THE TAB SHOWN IS THE HELD BRUSH'S. What stands here is only a tab the
/// hand has no brush in — one with no brush to take up (an empty group), or
/// the one a dragged brush is held over — and it ends the moment the hand
/// is another: another brush, another tool. The record is there so that
/// 「looking into the root section」 (a null group) is not 「looking into
/// nothing」.
///
/// 🚨ONE FOR THE TOOL LIBRARY, AND ITS OWNER KEEPS IT: settles it when a tab
/// is pressed ([settle]) and ends it when the hand changes ([end]). The
/// library's panel is kept alive once for EACH paint tool
/// (`KeyedKeepAliveStack`), and one kept off stage is not rebuilt when
/// another tool comes to hand — nothing its props could tell it.
/// ↩️Each panel kept its own, and kept it by itself: first as a latch
/// (`_tabChosen`: 「Unset until the user picks one, so the panel can follow
/// the selection」 — one tap, and that panel never followed again), and a
/// group's KEY reached 「the panel」 through one slot the last panel mounted
/// had taken (`BrushLibraryKeys.enterTab`). So with the brush in hand the
/// key turned the ERASER's tab, off stage, and the eraser came to hand
/// showing a tab its brush was not in — and which of the two was the last
/// mounted depended on the order the tools had been taken up in that
/// session.
class BrushLibraryLook extends ValueNotifier<({BrushGroupId? group})?> {
  BrushLibraryLook() : super(null);

  /// A tab was PRESSED — tapped, or by its key. [held] is the tab the hand's
  /// brush shows in once the press has done what it does to the hand, or
  /// null while it holds no brush the library can name: the hand says the
  /// tab pressed, and nothing is looked into; or it cannot, and the tab is.
  void settle(
    BrushGroupId? pressed, {
    required ({BrushGroupId? group})? held,
  }) => value = held == (group: pressed) ? null : (group: pressed);

  /// The hand is another — the library shows what it holds now.
  void end() => value = null;
}
