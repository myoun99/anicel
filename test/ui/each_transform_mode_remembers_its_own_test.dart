import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/transform_values.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

/// 🚨★★★EACH TRANSFORM MODE REMEMBERS ITS OWN (confirm-button ②).
///
/// 유저 2026-08-27: 「**툴마다 기억하는게 다름**: 일반변형 고른 상태로
/// 엔터하면 직전 일반변형 값을 재현, 자유변형 고른 상태로 엔터하면 직전
/// 자유변형을 재현. **두 번째 엔터에서 확정**」.
///
/// One slot could only answer for whichever mode committed LAST. Arming
/// 일반 and pressing Enter replayed a 퍼스 warp — or, when that warp's
/// affine happened to be identity, did nothing at all and read as a dead
/// key.
///
/// ⛔THIS IS NOT THE AXIS 08-13 SETTLED. That day's 「전역 하나」 was about
/// not keying the recall PER LAYER (「어떤 크기의 소재든 같은 값을
/// 변형주도록」) and still holds — nothing here is a layer's. Mode is a
/// different question and the user answered it separately.
void main() {
  TransformRecall recall({
    double scale = 1,
    double rotation = 0,
    List<CanvasPoint> corners = const [],
  }) => TransformRecall(
    values: TransformValues(sx: scale, sy: scale, rotationDegrees: rotation),
    cornerOffsets: corners,
  );

  test('a mode reads back what IT committed', () {
    final commands = CanvasSelectionCommands();
    addTearDown(commands.dispose);

    commands.transformRecalls[TransformMode.normal] = recall(scale: 1.2);
    commands.transformRecalls[TransformMode.perspective] = recall(
      corners: [
        CanvasPoint(x: 4, y: 0),
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 0, y: 0),
      ],
    );

    expect(commands.recallFor(TransformMode.normal)!.values.sx, 1.2);
    expect(
      commands.recallFor(TransformMode.perspective)!.hasPerspective,
      isTrue,
    );
    // ⛔THE POINT. The 퍼스 entry's affine is identity, so a shared slot
    // would have made 일반's Enter do NOTHING once a warp landed last.
    expect(
      commands.recallFor(TransformMode.perspective)!.values.isIdentity,
      isTrue,
      reason:
          'the warp carried no scale — which is exactly the case that '
          'made one shared slot read as a dead key',
    );
  });

  test('a mode nobody has committed in has nothing to replay', () {
    final commands = CanvasSelectionCommands();
    addTearDown(commands.dispose);
    commands.transformRecalls[TransformMode.normal] = recall(scale: 1.2);

    expect(
      commands.recallFor(TransformMode.mesh),
      isNull,
      reason:
          'Enter in 메쉬 must not replay somebody else\'s transform — the '
          'old single slot would have handed it 일반\'s',
    );
  });

  test('committing again in one mode leaves the other alone', () {
    // 🚨The drift a shared slot guaranteed: every commit overwrote the one
    // memory, so the two modes could never both be remembered at once.
    final commands = CanvasSelectionCommands();
    addTearDown(commands.dispose);

    commands.transformRecalls[TransformMode.normal] = recall(scale: 1.2);
    commands.transformRecalls[TransformMode.perspective] = recall(rotation: 24);
    commands.transformRecalls[TransformMode.normal] = recall(scale: 2);

    expect(commands.recallFor(TransformMode.normal)!.values.sx, 2);
    expect(
      commands.recallFor(TransformMode.perspective)!.values.rotationDegrees,
      24,
      reason: '퍼스 was not touched, so 퍼스 still remembers',
    );
  });

  // 🗣️유저 2026-10-03 (F-265): 「변형으로 좌우반전하고, 다음프레임에서 기록된
  // 내역대로 하려고 엔터누르니 좌우반전이아니라 좌우/상하반전이 됨」. A recall
  // was worth offering only when ITS ONE scale — the horizontal — had moved,
  // so a 상하반전, or a stretch along the vertical alone, left nothing to
  // replay.
  test('🚨a recall that changed ONE axis is worth offering, whichever axis', () {
    for (final values in const [
      TransformValues(sx: -1),
      TransformValues(sy: -1),
      TransformValues(sx: 1.5),
      TransformValues(sy: 1.5),
    ]) {
      expect(
        TransformRecall(values: values).isIdentity,
        isFalse,
        reason: '$values',
      );
    }
    expect(
      const TransformRecall(values: TransformValues.identity).isIdentity,
      isTrue,
    );
    expect(
      const TransformRecall(
        values: TransformValues(anchorX: 12, anchorY: -3),
      ).isIdentity,
      isTrue,
      reason: 'the cross moved alone changes no pixel — nothing to replay',
    );
  });
}
