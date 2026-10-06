import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/temporary_tool.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_key_holds.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';

/// 🗣️I-15 (유저 2026-09-11): 「단축키에 이동? 추가 … 기본값을 … 스페이스바로
/// 이동 … 스포이드는 그대로 해서 누르는동안 툴 바뀌도록. 툴 바껴서 해당툴을
/// 사용한다는 심플한 규칙」 — one law for every held input: while it is held
/// its action is in force, and letting go ends it.
///
/// The road is the shell's own: the shortcut manager with the holds on it,
/// a focus inside, and the keyboard's real events.
void main() {
  late ToolHoldMemory memory;
  late ValueNotifier<BrushToolState> tool;
  late ValueNotifier<bool> strokeLive;
  late EditorShortcutBindings bindings;
  late EditorKeyHolds holds;

  Widget road(Widget focused) => MaterialApp(
    home: Shortcuts.manager(
      manager: EditorShortcutManager(
        shortcuts: bindings.shortcuts,
        onHoldKey: holds.engage,
      ),
      child: Material(child: focused),
    ),
  );

  Future<void> pumpRoad(
    WidgetTester tester, {
    Widget Function()? focused,
  }) async {
    memory = ToolHoldMemory();
    tool = ValueNotifier(BrushToolState.defaults);
    addTearDown(tool.dispose);
    strokeLive = ValueNotifier(false);
    addTearDown(strokeLive.dispose);
    bindings = EditorShortcutBindings();
    holds = EditorKeyHolds(
      bindings: bindings,
      tool: tool,
      temporaryTool: TemporaryTool(
        memory: memory,
        current: () => tool.value,
        change: (next) => tool.value = next,
      ),
      strokeLive: strokeLive,
    );
    addTearDown(holds.dispose);
    await tester.pumpWidget(
      road(
        focused?.call() ??
            const Focus(autofocus: true, child: SizedBox.expand()),
      ),
    );
    await tester.pump();
  }

  testWidgets('Space held is the pan: taken whole, repeats and all — and '
      'letting go lets go', (tester) async {
    await pumpRoad(tester);
    expect(CanvasPanHold.held.value, isFalse);

    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isTrue);
    expect(CanvasPanHold.held.value, isTrue);
    expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space), isTrue);
    expect(CanvasPanHold.held.value, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(CanvasPanHold.held.value, isFalse);
  });

  testWidgets('a focused text field keeps its space bar — no pan', (
    tester,
  ) async {
    await pumpRoad(tester, focused: () => const TextField(autofocus: true));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasPanHold.held.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  });

  testWidgets('the pan follows its binding: moved to Z, Z holds it and Space '
      'does not — a chord it was not bound as is not it, and two keys '
      'bound to it are one hold', (tester) async {
    await pumpRoad(tester);
    bindings.setActivators(EditorActionIds.canvasPanHold, const [
      SingleActivator(LogicalKeyboardKey.keyZ),
      SingleActivator(LogicalKeyboardKey.keyX),
    ]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasPanHold.held.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // The character a real keyboard types here — a typed form for letters
    // would take exactly this for Z.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ, character: 'Z');
    expect(CanvasPanHold.held.value, isFalse, reason: 'Shift+Z is not Z');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    expect(CanvasPanHold.held.value, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    expect(CanvasPanHold.held.value, isTrue, reason: 'X still holds it');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    expect(CanvasPanHold.held.value, isFalse);
  });

  // 🚨A KEY IS THE CHARACTER IT TYPES (a-key-is-the-character-it-types): a
  // held key asks the same forms the shortcut map is built from. On a JIS
  // keyboard `'` is Shift+7 — `7` with Shift held, typing `'`.
  testWidgets('the pan moved to `\'` is held by a JIS Shift+7', (
    tester,
  ) async {
    await pumpRoad(tester);
    bindings.setActivators(EditorActionIds.canvasPanHold, const [
      SingleActivator(LogicalKeyboardKey.quoteSingle),
    ]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7, character: "'");
    expect(CanvasPanHold.held.value, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
    expect(CanvasPanHold.held.value, isFalse, reason: 'letting go lets go');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('⛔Shift+Space is still not the pan — the typed form is for a '
      'printed character a layout puts on Shift, and a space is none', (
    tester,
  ) async {
    await pumpRoad(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space, character: ' ');
    expect(
      CanvasPanHold.held.value,
      isFalse,
      reason: 'Shift+Space is not Space',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  /// 🗣️F-299 (유저 2026-10-05): 「채우기 도구인상태에서 스포이드 단축키로 도구
  /// 안바뀜. **어떤 도구 들고있던 규칙 만들지말고 법 통일해서 작동하도록**」.
  /// ↩️The hold took only over the brush, the eraser and the bucket.
  testWidgets('🚨Alt IS the eyedropper while held, whatever tool is in hand; '
      'letting go returns the tool it replaced', (tester) async {
    expect(
      {..._whereAltIsTheEyedropper, ..._whereAltIsTheToolsOwn},
      CanvasTool.values.toSet(),
      reason: 'a new tool has to say where its Alt goes',
    );
    await pumpRoad(tester);
    for (final inHand in _whereAltIsTheEyedropper) {
      tool.value = tool.value.copyWith(tool: inHand);
      expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft),
        isFalse,
        reason: 'Alt passes on — it still modifies what it is held with',
      );
      expect(tool.value.tool, CanvasTool.eyedropper, reason: '$inHand');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(tool.value.tool, inHand);
      expect(memory.sprangFrom, isNull);
    }
  });

  testWidgets('the two tools whose own drag reads Alt keep it — the '
      'selection subtracts with it, the transform scales about the far '
      'corner (F-299-Q1)', (tester) async {
    await pumpRoad(tester);
    for (final own in _whereAltIsTheToolsOwn) {
      tool.value = tool.value.copyWith(tool: own);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      expect(tool.value.tool, own);
      expect(memory.sprangFrom, isNull, reason: 'no hold was taken');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(tool.value.tool, own);
    }
  });

  testWidgets('both Alt keys are one hold — the tool returns only when the '
      'last of them lets go', (tester) async {
    await pumpRoad(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
    expect(tool.value.tool, CanvasTool.eyedropper);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
    expect(
      tool.value.tool,
      CanvasTool.eyedropper,
      reason: 'the left Alt still holds it',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush);
  });

  testWidgets('an Alt that comes down mid-stroke never takes the live line '
      '— it takes hold when the stroke ends, and not before', (tester) async {
    await pumpRoad(tester);
    strokeLive.value = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush);

    // A stroke that ends and a new one that starts before the wait
    // resolved: the new one is live, so the wait goes on.
    strokeLive.value = false;
    strokeLive.value = true;
    await tester.pump();
    expect(tool.value.tool, CanvasTool.brush);

    strokeLive.value = false;
    await tester.pump();
    expect(tool.value.tool, CanvasTool.eyedropper);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush);

    // Let go mid-stroke, and nothing is left waiting.
    strokeLive.value = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    strokeLive.value = false;
    await tester.pump();
    expect(tool.value.tool, CanvasTool.brush);
  });

  testWidgets('a stroke that ends inside a TEARDOWN — a panel unmounting '
      'mid-stroke — switches the tool after it, never inside it', (
    tester,
  ) async {
    Widget deck({required bool panel}) => Column(
      children: [
        const Focus(autofocus: true, child: SizedBox(height: 10)),
        ValueListenableBuilder<BrushToolState>(
          valueListenable: tool,
          builder: (context, state, _) => Text(state.tool.name),
        ),
        if (panel) _EndsTheStrokeOnDispose(strokeLive),
      ],
    );
    await pumpRoad(tester, focused: () => deck(panel: true));
    strokeLive.value = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);

    await tester.pumpWidget(road(deck(panel: false)));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text(CanvasTool.eyedropper.name), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.text(CanvasTool.brush.name), findsOneWidget);
  });

  testWidgets('a held key and a held pen button share ONE road: when they '
      'overlap, the tool from before either of them comes back', (
    tester,
  ) async {
    await pumpRoad(tester);
    // PEN-7a: the barrel button mapped to the eraser, held.
    final penButton = TemporaryTool(
      memory: memory,
      current: () => tool.value,
      change: (next) => tool.value = next,
    );
    penButton.hold(CanvasTool.eraser);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.eyedropper);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush);
    penButton.release(keep: false);
    expect(tool.value.tool, CanvasTool.brush);

    // A mapping that KEEPS the tool leaves it in hand.
    penButton.hold(CanvasTool.eraser);
    penButton.release(keep: true);
    expect(tool.value.tool, CanvasTool.eraser);
    expect(memory.sprangFrom, isNull);
  });

  testWidgets('🚨F-232: a window that loses the OS\'s focus lets go of every '
      'hold — the pan AND the eyedropper — because the key will be let go '
      'where this window never hears it', (tester) async {
    await pumpRoad(tester);
    tool.value = tool.value.copyWith(tool: CanvasTool.brush);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(CanvasPanHold.held.value, isTrue);
    expect(tool.value.tool, CanvasTool.eyedropper, reason: 'fixture');

    holds.letGoOfEverything();

    expect(CanvasPanHold.held.value, isFalse);
    expect(tool.value.tool, CanvasTool.brush, reason: 'the tool it replaced');
    // The releases the other app got are never heard; one that does come
    // back later finds nothing to end.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(tool.value.tool, CanvasTool.brush);
  });

  testWidgets('and an Alt that came down mid-stroke, still waiting for the '
      'stroke to end, is let go of too', (tester) async {
    await pumpRoad(tester);
    tool.value = tool.value.copyWith(tool: CanvasTool.brush);
    strokeLive.value = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush, reason: 'fixture: it waits');

    holds.letGoOfEverything();
    strokeLive.value = false;
    await tester.pump();

    expect(
      tool.value.tool,
      CanvasTool.brush,
      reason: 'a key the window lost is not taken when the stroke ends',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  });

  testWidgets('a shell that goes away lets go of the pan', (tester) async {
    await pumpRoad(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasPanHold.held.value, isTrue);

    holds.dispose();
    expect(CanvasPanHold.held.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(CanvasPanHold.held.value, isFalse);
  });

  testWidgets('🚨I-7: pointed at another project\'s stroke, the holds wait on '
      'THAT one — the one they left no longer counts', (tester) async {
    await pumpRoad(tester);
    final onScreen = ValueNotifier(true);
    addTearDown(onScreen.dispose);
    holds.strokeLive = onScreen;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush, reason: 'its stroke is live');

    strokeLive.value = true;
    strokeLive.value = false;
    await tester.pump();
    expect(
      tool.value.tool,
      CanvasTool.brush,
      reason: 'the project behind finishing a stroke frees nothing',
    );

    onScreen.value = false;
    await tester.pump();
    expect(tool.value.tool, CanvasTool.eyedropper);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(tool.value.tool, CanvasTool.brush);
  });
}

/// Every tool but the two below — spelled out, so that a tool added later
/// is in neither list until someone has said which it belongs in.
const _whereAltIsTheEyedropper = [
  CanvasTool.brush,
  CanvasTool.eraser,
  CanvasTool.eyedropper,
  CanvasTool.fill,
  CanvasTool.fillShape,
  CanvasTool.guide,
  CanvasTool.cut,
  CanvasTool.cutStamp,
];

/// The tools whose own drag reads Alt: the selection (subtract; with Shift,
/// intersect) and the transform (scale about the far corner).
const _whereAltIsTheToolsOwn = [CanvasTool.select, CanvasTool.move];

/// What the canvas panel does on the way out: a mid-stroke teardown lets
/// go of the stroke.
class _EndsTheStrokeOnDispose extends StatefulWidget {
  const _EndsTheStrokeOnDispose(this.strokeLive);

  final ValueNotifier<bool> strokeLive;

  @override
  State<_EndsTheStrokeOnDispose> createState() =>
      _EndsTheStrokeOnDisposeState();
}

class _EndsTheStrokeOnDisposeState extends State<_EndsTheStrokeOnDispose> {
  @override
  void dispose() {
    widget.strokeLive.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
