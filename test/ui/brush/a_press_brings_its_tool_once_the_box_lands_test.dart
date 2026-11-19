import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/brush/tool_press.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

/// 🗣️F-615-Q2 (유저 2026-11-19, 「착지하고 나서 바꾼다」): with a range
/// moved in the box and not confirmed, a press that brings another tool
/// lands the box first and brings the tool once it has — every tool's
/// entrance through the notifier's one door ([PaintToolStateNotifier.bring]).
void main() {
  PaintToolStateNotifier toolsOn(
    _Door door, {
    CanvasTool tool = CanvasTool.move,
  }) => PaintToolStateNotifier(
    BrushToolState.defaults.copyWith(tool: tool),
    landsFirst: door.land,
  );

  test('a press for another tool waits for the landing, and brings its tool '
      'once it is done', () {
    final door = _Door();
    final tools = toolsOn(door);
    var pressed = 0;

    tools.bring(CanvasTool.eraser, () {
      pressed += 1;
      tools.value = tools.value.copyWith(tool: CanvasTool.eraser);
    });
    expect(door.waiting, hasLength(1), reason: 'it asked the door');
    expect((pressed, tools.value.tool), (0, CanvasTool.move));

    door.open();
    expect((pressed, tools.value.tool), (1, CanvasTool.eraser));
  });

  test('a press for the tool in hand runs at once — the door is not asked',
      () {
    final door = _Door();
    final tools = toolsOn(door);
    var pressed = 0;

    tools.bring(CanvasTool.move, () => pressed += 1);
    expect(door.waiting, isEmpty);
    expect(pressed, 1);
  });

  test('with no door, a press runs at once', () {
    final tools = PaintToolStateNotifier(BrushToolState.defaults);
    tools.bring(
      CanvasTool.eraser,
      () => tools.value = tools.value.copyWith(tool: CanvasTool.eraser),
    );
    expect(tools.value.tool, CanvasTool.eraser);
  });

  test('a press pressed while one waits takes its place: a hold let go '
      'before its tool came never held it', () {
    final door = _Door();
    final tools = toolsOn(door);
    final ran = <String>[];

    tools.bring(CanvasTool.eyedropper, () {
      ran.add('hold');
      tools.value = tools.value.copyWith(tool: CanvasTool.eyedropper);
    });
    tools.bring(CanvasTool.move, () {
      ran.add('let go');
      tools.value = tools.value.copyWith(tool: CanvasTool.move);
    });
    expect(door.waiting, hasLength(1), reason: 'one landing for the two');

    door.open();
    expect(ran, ['let go']);
    expect(tools.value.tool, CanvasTool.move);

    tools.bring(CanvasTool.eraser, () => ran.add('next'));
    expect(
      door.waiting,
      hasLength(1),
      reason: 'with nothing waiting, the next press asks the door again',
    );
  });

  test('a held tool is taken up on the state in hand when it comes: a '
      'colour picked while it waits stays', () {
    final door = _Door();
    final tools = toolsOn(door);

    tools.bringTool(CanvasTool.eyedropper);
    tools.value = tools.value.copyWith(color: 0xFF123456);
    expect(tools.value.tool, CanvasTool.move);

    door.open();
    expect((tools.value.tool, tools.value.color), (
      CanvasTool.eyedropper,
      0xFF123456,
    ));
  });

  group('the rail, a tile and a tool key — pressTool', () {
    test('a tool of another group comes once the landing is done', () {
      final door = _Door();
      final tools = toolsOn(door);
      final transform = ValueNotifier(TransformToolOptions.defaults);

      pressTool(
        const RailToolPress(CanvasTool.brush),
        tool: tools,
        transform: transform,
      );
      expect(tools.value.tool, CanvasTool.move);

      door.open();
      expect(tools.value.tool, CanvasTool.brush);
    });

    test('a transform mode with the transform tool in hand is a setting of '
        'the open box: it lands nothing, at once', () {
      final door = _Door();
      final tools = toolsOn(door);
      final transform = ValueNotifier(TransformToolOptions.defaults);
      final other = TransformMode.values.firstWhere(
        (mode) => mode != transform.value.mode,
      );

      pressTool(TransformModePress(other), tool: tools, transform: transform);
      expect(door.waiting, isEmpty);
      expect(transform.value.mode, other);
    });

    test('a transform mode from another tool lands first, then sets its '
        'mode and brings the transform tool', () {
      final door = _Door();
      final tools = toolsOn(door, tool: CanvasTool.select);
      final transform = ValueNotifier(TransformToolOptions.defaults);
      final before = transform.value.mode;
      final other = TransformMode.values.firstWhere((mode) => mode != before);

      pressTool(TransformModePress(other), tool: tools, transform: transform);
      expect((transform.value.mode, tools.value.tool), (
        before,
        CanvasTool.select,
      ));

      door.open();
      expect((transform.value.mode, tools.value.tool), (
        other,
        CanvasTool.move,
      ));
    });
  });
}

/// A door that holds what it is to run until the test lets it.
final class _Door {
  final List<VoidCallback> waiting = [];

  void land(VoidCallback then) => waiting.add(then);

  void open() {
    final held = [...waiting];
    waiting.clear();
    for (final then in held) {
      then();
    }
  }
}
