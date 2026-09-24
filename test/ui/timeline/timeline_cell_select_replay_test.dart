import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// Selection must NEVER rewind: with onDoubleTap registered, an InkWell
/// onTap resolves ~300ms late, so tapping cell B right after cell A used to
/// replay A's deferred tap AFTER B's selection (the selection visibly jumped
/// B → A → B). The pick rides the raw pointer stream; the arena never
/// re-selects.
///
/// ㉟ (유저 2026-08-12, 「둘 다 선택하려면 탭. 즉 손 떼야 선택됨」): that raw
/// pick lands on the RELEASE for every device now, the way the rail row's tap
/// always has. The two tests at the bottom are the pair that pins it — one
/// fails if a device starts acting on the press again, the other if a drag
/// stops being exempt.
///
/// ↪️These ran on the widget cell (`TimelineFrameCell`) until 2026-09-24,
/// when its last user — the instance-edit dialog's miniature — started
/// drawing through the row painter and the widget went. The law was never
/// the widget's: the painted rows every timeline draws take it from the
/// same [InstantTapRegion], so it is pinned where the user presses now.
void main() {
  const extent = 24.0;
  const cross = 28.0;
  const frames = 8;

  final layer = Layer(id: const LayerId('layer'), name: 'L', frames: const []);

  Future<void> pumpRow(
    WidgetTester tester, {
    required ValueChanged<int> onSelectFrame,
    void Function(LayerId layerId, int frameIndex)? onActivateCell,
  }) async {
    final geometry = testFrameGeometry(
      frameCellExtent: extent,
      frameEndIndexExclusive: frames,
    );
    addTearDown(geometry.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: frames * extent,
              height: cross,
              child: Builder(
                builder: (context) => timelineRowCellsPaintArea(
                  context: context,
                  keyPrefix: 'timeline',
                  layer: layer,
                  geometry: geometry,
                  crossAxisExtent: cross,
                  axis: Axis.horizontal,
                  exposureStateForLayer: (_, _) =>
                      TimelineCellExposureState.uncovered,
                  onSelectLayer: (_) {},
                  onSelectFrame: onSelectFrame,
                  onActivateCell: onActivateCell,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset cellCentre(WidgetTester tester, int frame) =>
      tester.getTopLeft(
        find.byKey(const ValueKey<String>('timeline-row-cells-layer')),
      ) +
      Offset(frame * extent + extent / 2, cross / 2);

  testWidgets('quick successive taps never re-select the previous cell', (
    tester,
  ) async {
    final selections = <int>[];
    // Double-tap registered = the arena defers plain taps (the bug's
    // precondition on every layer kind since the entrance unification).
    await pumpRow(
      tester,
      onSelectFrame: selections.add,
      onActivateCell: (_, _) {},
    );

    await tester.tapAt(cellCentre(tester, 0));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(cellCentre(tester, 1));
    // Let every deferred recognizer deadline fire.
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections.first, 0);
    expect(selections.last, 1);
    final lastZero = selections.lastIndexOf(0);
    final firstOne = selections.indexOf(1);
    expect(
      lastZero < firstOne,
      isTrue,
      reason:
          'no selection of cell 0 may replay after cell 1 was selected '
          '(got $selections)',
    );
  });

  testWidgets('double-tap still activates the cell editor', (tester) async {
    final activated = <int>[];
    await pumpRow(
      tester,
      onSelectFrame: (_) {},
      onActivateCell: (_, frame) => activated.add(frame),
    );

    await tester.tapAt(cellCentre(tester, 3));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(cellCentre(tester, 3));
    await tester.pumpAndSettle();

    expect(activated, [3]);
  });

  /// 🚨T10 (유저 확정 2026-08-14): a press PICKS again.
  ///
  /// ⛔㉟ had made every device wait for the release (「손 떼야 선택됨」).
  /// That is reversed, and the reversal is safe because the press and the
  /// release now carry different jobs: the press picks and clears only when
  /// it landed OUTSIDE the selection, and the release clears when nothing
  /// travelled. These cases asserted the ㉟ half and are rewritten.
  ///
  /// ⚠️A FINGER is carved out ONLY WHILE IT IS NAVIGATING, and that is not
  /// T10's doing — the carve-out predates ㉟ and came from its own user
  /// report (UI-R23 #2: 「the first scroll touch kept moving the playhead」).
  /// 🚨With 터치 묘화 ON the finger is not navigating, so it presses like a
  /// mouse (유저 2026-08-29: 「터치 묘화 on이면 터치가 마우스랑 완전 똑같이
  /// 작용하길 원하는데 … 손떼야 바껴」). Both halves are below this loop.
  for (final kind in const [
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  ]) {
    testWidgets('T10 a ${kind.name} press picks on the DOWN', (tester) async {
      final selections = <int>[];
      await pumpRow(
        tester,
        onSelectFrame: selections.add,
        onActivateCell: (_, _) {},
      );

      final gesture = await tester.startGesture(
        cellCentre(tester, 2),
        kind: kind,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        selections,
        [2],
        reason:
            'the press IS the pick (T10) — and it does not wait out the '
            'double-tap window to be one',
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        selections,
        [2],
        reason: 'the release adds no second pick; its job is the clear',
      );
    });
  }

  /// 🚨The finger, BOTH ways — one body, driven twice.
  ///
  /// Written as a loop on purpose: the carve-out and its lift are the same
  /// press through the same row, and only the setting differs. Two
  /// hand-written copies would let one drift while the other kept passing.
  for (final (draws, expectOnPress) in const [(true, true), (false, false)]) {
    testWidgets(
      'a finger presses like a mouse when 터치 묘화 is ${draws ? "on" : "off"}',
      (tester) async {
        AppInput.settings.value = AppInput.settings.value.copyWith(
          touchDragOneFinger: draws
              ? CanvasTouchDragAction.draw
              : CanvasTouchDragAction.flip,
        );
        addTearDown(() {
          AppInput.settings.value = AppInputSettings.testCorpusBaseline;
        });

        final selections = <int>[];
        await pumpRow(
          tester,
          onSelectFrame: selections.add,
          onActivateCell: (_, _) {},
        );

        final gesture = await tester.startGesture(
          cellCentre(tester, 2),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          selections,
          expectOnPress ? [2] : isEmpty,
          reason: draws
              // 유저 2026-08-29: 「터치 묘화 on이면 터치가 마우스랑 완전
              // 똑같이 작용하길 원하는데 … 손떼야 바껴」.
              ? '터치 묘화 on — the finger IS the pointer, press and all'
              // ⛔THE CONTROL, and it is UI-R23 #2 itself: in flip mode the
              // finger is navigating, and a press that seeks is the bug.
              : 'in flip mode a finger still withholds on the press',
        );

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          selections,
          [2],
          reason: 'either way the cell is picked once the finger is done',
        );
      },
    );
  }

  testWidgets('T10 a press that TRAVELS has already picked, and that is the '
      'cost the user named', (tester) async {
    final selections = <int>[];
    await pumpRow(
      tester,
      onSelectFrame: selections.add,
      onActivateCell: (_, _) {},
    );

    final gesture = await tester.startGesture(
      cellCentre(tester, 5),
      kind: PointerDeviceKind.stylus,
    );
    // Past the travel slop, in steps — one big jump is not how a drag
    // arrives, and the region reads the moves.
    for (var i = 0; i < 4; i += 1) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      selections,
      [5],
      reason:
          '⛔This used to assert `isEmpty` — 「a drag must not leave a pick '
          'behind it」. T10 reverses it, and the user named the cost when '
          'they chose it: 「범위 드래그를 시작만 해도 액티브가 옮겨간다」. What '
          'protects the DRAG is not the pick being withheld, it is the '
          'clearing being withheld — a press inside a selection stands '
          'without wiping it, so the range the drag was about to carry '
          'survives.',
    );
  });
}
