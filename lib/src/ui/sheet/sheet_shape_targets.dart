import 'package:flutter/widgets.dart';

import '../canvas/interactive_brush_edit_canvas_view.dart'
    show ContentShapeTarget;

/// What takes the shape tool's shape on a sheet (F-420): the sheet's ink
/// layer answers here while the brush is on, and the sheet's panel asks at
/// the shape tool's press ([SheetShapeScope]).
class SheetShapeTargets {
  ContentShapeTarget? Function(Offset global)? _answer;
  bool Function(Offset global)? _takes;

  /// The view a press at [global] lands its shape in — none where the ink
  /// is off, or nothing there takes it.
  ContentShapeTarget? at(Offset global) => _answer?.call(global);

  /// Whether a press at [global] is the sheet's own before any tool's — a
  /// photo's (I-97-Q3: 「브러시 허용이면 어느 도구든 사진을 누르면 집는다」).
  bool takesPressAt(Offset global) => _takes?.call(global) ?? false;

  /// [answer] and [takes] say from now on.
  void answerWith(
    ContentShapeTarget? Function(Offset global) answer, {
    required bool Function(Offset global) takes,
  }) {
    _answer = answer;
    _takes = takes;
  }

  /// [answer] stops saying, and the [takes] given with it — unless another
  /// has taken their place.
  void stopAnswering(ContentShapeTarget? Function(Offset global) answer) {
    if (identical(_answer, answer)) {
      _answer = null;
      _takes = null;
    }
  }
}

/// A sheet panel's [SheetShapeTargets], over the content it lays on the
/// paper — where its ink layer finds them.
class SheetShapeScope extends InheritedWidget {
  const SheetShapeScope({
    super.key,
    required this.targets,
    required super.child,
  });

  final SheetShapeTargets targets;

  static SheetShapeTargets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetShapeScope>()?.targets;

  @override
  bool updateShouldNotify(SheetShapeScope oldWidget) =>
      !identical(oldWidget.targets, targets);
}
