import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/boolean_dot_probe.dart';
import 'package:anicel/src/models/transform_values.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

/// R26 #14: the Move/Transform settings' x/y/angle/scale are the shared
/// DRAG VALUE readouts (the canvas bar's zoom/angle vocabulary) — a
/// label drag writes through the selection channel, and the fields no
/// longer demand a selection first (R26 #13: none = whole picture).

/// What the box held after each write, in order.
///
/// ↩️It was four doubles — what `setTransformValues` was called with — and
/// a second list for the anchor's own verb. A write is a CHANGE to the
/// box's values now (F-265 · F-256), so the stand-in holds a box and each
/// entry is everything that box then held: a channel that restated a value
/// it did not mean shows up as that value moving.
typedef AppliedTransform = TransformValues;

void main() {
  /// A channel bound to a box that stands at [start] and keeps whatever a
  /// write leaves in it, recording each state in [applied].
  void bindBox(
    CanvasSelectionCommands commands, {
    required List<AppliedTransform> applied,
    TransformValues start = TransformValues.identity,
    bool canEdit = true,
    bool canApply = false,
    VoidCallback? beginTransformStep,
  }) {
    var held = start;
    commands.bind(
      Object(),
      hasSelection: () => false,
      canEditTransform: () => canEdit,
      canApplyTransform: () => canApply,
      deselect: () {},
      transformValues: () => held,
      editTransformValues: (change) {
        held = change(held);
        applied.add(held);
        // As the layer does after every edit: the digits read this.
        commands.publishTransformValues(held);
      },
      beginTransformStep: beginTransformStep,
    );
  }

  Future<CanvasSelectionCommands> pumpMoveSettings(
    WidgetTester tester, {
    required List<AppliedTransform> applied,
    TransformValues start = TransformValues.identity,
    ResampleMode resampleMode = ResampleMode.blend,
    ValueChanged<ResampleMode>? onResampleModeChanged,
    bool canEdit = true,
    bool canApply = false,
    TransformMode mode = TransformMode.normal,
    // Whether the two scale rows move together (F-256-Q2) — on, as the
    // tool begins.
    bool scaleLinked = true,
    ValueChanged<TransformToolOptions>? onOptionsChanged,
  }) async {
    // The panel takes the whole knob set as one object; most of this suite
    // cares about the AA half, so it unwraps that one field back out.
    final resampleHandler = onResampleModeChanged;
    final commands = CanvasSelectionCommands();
    bindBox(
      commands,
      applied: applied,
      start: start,
      canEdit: canEdit,
      canApply: canApply,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 320,
            height: 480,
            child: ToolSettingsPanel(
              state: BrushToolState.defaults.copyWith(tool: CanvasTool.move),
              onChanged: (_) {},
              fillOptions: const FloodFillOptions(),
              onFillOptionsChanged: (_) {},
              selectionCommands: commands,
              transformOptions: TransformToolOptions(
                mode: mode,
                resampleMode: resampleMode,
                scaleLinked: scaleLinked,
              ),
              onTransformOptionsChanged:
                  resampleHandler == null && onOptionsChanged == null
                  ? null
                  : (options) {
                      resampleHandler?.call(options.resampleMode);
                      onOptionsChanged?.call(options);
                    },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return commands;
  }

  /// Types [text] into the readout [key]: a press that moved nothing opens
  /// its editor, and Enter commits.
  Future<void> typeInto(WidgetTester tester, String key, String text) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ValueKey<String>('$key-input')), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('an X-label drag accumulates units and writes them through '
      'the channel — no selection required', (tester) async {
    final applied = <AppliedTransform>[];
    await pumpMoveSettings(tester, applied: applied);

    // A comfortably slop-clearing drag; the exact delivered delta is
    // slop-dependent, the CONTRACT is that units accumulate into tx.
    await tester.drag(
      find.byKey(const ValueKey<String>('move-x-field')),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    // Clear the double-tap recognizer's pending window.
    await tester.pump(const Duration(milliseconds: 500));

    expect(applied, isNotEmpty, reason: 'the drag writes live');
    expect(applied.last.tx, greaterThan(20));
    expect(
      applied.last,
      TransformValues(tx: applied.last.tx),
      reason: 'and it wrote X alone',
    );
  });

  /// 🚨★★★**A CHANNEL WRITES THE ONE VALUE IT NAMES** (F-265 · F-256).
  ///
  /// 🗣️유저 2026-10-03: 「변형으로 좌우반전하고 … 좌우반전이아니라
  /// 좌우/상하반전이 됨 … 반전을 숫자로서 표현못하는게 원인인거같으니
  /// 구조적으로 해결」 · 10-01: 「가로에 대한 단독배율변경같은게 저장안됨.
  /// 가로세로 통합으로서 … 기록됨」.
  ///
  /// ↩️Every scrub restated all four of this panel's own copies, and its
  /// copy of the scale was ONE number. 🧪Measured 2026-10-06 on the box
  /// below: a scrub on X put a 상하반전 back upright, and clamped a
  /// 좌우반전's −100% to 1%.
  ///
  /// ⛔Every value differs from every other here, and from the identity —
  /// a row that restated a neighbour's, or a default, moves something.
  const stretched = TransformValues(
    sx: -1.5,
    sy: 0.75,
    rotationDegrees: 20,
    tx: 6,
    ty: -9,
    anchorX: 4,
    anchorY: -3,
  );

  /// Each row, as the one value it names: how it reads off the box and
  /// how the box looks with that value replaced.
  final rows =
      <
        String,
        ({
          double Function(TransformValues values) read,
          TransformValues Function(TransformValues values, double to) write,
        })
      >{
        'move-x-field': (
          read: (values) => values.tx,
          write: (values, to) => values.copyWith(tx: to),
        ),
        'move-y-field': (
          read: (values) => values.ty,
          write: (values, to) => values.copyWith(ty: to),
        ),
        'move-angle-field': (
          read: (values) => values.rotationDegrees,
          write: (values, to) => values.copyWith(rotationDegrees: to),
        ),
        'move-scale-x-field': (
          read: (values) => values.sx,
          write: (values, to) => values.copyWith(sx: to),
        ),
        'move-scale-y-field': (
          read: (values) => values.sy,
          write: (values, to) => values.copyWith(sy: to),
        ),
        'move-anchor-x-field': (
          read: (values) => values.anchorX,
          write: (values, to) => values.copyWith(anchorX: to),
        ),
        'move-anchor-y-field': (
          read: (values) => values.anchorY,
          write: (values, to) => values.copyWith(anchorY: to),
        ),
      };

  /// ⚠️With the scales UNLINKED — the two scale rows are the only ones the
  /// link reaches, and linked they carry each other by design (below).
  testWidgets('🚨a scrub on a row moves that row\'s value and no other — a '
      'mirror, a one-axis stretch and the cross stay as they are', (
    tester,
  ) async {
    final commands = await pumpMoveSettings(
      tester,
      applied: [],
      scaleLinked: false,
    );
    for (final row in rows.entries) {
      final applied = <AppliedTransform>[];
      bindBox(commands, applied: applied, start: stretched);
      await tester.pump();

      // ⚠️Horizontal, like every other channel: the shared readout reads a
      // unit per pixel ALONG THE LABEL, whatever value it carries.
      await tester.drag(
        find.byKey(ValueKey<String>(row.key)),
        const Offset(60, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(applied, isNotEmpty, reason: '${row.key}: the drag writes live');
      final after = applied.last;
      expect(
        row.value.read(after),
        isNot(row.value.read(stretched)),
        reason: '${row.key} moved its own value',
      );
      expect(
        after,
        row.value.write(stretched, row.value.read(after)),
        reason: '⛔${row.key} moved more than its own value',
      );
    }
  });

  testWidgets('each scale row reads its own axis with its sign, and a typed '
      'minus is the mirror', (tester) async {
    final applied = <AppliedTransform>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      start: stretched,
      scaleLinked: false,
    );

    expect(find.text('-150%'), findsOneWidget, reason: '가로: 반전 + 150%');
    expect(find.text('75%'), findsOneWidget, reason: '세로: 75%');

    await typeInto(tester, 'move-scale-y-field', '-100');

    expect(applied.last, stretched.copyWith(sy: -1));
    expect(find.text('-100%'), findsOneWidget);
  });

  /// 🚨★★★**⑤ONE SCRUB IS ONE STEP BACK, not forty.**
  ///
  /// 🗣️유저 2026-09-20: 「변형에 대한 **조작마다** 언두로 기록」. A label
  /// scrub writes a value per pixel; only the label knows where the
  /// operation began, so it is the label that says so.
  testWidgets('⑤a label scrub announces ONE operation, a press that only '
      'opens the editor announces none', (tester) async {
    final applied = <AppliedTransform>[];
    var steps = 0;
    final commands = await pumpMoveSettings(tester, applied: applied);
    bindBox(
      commands,
      applied: applied,
      beginTransformStep: () => steps += 1,
    );
    await tester.pump();

    // ⚠️A hand-driven gesture, not `tester.drag`: that delivers the whole
    // travel as ONE update, so it writes once and the pin would pass on a
    // build that announced an operation per write.
    final scrub = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('move-x-field'))),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 4; i += 1) {
      await scrub.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await scrub.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      applied.length,
      greaterThan(1),
      reason: '⛔전제: the scrub really did write many times',
    );
    expect(steps, 1, reason: 'and it was ONE operation');
    // Each write adds to what the BOX holds by then, not to a number this
    // panel last heard at rest — there is nothing for a late ping to eat.
    for (var i = 1; i < applied.length; i += 1) {
      expect(
        applied[i].tx,
        greaterThan(applied[i - 1].tx),
        reason: 'write $i went on from write ${i - 1}',
      );
    }

    // A press that never moves the value opens the text field instead —
    // nothing has happened yet, so there is nothing to step back to.
    await tester.tap(find.byKey(const ValueKey<String>('move-y-field')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(steps, 1, reason: '⛔a tap is not an operation');
  });

  testWidgets('a scale never rests on zero, and never past the ceiling — '
      'either way round', (tester) async {
    // The floor is the box law's, with its sign (`TransformBoxLaw
    // .clampScale`): a number taken through zero mirrors, as a handle taken
    // through the centre does. ↩️It stopped at +1% — there was one scale,
    // and a minus was not a thing a number could say.
    final applied = <AppliedTransform>[];
    final commands = await pumpMoveSettings(
      tester,
      applied: applied,
      scaleLinked: false,
    );

    await typeInto(tester, 'move-scale-x-field', '0');
    expect(applied.last.sx, 0.01);
    await typeInto(tester, 'move-scale-x-field', '-0.2');
    expect(applied.last.sx, -0.01);
    await typeInto(tester, 'move-scale-x-field', '99999');
    expect(applied.last.sx, 32);
    await typeInto(tester, 'move-scale-y-field', '-99999');
    expect(applied.last.sy, -32);
    expect(applied.last.sx, 32, reason: 'and the other axis kept its own');
    expect(commands.transformValues, applied.last);
  });

  /// 🚨★★★**THE CHAIN** — F-256-Q2 (유저 2026-10-06): 「연동 스위치(AE 의
  /// 사슬) — 켜면 한 칸을 바꿀 때 다른 칸도 같은 비율로」, of the option that
  /// read 「지금의 가로 · 세로 비율과 반전은 지킨다」.
  ///
  /// The two rows became two so that each could say its own axis (F-256 ·
  /// F-265). Linked, a row still names its axis — and carries the other by
  /// the size of the step, leaving its sign alone.
  group('with the scales linked — AE\'s chain', () {
    // 200% across, a mirrored 100% down: a ratio and a sign to keep.
    const wide = TransformValues(sx: 2, sy: -1, tx: 6, rotationDegrees: 20);

    testWidgets('🚨a typed scale carries the other axis by the same ratio, '
        'and each keeps its own sign', (tester) async {
      final applied = <AppliedTransform>[];
      await pumpMoveSettings(tester, applied: applied, start: wide);

      await typeInto(tester, 'move-scale-x-field', '300');
      expect(applied.last, wide.copyWith(sx: 3, sy: -1.5));

      // Down the other row: 150% → 50% is a third, so 300% → 100%.
      await typeInto(tester, 'move-scale-y-field', '-50');
      expect(applied.last.sy, -0.5);
      expect(applied.last.sx, closeTo(1, 1e-9));
    });

    testWidgets('🚨a typed MINUS mirrors that axis and no other', (
      tester,
    ) async {
      final applied = <AppliedTransform>[];
      await pumpMoveSettings(tester, applied: applied, start: wide);

      await typeInto(tester, 'move-scale-x-field', '-200');

      expect(
        applied.last,
        wide.copyWith(sx: -2),
        reason: 'the same size, so the other axis is where it was — and '
            'still the way up it was',
      );
    });

    testWidgets('a scrub carries the other axis along, step by step', (
      tester,
    ) async {
      final applied = <AppliedTransform>[];
      await pumpMoveSettings(tester, applied: applied, start: wide);

      await tester.drag(
        find.byKey(const ValueKey<String>('move-scale-x-field')),
        const Offset(60, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));

      final after = applied.last;
      expect(after.sx, isNot(wide.sx), reason: '⛔premise: the scrub wrote');
      expect(after.sy / wide.sy, closeTo(after.sx / wide.sx, 1e-9));
      expect(after.sy, isNegative, reason: 'still mirrored');
      expect(
        after,
        wide.copyWith(sx: after.sx, sy: after.sy),
        reason: '⛔and nothing but the two scales moved',
      );
    });

    testWidgets('the axis carried along is held to the floor and the '
        'ceiling a typed scale is', (tester) async {
      final applied = <AppliedTransform>[];
      await pumpMoveSettings(tester, applied: applied, start: wide);

      // 200% → 6400% would be ×32; the row stops at 3200%, a ×16 step.
      await typeInto(tester, 'move-scale-x-field', '99999');
      expect(applied.last.sx, 32);
      expect(applied.last.sy, -16);

      // …and from there ×(1/3200): the mirrored axis stops at its floor,
      // on its own side of zero.
      await typeInto(tester, 'move-scale-x-field', '1');
      expect(applied.last.sx, 0.01);
      expect(applied.last.sy, -0.01);
    });

    testWidgets('the other rows are not the chain\'s: a move, a turn and '
        'the cross write their one value', (tester) async {
      final commands = await pumpMoveSettings(tester, applied: []);
      for (final key in const [
        'move-x-field',
        'move-y-field',
        'move-angle-field',
        'move-anchor-x-field',
        'move-anchor-y-field',
      ]) {
        final row = rows[key]!;
        final applied = <AppliedTransform>[];
        bindBox(commands, applied: applied, start: stretched);
        await tester.pump();

        await tester.drag(
          find.byKey(ValueKey<String>(key)),
          const Offset(60, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 500));

        final after = applied.last;
        expect(after, row.write(stretched, row.read(after)), reason: key);
      }
    });
  });

  /// A handle can leave a scale past the most this panel types (3200%).
  testWidgets('⛔unlinked, a number typed in one scale row does not restate '
      'the other — not even to pull it back under the ceiling', (
    tester,
  ) async {
    const past = TransformValues(sx: 40, sy: 1);
    final applied = <AppliedTransform>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      start: past,
      scaleLinked: false,
    );

    await typeInto(tester, 'move-scale-y-field', '200');

    expect(applied.last, past.copyWith(sy: 2));
  });

  /// The shell keeps the tool's options on a notifier, and a notifier says
  /// nothing for a value equal to the one it holds.
  test('the link is part of what the options ARE: whoever holds them hears '
      'the switch', () {
    final held = ValueNotifier(TransformToolOptions.defaults);
    addTearDown(held.dispose);
    var heard = 0;
    held.addListener(() => heard += 1);

    held.value = held.value.copyWith(scaleLinked: false);

    expect(heard, 1);
    expect(held.value.scaleLinked, isFalse);
    expect(
      held.value.copyWith(meshRows: 5).scaleLinked,
      isFalse,
      reason: 'and another knob turned leaves the link as it was',
    );
  });

  testWidgets('the link switch reaches the tool\'s options, and reads back '
      'from them', (tester) async {
    final chosen = <TransformToolOptions>[];
    await pumpMoveSettings(
      tester,
      applied: [],
      onOptionsChanged: chosen.add,
    );
    final link = find.byKey(const ValueKey<String>('move-scale-link-switch'));
    expect(
      tester.booleanDotIn(link).value,
      isTrue,
      reason: 'the chain is on as the tool begins — AE\'s',
    );

    await tester.tap(link);
    await tester.pump();
    expect(chosen.single.scaleLinked, isFalse);
    expect(
      chosen.single,
      const TransformToolOptions(scaleLinked: false),
      reason: '⛔and it changed nothing else of the tool\'s',
    );

    // The host holding it OFF: the panel torn down between, so what the
    // switch reads can only have come from the host (as the AA switch's
    // pin below explains).
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      applied: [],
      scaleLinked: false,
      onOptionsChanged: chosen.add,
    );
    expect(tester.booleanDotIn(link).value, isFalse);
    await tester.tap(link);
    await tester.pump();
    expect(chosen.last.scaleLinked, isTrue);
  });

  testWidgets('the AA switch reaches the resampler, and reads back from it', (
    tester,
  ) async {
    // P3e, relabelled. It used to read "Preserve original colours" over a
    // paragraph about in-between shades; 유저 08-13 asked for the two
    // letters and the polarity that goes with them, so ON is now the
    // smoothing default and OFF is the two-value copy. The wiring is what
    // it always was: the state has to come from the HOST, not from a local
    // bool that would drift away from what a commit runs through.
    final applied = <AppliedTransform>[];
    final chosen = <ResampleMode>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: chosen.add,
    );

    final switchKey = find.byKey(
      const ValueKey<String>('move-antialias-switch'),
    );
    expect(switchKey, findsOneWidget);
    expect(
      tester.booleanDotIn(switchKey).value,
      isTrue,
      reason: 'Blend is the default, so AA starts ON',
    );

    await tester.tap(switchKey);
    await tester.pump();
    expect(chosen, <ResampleMode>[ResampleMode.pick]);

    // Now with the host holding Pick: AA must read off, and turning it on
    // must ask for Blend.
    //
    // The empty pump matters — it tears the panel's State down, so the
    // value the switch reads back can only have come from the host.
    // Without it, pumping the identical tree reuses `_MoveSettingsState`,
    // and a widget that kept the value in a local bool set by the tap
    // above would read the same and this half of the test would pass for
    // the implementation it exists to rule out.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      applied: applied,
      resampleMode: ResampleMode.pick,
      onResampleModeChanged: chosen.add,
    );
    expect(tester.booleanDotIn(switchKey).value, isFalse);
    await tester.tap(switchKey);
    await tester.pump();
    expect(chosen.last, ResampleMode.blend);
  });

  testWidgets('with nothing to transform every control goes flat — the '
      'refusal is the panel, not a notice', (tester) async {
    final applied = <AppliedTransform>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: (_) {},
      canEdit: false,
    );
    for (final key in const [
      'move-antialias-switch',
      'move-scale-link-switch',
    ]) {
      expect(
        tester.booleanDotIn(find.byKey(ValueKey<String>(key))).enabled,
        isFalse,
        reason: '$key must be flat with nothing to transform',
      );
    }
    for (final key in const [
      'move-flip-horizontal-button',
      'move-flip-vertical-button',
      'move-reset-button',
    ]) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(ValueKey<String>(key)))
            .onPressed,
        isNull,
        reason: '$key must not be pressable with nothing to transform',
      );
    }
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('move-apply-button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('적용 is grey when 적용 has nothing to do, though the tool can '
      'edit — it asks the verb, as the rail\'s ↵ does', (tester) async {
    // confirm-button (유저 2026-09-24): 「할 게 없으면 회색」. ↩️It asked
    // whether the TOOL could edit, so it lit over a box with nothing to
    // confirm and nothing to replay, and pressing it did nothing.
    FilledButton apply() => tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('move-apply-button')),
    );
    await pumpMoveSettings(tester, applied: []);
    expect(apply().onPressed, isNull);

    await pumpMoveSettings(tester, applied: [], canApply: true);
    expect(apply().onPressed, isNotNull);
  });

  testWidgets('the four buttons come in the order the user asked for, and '
      'the mesh grid shows only in 메쉬', (tester) async {
    final applied = <AppliedTransform>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: (_) {},
    );
    // 좌우반전 · 상하반전 · 리셋 · 적용.
    final buttons = <Offset>[
      for (final key in const [
        'move-flip-horizontal-button',
        'move-flip-vertical-button',
        'move-reset-button',
        'move-apply-button',
      ])
        tester.getTopLeft(find.byKey(ValueKey<String>(key))),
    ];
    for (var i = 1; i < buttons.length; i += 1) {
      expect(
        buttons[i].dy > buttons[i - 1].dy ||
            (buttons[i].dy == buttons[i - 1].dy &&
                buttons[i].dx > buttons[i - 1].dx),
        isTrue,
        reason: 'button $i sits after button ${i - 1}',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('move-mesh-columns-field')),
      findsNothing,
      reason: 'a grid size means nothing outside 메쉬',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: (_) {},
      mode: TransformMode.mesh,
    );
    expect(
      find.byKey(const ValueKey<String>('move-mesh-columns-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('move-mesh-rows-field')),
      findsOneWidget,
    );
  });

  /// 🚨★★★**F-164 ③④ — 유저 2026-09-18**: 「변형중에 툴도구의 X,Y값같은거
  /// **실시간으로 바뀌게**해주고. **무겁지 않을 구조로 패널리빌드하지말고
  /// 글자만 바꾸게**」.
  testWidgets('the numbers follow the live box, and ONLY the digits rebuild', (
    tester,
  ) async {
    final commands = await pumpMoveSettings(tester, applied: []);

    expect(find.text('0'), findsWidgets, reason: '⛔fixture premise: identity');

    // What the LAYER publishes while a handle is being dragged.
    commands.publishTransformValues(const TransformValues(tx: 12, ty: -4));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('move-x-field')),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget, reason: 'X followed the box');
    expect(find.text('-4'), findsOneWidget, reason: 'Y followed the box');
  });

  testWidgets('⛔and the digits are the only thing listening', (tester) async {
    // 🎯THE HALF THAT IS A PERFORMANCE RULE. A transform drag is a
    // pointer-rate event; the panel learning through its own `setState`
    // would rebuild every row of every section on every sample, which is
    // exactly what 유저 ruled out in the same sentence they asked for the
    // numbers.
    //
    // ⛔A STRUCTURAL assertion, and deliberately so. A test that counted
    // "rebuilds" here would have to invent a counter the panel does not
    // have, and this file has already been taught what an invented
    // instrument is worth. What is checkable is where the listening
    // happens: the number sits inside a builder that listens to the live
    // values, and the panel above it does not.
    await pumpMoveSettings(tester, applied: []);
    final label = find.byKey(const ValueKey<String>('move-x-field'));
    expect(label, findsOneWidget, reason: '⛔fixture premise');

    expect(
      find.ancestor(
        of: label,
        matching: find.byType(ValueListenableBuilder<TransformValues?>),
      ),
      findsOneWidget,
      reason: 'the digits read the live values themselves',
    );
    // ⚠️And that builder is BELOW the sections, not wrapped around them —
    // one around the panel would rebuild everything and still pass the
    // assertion above.
    expect(
      find.descendant(
        of: find.byType(ValueListenableBuilder<TransformValues?>),
        matching: find.byType(ToolSettingsPanel),
      ),
      findsNothing,
      reason: '⛔a builder around the whole panel is the thing being avoided',
    );
  });
}
