import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/stroke_in_flight.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';

import '../brush_canvas_test_helpers.dart';

/// I-69 (유저 2026-10-04): 「브러시 상태를 그대로 사용해서 도형그림. 샤프
/// 브러시 그대로 사각형 그린다던가 … 그냥 진짜 브러시랑 똑같이
/// 래스터라이즈되있는 도형」.
///
/// 🚨★★★A SHAPE IS THE STROKE, NOT A STROKE LIKE IT. The drawing view lays
/// a path handed to it through the stroke's own arming, advance and landing
/// (`_BrushEditPathStroke`), so the one thing worth pinning is that it is
/// the same stroke a hand would draw through the same points — and the few
/// things a tool does not bring that a hand does.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(CanvasTouchContacts.reset);

  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);
  final corner = [p(10, 10), p(100, 10), p(100, 50)];

  testWidgets('a path is laid as the stroke a hand would draw through the '
      'same points with nothing to read from a pen', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush());

    expect(host.show!.landStroke(corner), isTrue);
    await tester.pump();
    await _byMouse(tester, const [
      Offset(10, 10),
      Offset(100, 10),
      Offset(100, 50),
    ]);

    expect(host.committed, hasLength(2), reason: 'one stroke each');
    final laid = host.committed.first;
    expect(laid.length, greaterThan(20), reason: 'a line of dabs, not a dot');
    expect(laid.first.center, p(10, 10), reason: 'it begins under its start');
    expect(_look(laid), _look(host.committed.last));
  });

  testWidgets('a brush with a second tip lays its second stroke along the '
      'path, a hand\'s and a tool\'s alike', (tester) async {
    final grain = BrushTipMask(
      id: 'path-second-tip',
      size: 8,
      alpha: Uint8List.fromList([for (var i = 0; i < 64; i += 1) i * 4]),
    );
    final host = _Host();
    await _pump(
      tester,
      host,
      BrushToolState.defaults
          .copyWith(
            size: 6,
            dualMaskScale: 0.5,
            dualDensity: 0.8,
            // Nothing steadies or smooths the hand, so it lays the path
            // the tool lays.
            correction: const BrushCorrection(
              steadies: false,
              postBySpeed: false,
            ),
          )
          .withMask(BrushMaskSlot.dual, grain)
          .toInputSettings(),
    );

    host.show!.landStroke(corner);
    await tester.pump();
    await _byMouse(tester, const [
      Offset(10, 10),
      Offset(100, 10),
      Offset(100, 50),
    ]);

    expect(host.committed, hasLength(2));
    final laid = host.committed.first;
    final second = [for (final dab in laid) if (dab.second) dab];
    expect(second.length, greaterThan(20), reason: 'a stroke, not a dot');
    expect(second.first.center, p(10, 10), reason: 'it follows the pen');
    expect({for (final dab in second) dab.size}, {3});
    expect({for (final dab in second) dab.tipMask}, {grain});
    expect(
      {for (final dab in laid) dab.dual},
      {const BrushDualView(density: 0.8)},
      reason: 'every dab of the stroke shows through the one view',
    );
    expect(
      _placed([for (final dab in host.committed.last) if (dab.second) dab]),
      _placed(second),
      reason: "the hand's second stroke is the tool's, numbered as it came",
    );
  });

  testWidgets('the host hears the stroke begin and end, inside the call', (
    tester,
  ) async {
    final host = _Host();
    await _pump(tester, host, _brush());

    host.show!.landStroke(corner);

    expect(host.active, [StrokeInFlight.paints, StrokeInFlight.none]);
    expect(host.committed, hasLength(1), reason: 'landed before it answers');
  });

  testWidgets('an erasing tool\'s stroke is heard as one that erases — what '
      'leaves an empty block empty (F-482)', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush().copyWith(erase: true));

    host.show!.landStroke(corner);

    expect(host.active, [StrokeInFlight.erases, StrokeInFlight.none]);
  });

  testWidgets('⛔nothing steadies it: a stabilised brush lays the path where '
      'it was told, to its very end', (tester) async {
    final plain = _Host();
    await _pump(tester, plain, _brush());
    plain.show!.landStroke(corner);

    final steadied = _Host();
    await _pump(tester, steadied, _brush(stabilizer: 40));
    steadied.show!.landStroke(corner);

    expect(_look(steadied.committed.single), _look(plain.committed.single));
  });

  testWidgets('⛔nothing smooths it: a brush with 後補正 lays the path where '
      'it was told, corner and all (F-418)', (tester) async {
    final plain = _Host();
    await _pump(tester, plain, _brush());
    plain.show!.landStroke(corner);

    final smoothing = _Host();
    await _pump(tester, smoothing, _brush(postStrength: 100));
    smoothing.show!.landStroke(corner);
    // Fixture: a hand's stroke through the same points is smoothed.
    await _byMouse(tester, const [
      Offset(10, 10),
      Offset(100, 10),
      Offset(100, 50),
    ]);

    expect(smoothing.committed, hasLength(2));
    expect(_look(smoothing.committed.first), _look(plain.committed.single));
    expect(
      _look(smoothing.committed.last),
      isNot(_look(plain.committed.single)),
      reason: "fixture: the hand's stroke was smoothed",
    );
  });

  testWidgets('⛔a cancelled stroke leaves no line behind to smooth: the '
      'path laid after it lands where it was told (F-418)', (tester) async {
    final plain = _Host();
    await _pump(tester, plain, _brush());
    plain.show!.landStroke(corner);

    final smoothing = _Host();
    await _pump(tester, smoothing, _brush(postStrength: 100));
    final hand = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(20, 40)),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await hand.moveTo(canvasGlobalOffset(tester, const Offset(60, 30)));
    await tester.pump();
    await hand.cancel();
    await tester.pump();
    smoothing.show!.landStroke(corner);

    expect(smoothing.committed, hasLength(1), reason: 'the cancel landed none');
    expect(_look(smoothing.committed.single), _look(plain.committed.single));
  });

  testWidgets('⛔nothing snaps it: under a perspective guide that bends a '
      'hand\'s stroke onto its rays, a path is laid where it was told', (
    tester,
  ) async {
    final guides = CutGuides(
      guides: [
        DrawingGuide(
          id: const GuideId('p1'),
          name: 'p1',
          shape: PerspectiveShape(
            vanishingPoints: [VanishingPointAt(p(150, 60))],
            eyeLevel: GuideAxis(origin: p(80, 60), angleDegrees: 0),
            snapEnabled: true,
          ),
        ),
      ],
    );
    final plain = _Host();
    await _pump(tester, plain, _brush());
    plain.show!.landStroke(corner);

    final guided = _Host();
    await _pump(tester, guided, _brush(), guides: guides);
    guided.show!.landStroke(corner);
    // Fixture: the guide does bend a hand's stroke through the same points.
    await _byMouse(tester, const [
      Offset(10, 10),
      Offset(100, 10),
      Offset(100, 50),
    ]);

    expect(guided.committed, hasLength(2));
    expect(_look(guided.committed.first), _look(plain.committed.single));
    expect(
      _look(guided.committed.last),
      isNot(_look(plain.committed.single)),
      reason: 'fixture: the hand\'s stroke was snapped',
    );
  });

  testWidgets('symmetry copies it as it copies a stroke: every dab, the '
      'first included', (tester) async {
    final plain = _Host();
    await _pump(tester, plain, _brush());
    plain.show!.landStroke([p(10, 10), p(60, 10), p(60, 50)]);

    final mirrored = _Host();
    await _pump(
      tester,
      mirrored,
      _brush(),
      guides: CutGuides(
        guides: [
          DrawingGuide(
            id: const GuideId('s1'),
            name: 's1',
            shape: SymmetryShape(
              axis: GuideAxis(origin: p(80, 32), angleDegrees: 90),
            ),
          ),
        ],
        activeSymmetryId: const GuideId('s1'),
      ),
    );
    mirrored.show!.landStroke([p(10, 10), p(60, 10), p(60, 50)]);

    final dabs = mirrored.committed.single;
    expect(dabs.length, plain.committed.single.length * 2);
    expect(
      dabs.where((dab) => dab.center.x > 80).length,
      plain.committed.single.length,
      reason: 'one copy across the axis for each dab on this side',
    );
    expect(
      dabs.any(
        (dab) =>
            (dab.center.x - 150).abs() < 1e-6 &&
            (dab.center.y - 10).abs() < 1e-6,
      ),
      isTrue,
      reason: 'the first dab\'s copy: (10,10) across x = 80',
    );
  });

  testWidgets('one path, one roll of the dice: a shape drawn again scatters '
      'the same way, and another shape rolls numbers of its own', (
    tester,
  ) async {
    final host = _Host();
    await _pump(
      tester,
      host,
      BrushToolState.defaults
          .copyWith(size: 6, scatterRadiusRatio: 1.0, scatterCount: 1)
          .toInputSettings(),
    );
    final high = [p(10, 20), p(140, 20)];
    // The same line, 24 lower.
    final low = [p(10, 44), p(140, 44)];

    host.show!.landStroke(high);
    host.show!.landStroke(high);
    host.show!.landStroke(low);

    // How far each dab was thrown off its line, to a millionth of a pixel.
    List<int> thrown(List<BrushDab> dabs, double line) => [
      for (final dab in dabs) ((dab.center.y - line) * 1e6).round(),
    ];
    final first = thrown(host.committed[0], 20);
    expect(first.any((off) => off != 0), isTrue, reason: 'fixture: it scatters');
    expect(thrown(host.committed[1], 20), first, reason: 'the same shape');
    expect(
      thrown(host.committed[2], 44),
      isNot(first),
      reason: 'another shape, another roll — not one pattern on every line',
    );
  });

  testWidgets('its first dab is turned the way the stroke sets off — it is '
      'laid by the first advance, which knows the way', (tester) async {
    final host = _Host();
    await _pump(
      tester,
      host,
      _brush(rotation: BrushTipRotationMode.direction),
    );

    // Straight down.
    host.show!.landStroke([p(40, 8), p(40, 56)]);

    final down = host.committed.single;
    expect(down.length, greaterThan(4));
    // ↩️It compared the tip stamps a dab landed with, its tip already
    // turned — a round tip has none since it is read off its radial
    // profile (fbe3767c2), and the two nulls compared alike.
    expect(
      down.first.angleDegrees,
      down.last.angleDegrees,
      reason: 'one straight line, one direction from its first dab on',
    );

    // Fixture: the direction is what turns it.
    host.show!.landStroke([p(8, 30), p(150, 30)]);
    final across = host.committed.last;
    expect(across.first.angleDegrees, across.last.angleDegrees);
    expect(down.first.angleDegrees, isNot(across.first.angleDegrees));
  });

  group('where there is nothing to draw on', () {
    testWidgets('it asks for the cel as a press does, and draws once the cel '
        'is there', (tester) async {
      final host = _Host();
      await _pump(tester, host, _brush(), editable: false, celAnswer: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'fixture');

      expect(
        host.show!.landStroke(corner, pressure: 0.3),
        isTrue,
        reason: 'it will be drawn',
      );
      expect(host.askedForACel, 1);
      expect(host.committed, isEmpty, reason: 'not before the cel');
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'the frame that brings the cel is asked for, not waited on — '
            'a path left for whichever frame comes next could land on '
            'another cel',
      );

      // The frame that brings the cel.
      await _pump(tester, host, _brush(), editable: true, celAnswer: true);
      await tester.pump();

      expect(host.committed, hasLength(1));
      expect(host.committed.single.first.center, p(10, 10));
      expect(
        {for (final dab in host.committed.single) dab.pressure},
        {0.3},
        reason: 'at the pressure it was handed',
      );
      expect(host.askedForACel, 1, reason: 'asked once');
    });

    testWidgets('🗣️I-113: on a held cel that gives way it asks for a cel of '
        'its own, and draws once that is there — never on the held one', (
      tester,
    ) async {
      final host = _Host();
      // It gives way until the stroke has made its own cel: that one stands
      // on its block's head, where a mark goes on the cel.
      bool givesWay() => host.askedForACel == 0;
      await _pump(
        tester,
        host,
        _brush(),
        celAnswer: true,
        markMakesItsOwnCel: givesWay,
      );

      expect(host.show!.landStroke(corner), isTrue, reason: 'it will be drawn');
      expect(host.askedForACel, 1);
      expect(host.committed, isEmpty, reason: 'not on the held cel');

      // The frame that brings the cel it made.
      await _pump(
        tester,
        host,
        _brush(),
        celAnswer: true,
        markMakesItsOwnCel: givesWay,
        frame: 'frame-b',
      );
      await tester.pump();

      expect(host.committed, hasLength(1));
      expect(host.askedForACel, 1, reason: 'asked once');
    });

    testWidgets('⛔refused a cel, it draws nothing — then or later', (
      tester,
    ) async {
      final host = _Host();
      await _pump(tester, host, _brush(), editable: false, celAnswer: false);

      expect(host.show!.landStroke(corner), isFalse);
      expect(host.askedForACel, 1);

      await _pump(tester, host, _brush(), editable: true, celAnswer: false);
      await tester.pump();
      expect(host.committed, isEmpty);
      expect(host.active, isEmpty, reason: 'no stroke ever began');
    });

    testWidgets('⛔a cel that never came is not drawn on when another does '
        'frames later', (tester) async {
      final host = _Host();
      await _pump(tester, host, _brush(), editable: false, celAnswer: true);
      expect(host.show!.landStroke(corner), isTrue);

      // The next frame, and still nothing to draw on.
      await tester.pump();
      await tester.pump();
      await _pump(tester, host, _brush(), editable: true, celAnswer: true);
      await tester.pump();

      expect(host.committed, isEmpty);
    });
  });

  testWidgets('⛔a row that takes no strokes shows no line', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush(), rowAcceptsStrokes: false);

    expect(host.show!.landStroke(corner), isFalse);
    expect(host.committed, isEmpty);
    expect(host.active, isEmpty);
  });

  testWidgets('a path of one point is no stroke', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush());

    expect(host.show!.landStroke([p(10, 10)]), isFalse);
    expect(host.committed, isEmpty);
  });

  testWidgets('the show goes when the view does', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush());
    expect(host.show, isNotNull);

    await tester.pumpWidget(const SizedBox());

    expect(host.show, isNull);
  });

  /// 🗣️I-69-Q4ⓒ (유저 2026-10-08): 「윤곽선은 손을 따라오고, 실제 결과는 따라
  /// 그린다」 — while the shape is dragged its stroke is laid off screen a
  /// step at a time, shown when it is whole, and landed as it was shown.
  group('while it is dragged', () {
    tearDown(() {
      shapeShowFrameShare = const Duration(microseconds: 4000);
      debugStrokeDabsLaid = null;
    });

    Future<ActiveStrokeOverlayModel> pumpShown(
      WidgetTester tester,
      _Host host,
    ) async {
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      await _pump(tester, host, _brush(), overlay: overlay);
      return overlay;
    }

    Future<int> untilShown(
      WidgetTester tester,
      ActiveStrokeOverlayModel overlay,
    ) async {
      var frames = 0;
      while (!overlay.hasStrokeContent) {
        await tester.pump();
        frames += 1;
        expect(frames, lessThan(400), reason: 'it comes up');
      }
      return frames;
    }

    Future<_Host> laidInOneGo(
      WidgetTester tester,
      List<CanvasPoint> path,
    ) async {
      final host = _Host();
      await _pump(tester, host, _brush());
      host.show!.landStroke(path);
      return host;
    }

    testWidgets('it lands as the stroke laid in one go — the same dabs, the '
        'same tiles — and nothing of it is laid twice', (tester) async {
      final once = await laidInOneGo(tester, corner);
      final host = _Host();
      final overlay = await pumpShown(tester, host);
      final laid = debugStrokeDabsLaid = <BrushDab>[];

      host.show!.showStroke(corner);
      await untilShown(tester, overlay);
      expect(host.committed, isEmpty, reason: 'nothing lands while dragged');
      expect(host.show!.landStroke(corner), isTrue);

      expect(_look(host.committed.single), _look(once.committed.single));
      expect(_tiles(host.data.single), _tiles(once.data.single));
      expect(
        laid,
        hasLength(host.committed.single.length),
        reason: 'what was shown landed: the landing laid nothing again',
      );
      expect(overlay.hasStrokeContent, isFalse, reason: 'it has landed');
    });

    // 🗣️F-483: the line from the last stroke goes through these two doors
    // at that stroke's pressure.
    testWidgets('every dab reads the pressure the stroke is handed — and the '
        'same path at another pressure is another stroke', (tester) async {
      final once = _Host();
      await _pump(tester, once, _brush());
      once.show!.landStroke(corner, pressure: 0.3);
      expect({for (final dab in once.committed.single) dab.pressure}, {0.3});

      final host = _Host();
      final overlay = await pumpShown(tester, host);
      host.show!.showStroke(corner, pressure: 0.3);
      await untilShown(tester, overlay);
      expect(host.show!.landStroke(corner), isTrue);
      expect(
        {for (final dab in host.committed.single) dab.pressure},
        {1.0},
        reason: 'shown light, landed at full: laid again at full',
      );
    });

    testWidgets('until it lands it is no stroke: the host hears nothing, and '
        'a save lands nothing of it', (tester) async {
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      await untilShown(tester, overlay);
      expect(host.active, isEmpty, reason: 'the host heard nothing');
      expect(host.lander!(), isFalse, reason: 'a save lands nothing of it');
      expect(host.committed, isEmpty);
      expect(overlay.hasStrokeContent, isTrue, reason: 'and it still shows');

      host.show!.landStroke(corner);
      expect(
        host.active,
        [StrokeInFlight.paints, StrokeInFlight.none],
        reason: 'heard as it lands',
      );
      expect(host.committed, hasLength(1));
    });

    testWidgets('it is shown WHOLE or not at all: a step a frame, and the '
        'overlay holds nothing until the last', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      final frames = await untilShown(tester, overlay);

      // Started, taken to each of its two corners, its dabs blended a share
      // at a time and its tiles pictured: never all in one frame when a
      // frame takes one step.
      expect(frames, greaterThan(4), reason: 'it took a frame a step');
      final shown = Map.of(overlay.tileImages);
      await tester.pump();
      expect(
        overlay.tileImages,
        shown,
        reason: 'nothing more comes: it came up whole',
      );
      host.show!.landStroke(corner);
    });

    testWidgets('the hand moved on: the stroke on screen stays until the '
        'newest is whole, and the newest takes its place', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final short = [p(10, 10), p(30, 10)];
      final once = await laidInOneGo(tester, short);
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      await untilShown(tester, overlay);
      final first = Map.of(overlay.tileImages);
      expect(first.keys.any((tile) => tile.x > 2), isTrue, reason: 'fixture');

      host.show!.showStroke(short);
      await tester.pump();
      expect(overlay.tileImages, first, reason: 'the last whole one stays');
      for (var frame = 0; frame < 400; frame += 1) {
        await tester.pump();
        if (!mapEquals(overlay.tileImages, first)) {
          break;
        }
      }
      expect(
        overlay.tileImages.keys.every((tile) => tile.x <= 2),
        isTrue,
        reason: 'then the newest alone, 10..30 in the first three tiles',
      );

      host.show!.landStroke(short);
      expect(_look(host.committed.single), _look(once.committed.single));
      expect(_tiles(host.data.single), _tiles(once.data.single));
    });

    testWidgets('let go before it is whole, it is finished on the spot and '
        'lands whole', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final once = await laidInOneGo(tester, corner);
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      await tester.pump();
      await tester.pump();
      expect(overlay.hasStrokeContent, isFalse, reason: '⛔premise');
      expect(host.show!.landStroke(corner), isTrue);

      expect(_look(host.committed.single), _look(once.committed.single));
      expect(_tiles(host.data.single), _tiles(once.data.single));
      expect(overlay.hasStrokeContent, isFalse);
    });

    testWidgets('let go on a path the hand reached after the one on screen: '
        'that path lands', (tester) async {
      final short = [p(10, 10), p(30, 10)];
      final once = await laidInOneGo(tester, short);
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      await untilShown(tester, overlay);
      host.show!.showStroke(short);
      host.show!.landStroke(short);

      expect(_look(host.committed.single), _look(once.committed.single));
      expect(_tiles(host.data.single), _tiles(once.data.single));
    });

    testWidgets('dropped, it leaves nothing — and the pen draws as ever '
        'after', (tester) async {
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      await untilShown(tester, overlay);
      host.show!.drop();
      expect(overlay.hasStrokeContent, isFalse);
      await tester.pump();
      expect(overlay.hasStrokeContent, isFalse, reason: 'and stays gone');
      expect(host.committed, isEmpty);
      expect(host.active, isEmpty);

      await _byMouse(tester, const [
        Offset(10, 10),
        Offset(100, 10),
        Offset(100, 50),
      ]);
      expect(host.committed, hasLength(1));
      expect(host.active, [StrokeInFlight.paints, StrokeInFlight.none]);
    });

    testWidgets('a long stretch is laid a share at a time — no frame lays a '
        'tenth of it — and lands as the stroke laid in one go', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final wide = BitmapSurface(
        canvasSize: const CanvasSize(width: 2048, height: 64),
        tileSize: 128,
      );
      final long = [p(10, 32), p(2030, 32)];
      final once = _Host();
      await _pump(tester, once, _brush(), cel: wide);
      once.show!.landStroke(long);

      final host = _Host();
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      await _pump(tester, host, _brush(), overlay: overlay, cel: wide);
      final laid = debugStrokeDabsLaid = <BrushDab>[];
      host.show!.showStroke(long);
      var most = 0;
      for (var frame = 0; frame < 4000 && !overlay.hasStrokeContent; frame++) {
        final before = laid.length;
        await tester.pump();
        most = math.max(most, laid.length - before);
      }
      expect(overlay.hasStrokeContent, isTrue, reason: 'it comes up');
      expect(most, lessThan(laid.length ~/ 10), reason: 'a share a frame');

      host.show!.landStroke(long);
      expect(_look(host.committed.single), _look(once.committed.single));
      expect(_tiles(host.data.single), _tiles(once.data.single));
    });

    testWidgets('given up for another path while it was being pictured, none '
        'of its pictures come up with the other', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final short = [p(10, 10), p(30, 10)];
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      for (var frame = 0; frame < 400 && overlay.stagedCount == 0; frame++) {
        await tester.pump();
      }
      expect(overlay.stagedCount, isNonZero, reason: '⛔premise: pictured');
      expect(overlay.hasStrokeContent, isFalse, reason: '⛔premise: unshown');
      var strayShown = false;
      void watch() =>
          strayShown |= overlay.tileImages.keys.any((tile) => tile.x > 2);
      overlay.addListener(watch);
      addTearDown(() => overlay.removeListener(watch));
      host.show!.showStroke(short);
      host.show!.landStroke(short);

      expect(strayShown, isFalse, reason: 'the corner\'s pictures went');
      expect(host.committed, hasLength(1));
    });

    // An AREA is shown the same way (the shape tool's 「일반」 line and its
    // fill — their pins drive the panel, `a_dragged_shape_shows_what_it_will
    // _lay_test`); this one needs a cel on a grid the panel never uses.
    testWidgets('an area whose pieces share a tile of the cel comes up, and '
        'lands, as that tile with every piece', (tester) async {
      // Pieces are cut on 128px rows of tiles; a cel on a 256px grid holds
      // two of them in one tile.
      final big = BitmapSurface(
        canvasSize: const CanvasSize(width: 256, height: 256),
        tileSize: 256,
      );
      final host = _Host();
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      await _pump(tester, host, _brush(), overlay: overlay, cel: big);
      final region = CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 10, top: 100, right: 60, bottom: 160),
      );
      final area = (
        shape: region,
        pieces: () => regionFillPieces(
          region: region,
          color: 0xFFFF0000,
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
        ),
        blend: BrushBlendMode.color,
      );
      expect(area.pieces(), hasLength(2), reason: 'fixture: one tile, two');

      host.show!.show(area);
      await untilShown(tester, overlay);
      expect(host.show!.land(area), isTrue);

      final landed = host.data.single.promotedTiles!.single.tile.pixels;
      int alphaAt(int x, int y) => landed[(y * 256 + x) * 4 + 3];
      expect(alphaAt(30, 110), 255, reason: 'the piece above 128');
      expect(alphaAt(30, 150), 255, reason: 'the piece below');
    });

    testWidgets('a cel that changes under it takes what showed with it, and '
        'the release lays the path on the cel there is', (tester) async {
      final host = _Host();
      final overlay = await pumpShown(tester, host);

      host.show!.showStroke(corner);
      await untilShown(tester, overlay);
      await _pump(tester, host, _brush(), overlay: overlay, frame: 'frame-b');
      expect(overlay.hasStrokeContent, isFalse);
      expect(host.active, isEmpty, reason: 'no stroke was in flight');

      expect(host.show!.landStroke(corner), isTrue);
      expect(host.committed, hasLength(1));
    });
  });
}

class _Host {
  final shapeShow = ViewHand<ShapeShow>();
  final strokeLander = ViewHand<StrokeLander>();
  ShapeShow? get show => shapeShow.now;
  StrokeLander? get lander => strokeLander.now;
  final data = <BrushStrokeCommitData>[];
  List<List<BrushDab>> get committed => [
    for (final landed in data) landed.sourceDabs,
  ];
  final active = <StrokeInFlight>[];
  int askedForACel = 0;
}

/// The tiles a stroke landed, byte for byte.
Map<TileCoord, List<int>> _tiles(BrushStrokeCommitData data) => {
  for (final placed in data.promotedTiles!) placed.coord: placed.tile.pixels,
};

final _cel = BitmapSurface(
  canvasSize: const CanvasSize(width: 160, height: 64),
  tileSize: 16,
);

/// [stabilizer] null: switched off.
BrushEditCanvasInputSettings _brush({
  double? stabilizer,
  double postStrength = 0,
  BrushTipRotationMode rotation = BrushTipRotationMode.fixed,
}) => BrushToolState.defaults
    .copyWith(
      size: 6,
      roundness: 0.5,
      correction: BrushCorrection(
        steadies: stabilizer != null,
        stabilization: stabilizer ?? 0,
        postStrength: postStrength,
        postBySpeed: false,
      ),
      rotationMode: rotation,
    )
    .toInputSettings();

Future<void> _pump(
  WidgetTester tester,
  _Host host,
  BrushEditCanvasInputSettings settings, {
  bool editable = true,
  bool rowAcceptsStrokes = true,
  bool? celAnswer,
  bool Function()? markMakesItsOwnCel,
  CutGuides? guides,
  ActiveStrokeOverlayModel? overlay,
  String frame = 'frame-a',
  BitmapSurface? cel,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: InteractiveBrushEditCanvasView(
          // A view of its own for each host: the show is handed over
          // when the view is made.
          key: ObjectKey(host),
          celNow: () => cel ?? _cel,
          layerId: const LayerId('layer-a'),
          frameId: FrameId(frame),
          inputSettings: () => settings,
          editable: editable,
          rowAcceptsStrokes: rowAcceptsStrokes,
          guides: guides,
          onPressNeedsCel: celAnswer == null
              ? null
              : () {
                  host.askedForACel += 1;
                  return celAnswer;
                },
          markMakesItsOwnCel: markMakesItsOwnCel,
          onActiveStrokeChanged: host.active.add,
          shapeShow: host.shapeShow,
          strokeLander: host.strokeLander,
          onSourceStrokeCommitted: host.data.add,
          overlayModel: overlay,
        ),
      ),
    ),
  ),
);

/// The same points by a hand that reads nothing from a pen: a mouse, whose
/// pressure is full the whole way.
Future<void> _byMouse(WidgetTester tester, List<Offset> through) async {
  final gesture = await tester.startGesture(
    canvasGlobalOffset(tester, through.first),
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryButton,
  );
  await tester.pump();
  for (final at in through.skip(1)) {
    await gesture.moveTo(canvasGlobalOffset(tester, at));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// What a dab looks like on the cel — where, how big, how strong, and
/// which way it is turned. ⚠️Not its speed or its lean: those are a pen's
/// readings, and a tool has none.
List<Object?> _look(List<BrushDab> dabs) => [
  for (final dab in dabs)
    (
      dab.center.x,
      dab.center.y,
      dab.size,
      dab.opacity,
      dab.flow,
      dab.pressure,
      dab.sequence,
    ),
];

/// Where dabs fall and how big — [_look] without the numbering, which a
/// hand's advances interleave with the first tip's.
List<Object?> _placed(List<BrushDab> dabs) => [
  for (final dab in dabs) (dab.center.x, dab.center.y, dab.size),
];
