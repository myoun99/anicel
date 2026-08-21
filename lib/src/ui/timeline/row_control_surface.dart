import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A CONTROL, not a place to grab the row by (H1, 유저 2026-08-21).
///
/// > 「지금 레이어 선택범위시 **버튼쪽 탭다운해서 움직이면 선택범위
/// > 작동해버리는데** 보통 그게 아니잖아? **버튼쪽 클릭하면 선택범위 작동
/// > 안 하도록.** 그 외 부분. **레이어이름영역이나 그 외 버튼 요소가 아닌
/// > 부분만** 작동하도록」
///
/// The row's drag recognizer wraps the WHOLE row — it has to, because the
/// name area and the blank space between controls are the surface you grab
/// a row by, and those are not widgets of their own. So the exclusion
/// cannot be "the drag covers less"; it has to be "this pixel belongs to a
/// control", asked at the moment the press lands.
///
/// ★A MARKER rather than a list of types. Asking "is the thing under the
/// pointer a button?" by class would be a list to maintain, and the day a
/// row grows a control that is not on it, the row starts moving when that
/// control is pressed — the exact defect this removes. The rail's shared
/// slot builder marks every slot that HOLDS something, so a control added
/// later is covered by construction and a slot left empty stays grabbable
/// (reserved space is not a button).
class RowControlSurface extends StatelessWidget {
  const RowControlSurface({super.key, required this.child});

  final Widget child;

  /// The sentinel the hit-test looks for. Identity, not a type: any
  /// widget may carry it without inheriting anything.
  static const Object marker = _RowControlSurfaceMarker();

  /// Whether the press at [globalPosition] landed on a control INSIDE the
  /// subtree of [host].
  ///
  /// Hit-tests the live tree rather than reading geometry: the rail folds
  /// its columns as the panel narrows, so "which slots are where" is a
  /// layout answer only the render tree has, and it moves with the
  /// splitter mid-session.
  ///
  /// ⛔Scoped to [host] rather than asking the whole view. A row must
  /// answer about ITSELF: a global hit-test would also see whatever floats
  /// over the panel, so a tooltip or a drag preview passing above the rail
  /// would start refusing drags on rows it merely covers.
  static bool covers(BuildContext host, Offset globalPosition) {
    final box = host.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return false;
    }
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(globalPosition));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && identical(target.metaData, marker)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => MetaData(
    metaData: marker,
    // TRANSLUCENT: the control underneath must still receive the press.
    // This widget adds itself to the hit path; it does not take the path
    // away from what it wraps.
    behavior: HitTestBehavior.translucent,
    child: child,
  );
}

class _RowControlSurfaceMarker {
  const _RowControlSurfaceMarker();
}
