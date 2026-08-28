import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
    tx: 0,
    ty: 0,
    rotationDegrees: rotation,
    scale: scale,
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

    expect(commands.recallFor(TransformMode.normal)!.scale, 1.2);
    expect(
      commands.recallFor(TransformMode.perspective)!.hasPerspective,
      isTrue,
    );
    // ⛔THE POINT. The 퍼스 entry's affine is identity, so a shared slot
    // would have made 일반's Enter do NOTHING once a warp landed last.
    expect(
      commands.recallFor(TransformMode.perspective)!.scale,
      1,
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

    expect(commands.recallFor(TransformMode.normal)!.scale, 2);
    expect(
      commands.recallFor(TransformMode.perspective)!.rotationDegrees,
      24,
      reason: '퍼스 was not touched, so 퍼스 still remembers',
    );
  });
}
