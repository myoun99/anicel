import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/native/windows_key_state.dart' show vkShift;
import 'package:anicel/src/services/input/modifier_keys.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'brush_canvas_test_helpers.dart';
import '../helpers/blank_cel.dart';

/// Guides are a contract about what a real gesture puts on the canvas, so
/// these drive the actual pointer pipeline rather than calling the geometry
/// directly — the unit tests next door already cover the maths, and a
/// pipeline that never consulted them would still pass those.
void main() {
  const layerId = LayerId('layer-a');
  const frameId = FrameId('frame-a');
  const canvasSize = CanvasSize(width: 200, height: 200);

  late List<BrushStrokeCommitData> commits;

  setUp(() => commits = <BrushStrokeCommitData>[]);

  Widget app(CutGuides guides) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: canvasSize.width.toDouble(),
          height: canvasSize.height.toDouble(),
          child: InteractiveBrushEditCanvasView(
            celNow: blankCel(canvasSize, tileSize: 32),
            layerId: layerId,
            frameId: frameId,
            inputSettings: () =>
                BrushEditCanvasInputSettings(color: 0xFFFF0000),
            guides: guides,
            onSourceStrokeCommitted: commits.add,
          ),
        ),
      ),
    ),
  );

  List<BrushDab> dabs() {
    expect(commits, hasLength(1), reason: 'one stroke, one commit');
    return commits.single.sourceDabs;
  }

  CutGuides symmetryGuides({int lineCount = 2, bool lineSymmetry = true}) {
    const id = GuideId('sym');
    return CutGuides(
      guides: [
        DrawingGuide(
          id: id,
          name: 'Symmetry',
          shape: SymmetryShape(
            axis: GuideAxis(
              origin: CanvasPoint(x: 100, y: 100),
              angleDegrees: 90,
            ),
            lineCount: lineCount,
            lineSymmetry: lineSymmetry,
          ),
        ),
      ],
      activeSymmetryId: id,
    );
  }

  CutGuides perspectiveGuides({bool snapEnabled = true}) => CutGuides(
    guides: [
      DrawingGuide(
        id: const GuideId('persp'),
        name: 'Perspective',
        shape: PerspectiveShape(
          // A single horizontal family: strokes must come out flat.
          vanishingPoints: [VanishingPointTowards(dx: 1, dy: 0)],
          eyeLevel: GuideAxis(
            origin: CanvasPoint(x: 0, y: 100),
            angleDegrees: 0,
          ),
          snapEnabled: snapEnabled,
        ),
      ),
    ],
  );

  testWidgets('no guides leaves the stroke exactly where it was drawn', (
    tester,
  ) async {
    await tester.pumpWidget(app(CutGuides.empty));

    await dragCanvas(tester, const [
      Offset(120, 40),
      Offset(140, 60),
      Offset(160, 80),
    ]);

    final drawn = dabs();
    expect(drawn, isNotEmpty);
    expect(drawn.every((dab) => dab.center.x >= 100), isTrue);
    // Sequence numbers stay one per dab when nothing replicates.
    expect(
      drawn.map((dab) => dab.sequence).toList(),
      List<int>.generate(drawn.length, (index) => index),
    );
  });

  testWidgets('an acting symmetry puts the same stroke on both sides', (
    tester,
  ) async {
    await tester.pumpWidget(app(symmetryGuides()));

    await dragCanvas(tester, const [
      Offset(120, 40),
      Offset(140, 60),
      Offset(160, 80),
    ]);

    final drawn = dabs();
    final right = drawn.where((dab) => dab.center.x > 100).toList();
    final left = drawn.where((dab) => dab.center.x < 100).toList();

    expect(right, isNotEmpty);
    expect(left, hasLength(right.length));
    // Every dab on the right has a partner mirrored about x = 100.
    for (final dab in right) {
      expect(
        left.any(
          (other) =>
              (other.center.x - (200 - dab.center.x)).abs() < 1e-6 &&
              (other.center.y - dab.center.y).abs() < 1e-6,
        ),
        isTrue,
        reason: 'no mirror partner for ${dab.center}',
      );
    }
  });

  testWidgets('symmetry doubles the dab count and keeps sequences unique', (
    tester,
  ) async {
    await tester.pumpWidget(app(CutGuides.empty));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);
    final plain = dabs().length;

    commits.clear();
    await tester.pumpWidget(app(symmetryGuides()));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);
    final mirrored = dabs();

    expect(mirrored.length, plain * 2);
    expect(
      mirrored.map((dab) => dab.sequence).toSet().length,
      mirrored.length,
      reason: 'a repeated sequence number would collide in the batch',
    );
  });

  testWidgets('a four-line symmetry emits four copies', (tester) async {
    await tester.pumpWidget(app(CutGuides.empty));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);
    final plain = dabs().length;

    commits.clear();
    await tester.pumpWidget(app(symmetryGuides(lineCount: 4)));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);

    expect(dabs().length, plain * 4);
  });

  testWidgets('a switched-off symmetry replicates nothing', (tester) async {
    // Keeping several symmetry guides is fine; only the ACTING one draws.
    final kept = CutGuides(guides: symmetryGuides().guides);

    await tester.pumpWidget(app(kept));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);

    expect(dabs().every((dab) => dab.center.x >= 100), isTrue);
  });

  testWidgets('perspective snapping flattens a wobbly stroke onto its ray', (
    tester,
  ) async {
    await tester.pumpWidget(app(perspectiveGuides()));

    // Drawn with a pronounced vertical wobble; the horizontal family must
    // straighten it.
    await dragCanvas(tester, const [
      Offset(20, 100),
      Offset(60, 118),
      Offset(100, 84),
      Offset(150, 112),
    ]);

    final drawn = dabs();
    expect(drawn, isNotEmpty);
    for (final dab in drawn) {
      expect(
        dab.center.y,
        closeTo(100, 1e-6),
        reason: 'the wobble should not survive the snap',
      );
    }
  });

  testWidgets('a switched-off perspective leaves the wobble alone', (
    tester,
  ) async {
    await tester.pumpWidget(app(perspectiveGuides(snapEnabled: false)));

    await dragCanvas(tester, const [
      Offset(20, 100),
      Offset(60, 118),
      Offset(100, 84),
    ]);

    expect(dabs().any((dab) => (dab.center.y - 100).abs() > 1), isTrue);
  });

  testWidgets('the snapped stroke starts where the pen went down', (
    tester,
  ) async {
    // The held run is released onto the ray, and the ray passes through the
    // pen-down point — so nothing is lost off the front of the stroke.
    await tester.pumpWidget(app(perspectiveGuides()));

    await dragCanvas(tester, const [
      Offset(20, 100),
      Offset(24, 103),
      Offset(120, 96),
    ]);

    final drawn = dabs();
    final leftmost = drawn
        .map((dab) => dab.center.x)
        .reduce((a, b) => a < b ? a : b);
    expect(leftmost, closeTo(20, 1.0));
  });

  testWidgets('a short flick under the lock distance still draws', (
    tester,
  ) async {
    await tester.pumpWidget(app(perspectiveGuides()));

    await dragCanvas(tester, const [Offset(60, 100), Offset(63, 101)]);

    expect(commits, hasLength(1));
    // To where the pen went, on the ray — not the press's dab alone: what
    // the lock held when the pen lifted is laid too.
    final reach = dabs()
        .map((dab) => dab.center.x)
        .reduce((a, b) => a > b ? a : b);
    expect(reach, closeTo(63, 0.5));
    for (final dab in dabs()) {
      expect(dab.center.y, closeTo(100, 1e-6));
    }
  });

  testWidgets('snap and symmetry compose: constrain first, then copy', (
    tester,
  ) async {
    final both = CutGuides(
      guides: [...symmetryGuides().guides, ...perspectiveGuides().guides],
      activeSymmetryId: const GuideId('sym'),
    );

    await tester.pumpWidget(app(both));
    await dragCanvas(tester, const [
      Offset(120, 100),
      Offset(140, 118),
      Offset(180, 84),
    ]);

    final drawn = dabs();
    expect(drawn, isNotEmpty);
    // Snapped flat by the perspective, then mirrored about x = 100: both
    // halves are on the eye level, and both sides are present.
    for (final dab in drawn) {
      expect(dab.center.y, closeTo(100, 1e-6));
    }
    expect(drawn.any((dab) => dab.center.x > 100), isTrue);
    expect(drawn.any((dab) => dab.center.x < 100), isTrue);
  });

  // 🗣️I-61 (유저 2026-10-08): Shift 는 45° 잠금(Q1) — 「누르고 있는 동안만
  // — 누른 그 자리에서부터 잠긴다」(Q2). Keyboard only (10-02).
  group('Shift held', () {
    testWidgets('🚨puts a wobbly stroke on the nearest of the eight ways '
        'from where the pen went down', (tester) async {
      await tester.pumpWidget(app(CutGuides.empty));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      await dragCanvas(tester, const [
        Offset(20, 20),
        Offset(60, 66),
        Offset(100, 94),
        Offset(150, 154),
      ]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      final drawn = dabs();
      expect(drawn.length, greaterThan(3));
      for (final dab in drawn) {
        expect(dab.center.y - 20, closeTo(dab.center.x - 20, 1e-6));
      }
    });

    testWidgets('🚨pressed in the middle of a stroke it locks it from '
        'there — and let go, the stroke is free again', (tester) async {
      await tester.pumpWidget(app(CutGuides.empty));
      final pen = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(20, 100)),
      );
      await tester.pump();
      Future<void> to(double x, double y) async {
        await pen.moveTo(canvasGlobalOffset(tester, Offset(x, y)));
        await tester.pump();
      }

      await to(40, 120);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await to(60, 124);
      await to(80, 116);
      await to(100, 124);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await to(130, 160);
      await pen.up();
      await tester.pump();
      await tester.pump();

      final drawn = dabs();
      final held = [
        for (final dab in drawn)
          if (dab.center.x > 41 && dab.center.x < 99) dab,
      ];
      expect(held, isNotEmpty);
      for (final dab in held) {
        expect(dab.center.y, closeTo(120, 1e-6), reason: 'held across');
      }
      expect(
        drawn.any((dab) => dab.center.x < 40 && dab.center.y < 119),
        isTrue,
        reason: 'free before it',
      );
      expect(
        drawn.any((dab) => dab.center.x > 100 && dab.center.y > 121),
        isTrue,
        reason: 'free after it',
      );
    });

    // 🗣️유저 2026-10-16: 「마우스로는 작동하는거 확인했는데 왜 펜으로는
    // 작동안하는지? 마우스던 펜이던 터치묘화던 그림 그리는 동작이라면
    // 해야하는건데」 — on Windows the engine lets go of Shift in its record
    // at a pen's or a finger's first move, with the key still down
    // (`ModifierKeys`). Windows still holds it: the stroke must too.
    for (final kind in const [
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
    ]) {
      testWidgets('🚨a ${kind.name}\'s stroke stays locked when the engine '
          'lets go of Shift under it and Windows holds it', (tester) async {
        ModifierKeys.debugWindowsKeyDown = (key) => key == vkShift;
        addTearDown(() => ModifierKeys.debugWindowsKeyDown = null);
        await tester.pumpWidget(app(CutGuides.empty));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final pointer = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(20, 20)),
          kind: kind,
        );
        await tester.pump();
        // What the engine sends ahead of the first move.
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        for (final at in const [
          Offset(60, 66),
          Offset(100, 94),
          Offset(150, 154),
        ]) {
          await pointer.moveTo(canvasGlobalOffset(tester, at));
          await tester.pump();
        }
        await pointer.up();
        await tester.pump();
        await tester.pump();

        final drawn = dabs();
        expect(drawn.length, greaterThan(3));
        for (final dab in drawn) {
          expect(dab.center.y - 20, closeTo(dab.center.x - 20, 1e-6));
        }
      });
    }

    testWidgets('🚨pressed in the middle of a pen\'s stroke, it locks it '
        'from there though the engine lets go of it at the next move', (
      tester,
    ) async {
      var windowsHoldsShift = false;
      ModifierKeys.debugWindowsKeyDown = (key) =>
          key == vkShift && windowsHoldsShift;
      addTearDown(() => ModifierKeys.debugWindowsKeyDown = null);
      await tester.pumpWidget(app(CutGuides.empty));
      final pen = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(20, 100)),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      Future<void> to(double x, double y) async {
        await pen.moveTo(canvasGlobalOffset(tester, Offset(x, y)));
        await tester.pump();
      }

      await to(40, 120);
      windowsHoldsShift = true;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await to(60, 124);
      await to(80, 116);
      await to(100, 124);
      windowsHoldsShift = false;
      await to(130, 160);
      await pen.up();
      await tester.pump();
      await tester.pump();

      final drawn = dabs();
      final held = [
        for (final dab in drawn)
          if (dab.center.x > 41 && dab.center.x < 99) dab,
      ];
      expect(held, isNotEmpty);
      for (final dab in held) {
        expect(dab.center.y, closeTo(120, 1e-6), reason: 'held across');
      }
      expect(
        drawn.any((dab) => dab.center.x > 100 && dab.center.y > 121),
        isTrue,
        reason: 'free once Windows lets go, with no key event to say so',
      );
    });
  });

  // 🗣️I-61-Q3 (유저 2026-10-14): 「손가락도 — 다른 손가락이 닿아 있는 동안
  // 잠긴다」 — behind a switch of its own, off as it comes.
  group('a finger resting on the glass', () {
    void switchedOn({bool fingerDraws = true}) {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        strokeFingerModifier: true,
        touchDragOneFinger: fingerDraws
            ? CanvasTouchDragAction.draw
            : CanvasTouchDragAction.navigate,
      );
      addTearDown(
        () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
      );
    }

    Future<TestGesture> downAt(
      WidgetTester tester,
      Offset at, {
      required PointerDeviceKind kind,
      required int pointer,
    }) async {
      final contact = await tester.startGesture(
        canvasGlobalOffset(tester, at),
        kind: kind,
        pointer: pointer,
      );
      await tester.pump();
      return contact;
    }

    /// What rests: in a corner, away from every stroke — a finger, unless
    /// said otherwise.
    Future<TestGesture> rest(
      WidgetTester tester, {
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) => downAt(tester, const Offset(190, 10), kind: kind, pointer: 9);

    Future<void> to(WidgetTester tester, TestGesture pen, Offset at) async {
      await pen.moveTo(canvasGlobalOffset(tester, at));
      await tester.pump();
    }

    Future<void> lift(WidgetTester tester, TestGesture contact) async {
      await contact.up();
      await tester.pump();
      await tester.pump();
    }

    /// A pen's stroke with a wobble across y = 120, the finger resting
    /// while it crosses — the shape of the Shift test above. [meanwhile]
    /// runs once the finger is down, before the wobble.
    Future<void> wobbleWithAFingerOnTheWay(
      WidgetTester tester, {
      PointerDeviceKind drawnBy = PointerDeviceKind.stylus,
      PointerDeviceKind resting = PointerDeviceKind.touch,
      VoidCallback? meanwhile,
    }) async {
      final pen = await downAt(
        tester,
        const Offset(20, 100),
        kind: drawnBy,
        pointer: 3,
      );
      await to(tester, pen, const Offset(40, 120));
      final finger = await rest(tester, kind: resting);
      meanwhile?.call();
      await to(tester, pen, const Offset(60, 124));
      await to(tester, pen, const Offset(80, 116));
      await to(tester, pen, const Offset(100, 124));
      await lift(tester, finger);
      await to(tester, pen, const Offset(130, 160));
      await lift(tester, pen);
    }

    List<BrushDab> crossing() => [
      for (final dab in dabs())
        if (dab.center.x > 41 && dab.center.x < 99) dab,
    ];

    void wobbleKept() => expect(
      crossing().any((dab) => (dab.center.y - 120).abs() > 1),
      isTrue,
      reason: 'the wobble is kept',
    );

    testWidgets('🚨with the switch on, one resting before the pen goes down '
        'holds the whole stroke to the eight ways', (tester) async {
      switchedOn(fingerDraws: false);
      await tester.pumpWidget(app(CutGuides.empty));
      final finger = await rest(tester);
      final pen = await downAt(
        tester,
        const Offset(20, 20),
        kind: PointerDeviceKind.stylus,
        pointer: 3,
      );
      for (final at in const [
        Offset(60, 66),
        Offset(100, 94),
        Offset(150, 154),
      ]) {
        await to(tester, pen, at);
      }
      await lift(tester, pen);
      await lift(tester, finger);

      final drawn = dabs();
      expect(drawn.length, greaterThan(3));
      for (final dab in drawn) {
        expect(dab.center.y - 20, closeTo(dab.center.x - 20, 1e-6));
      }
    });

    testWidgets('🚨put down in the middle of a stroke it holds it from there '
        '— and lifted, the stroke is free again', (tester) async {
      switchedOn();
      await tester.pumpWidget(app(CutGuides.empty));

      await wobbleWithAFingerOnTheWay(tester);

      expect(crossing(), isNotEmpty);
      for (final dab in crossing()) {
        expect(dab.center.y, closeTo(120, 1e-6), reason: 'held across');
      }
      expect(
        dabs().any((dab) => dab.center.x > 100 && dab.center.y > 121),
        isTrue,
        reason: 'free after it',
      );
    });

    testWidgets('🚨with the switch off — as it comes — it is a palm resting: '
        'the stroke is as it was drawn', (tester) async {
      expect(AppInput.settings.value.strokeFingerModifier, isFalse);
      await tester.pumpWidget(app(CutGuides.empty));

      await wobbleWithAFingerOnTheWay(tester);

      wobbleKept();
    });

    testWidgets('a FINGER\'s stroke takes a second finger as its Shift once '
        'it has gone its way', (tester) async {
      switchedOn();
      await tester.pumpWidget(app(CutGuides.empty));

      await wobbleWithAFingerOnTheWay(
        tester,
        drawnBy: PointerDeviceKind.touch,
      );

      expect(crossing(), isNotEmpty);
      for (final dab in crossing()) {
        expect(dab.center.y, closeTo(120, 1e-6), reason: 'held across');
      }
    });

    testWidgets('⛔a finger is a FINGER: a pen resting while a finger draws '
        'is not the stroke\'s Shift', (tester) async {
      switchedOn();
      await tester.pumpWidget(app(CutGuides.empty));

      await wobbleWithAFingerOnTheWay(
        tester,
        drawnBy: PointerDeviceKind.touch,
        resting: PointerDeviceKind.stylus,
      );

      wobbleKept();
    });

    testWidgets('⛔with the switch off nothing counts a finger (「off하면 '
        '확실하게 제거」) — so one already resting when it goes on is not '
        'counted', (tester) async {
      await tester.pumpWidget(app(CutGuides.empty));

      await wobbleWithAFingerOnTheWay(tester, meanwhile: switchedOn);

      wobbleKept();
    });

    testWidgets('turned off under a resting finger, the stroke is free at '
        'once', (tester) async {
      switchedOn();
      await tester.pumpWidget(app(CutGuides.empty));

      await wobbleWithAFingerOnTheWay(
        tester,
        meanwhile: () =>
            AppInput.settings.value = AppInputSettings.testCorpusBaseline,
      );

      wobbleKept();
    });
  });
}
