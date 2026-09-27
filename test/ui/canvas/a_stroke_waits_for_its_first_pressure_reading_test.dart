import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/native/qa_pen_ledger.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

import '../brush_canvas_test_helpers.dart';

/// 🚨H43 (유저 2026-09-26, iPad): 「필압있는 브러시 쓸때 첫 펜다운한 부분? 만
/// 입력한 필압보다 센게나와. 최대치가 나오는거같기도하고」.
///
/// The first samples of a contact can carry a value the device has not
/// measured yet — UIKit's force estimate for Apple Pencil (a constant the
/// press repeats until the Pencil measures, corrected later through a
/// callback Flutter's engine never implements), or a Wintab packet the
/// driver took while the pen still hovered. The stroke painted it. It now
/// waits for the contact's first READING and paints every sample that
/// waited with it.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  final ipad = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets(
    'the iPad stroke that waited lands exactly as the same stroke would '
    'have if every sample had read its first reading',
    (tester) async {
      final results = await _parity(
        tester,
        _pressureBrush,
        // The stand-in on the press and on the first move, then the
        // Bluetooth catches up with a light touch. Each sample leans its
        // own way, and the lean and the speed must stay each sample's own.
        waited: [
          _s(const Offset(4, 8), _stand, 0, tilt: 0.2),
          _s(const Offset(20, 8), _stand, 8, tilt: 0.4),
          _s(const Offset(40, 8), 0.25, 20, tilt: 0.6),
          _s(const Offset(70, 8), 0.25, 24, tilt: 0.8),
        ],
        reading: _ipad(0.25),
      );

      final waited = results.first;
      expect(waited.first.center.x, 4, reason: 'the press still lands');
      expect(
        waited.map((dab) => dab.pressure).toSet(),
        {closeTo(_ipad(0.25), 1e-9)},
        reason: 'no dab carries the stand-in',
      );
      expect(_look(waited), _look(results.last));
    },
    variant: ipad,
  );

  testWidgets(
    'the wait holds the stabiliser to the order the pen moved in',
    (tester) async {
      final results = await _parity(
        tester,
        _pressureBrush.copyWith(stabilizerStrength: 40),
        waited: [
          _s(const Offset(4, 8), _stand, 0),
          _s(const Offset(30, 20), _stand, 8),
          _s(const Offset(60, 4), _stand, 16),
          _s(const Offset(90, 24), 0.5, 24),
          _s(const Offset(120, 8), 0.5, 32),
        ],
        reading: _ipad(0.5),
      );

      expect(_look(results.first), _look(results.last));
    },
    variant: ipad,
  );

  testWidgets(
    '🔬the stroke the user drew on build 1064 — the press and three moves '
    'repeat one force, then the Pencil measures',
    (tester) async {
      // 유저 2026-09-27: 「펜 다운 0.33이 1개, 펜 무브 0.33이 3개, 무브 0.16
      // 1개, 무브 0.0 1개, 업 0.0 1개」 — the first start that stayed big.
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([
          _s(const Offset(4, 8), _stand, 0),
          _s(const Offset(20, 8), _stand, 8),
          _s(const Offset(36, 8), _stand, 17),
          _s(const Offset(52, 8), _stand, 25),
          _s(const Offset(68, 8), 0.16, 33),
          _s(const Offset(84, 8), 0.0, 42),
        ]),
      ]);

      final dabs = results.single;
      expect(dabs.first.center.x, 4);
      expect(
        dabs.where((dab) => dab.center.x <= 68).map((dab) => dab.pressure),
        everyElement(closeTo(_ipad(0.16), 1e-9)),
      );
      expect(dabs.last.pressure, 0.0);
    },
    variant: ipad,
  );

  testWidgets(
    'a stand-in in the middle of a stroke keeps the last reading',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([
          _s(const Offset(4, 24), _stand, 0),
          _s(const Offset(30, 24), 0.25, 8),
          // Once the stroke has read, the press's force coming back is
          // still not a reading.
          _s(const Offset(60, 24), _stand, 16),
          _s(const Offset(90, 24), 0.25, 24),
        ]),
      ]);

      expect(
        results.single.map((dab) => dab.pressure).toSet(),
        {closeTo(_ipad(0.25), 1e-9)},
      );
    },
    variant: ipad,
  );

  testWidgets(
    'a tap too short to be measured still leaves its dot, at what the '
    'device reported',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([_s(const Offset(10, 8), _stand, 0)]),
      ]);

      expect(results.single, hasLength(1));
      expect(results.single.single.center.x, 10);
      expect(results.single.single.pressure, closeTo(_ipad(_stand), 1e-9));
    },
    variant: ipad,
  );

  testWidgets(
    'a pen that never measures paints what it reports once the wait runs '
    'out — and a reading after that is used as it comes',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([
          _s(const Offset(4, 8), _stand, 0),
          _s(const Offset(20, 8), _stand, 40),
          _s(const Offset(36, 8), _stand, 80),
          // Past the patience, still the stand-in: the stroke stops waiting.
          _s(const Offset(52, 8), _stand, 120),
          _s(const Offset(90, 8), 2.0, 140),
        ]),
      ]);

      final dabs = results.single;
      expect(dabs.first.center.x, 4);
      expect(
        dabs.where((dab) => dab.center.x <= 52).map((dab) => dab.pressure),
        everyElement(closeTo(_ipad(_stand), 1e-9)),
      );
      expect(dabs.last.pressure, closeTo(_ipad(2.0), 1e-9));
    },
    variant: ipad,
  );

  testWidgets('within the patience the stroke keeps waiting', (tester) async {
    final results = await _strokes(tester, _pressureBrush, [
      _pencil([
        _s(const Offset(4, 8), _stand, 0),
        _s(const Offset(20, 8), _stand, 50),
        _s(const Offset(36, 8), _stand, 100),
        _s(const Offset(60, 8), 1.0, 108),
      ]),
    ]);

    expect(
      results.single.map((dab) => dab.pressure).toSet(),
      {closeTo(_ipad(1.0), 1e-9)},
    );
  }, variant: ipad);

  testWidgets(
    'a brush that does not read pressure never waits for it',
    (tester) async {
      // Observed through the pressure the dabs record: waiting would have
      // handed the pressed dab the later reading. The value draws nothing
      // for this brush — which is exactly why it must not hold the stroke.
      final results = await _strokes(
        tester,
        BrushEditCanvasInputSettings(
          size: 8,
          curves: {
            (BrushPressureTarget.size, BrushInputSource.tilt):
                BrushPressureCurve.identity(),
          },
        ),
        [
          _pencil([
            _s(const Offset(4, 8), _stand, 0),
            _s(const Offset(40, 8), 0.25, 8),
          ]),
        ],
      );

      expect(results.single.first.pressure, closeTo(_ipad(_stand), 1e-9));
    },
    variant: ipad,
  );

  testWidgets(
    'only UIKit repeats a stand-in — elsewhere a force the press repeats is '
    'a reading',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pen(pressureMax: 1, [
          _s(const Offset(4, 8), 0.5, 0),
          _s(const Offset(20, 8), 0.5, 8),
          _s(const Offset(40, 8), 0.9, 16),
        ]),
      ]);

      expect(results.single.first.pressure, closeTo(0.5, 1e-9));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a stroke cancelled while it waits leaves nothing behind for the next',
    (tester) async {
      final results = <List<BrushDab>>[];
      await _pump(tester, _pressureBrush, results);

      await _drive(
        tester,
        _pencil([
          _s(const Offset(4, 20), _stand, 0),
          _s(const Offset(30, 20), _stand, 8),
        ]),
        end: _End.cancel,
      );
      await _drive(
        tester,
        _pencil([
          _s(const Offset(50, 8), _stand, 100),
          _s(const Offset(80, 8), 0.25, 108),
        ]),
      );

      expect(results, hasLength(1));
      expect(
        results.single.map((dab) => dab.center.y).toSet(),
        {8},
        reason: 'nothing the cancelled press held is painted',
      );
    },
    variant: ipad,
  );

  testWidgets(
    'an iPad pencil\'s force reads in Apple\'s unit — the average touch is '
    'half pressure, twice it is full',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([
          _s(const Offset(4, 8), _stand, 0),
          _s(const Offset(20, 8), 1.0, 8),
          _s(const Offset(40, 8), 1.0, 16),
        ]),
        _pencil([
          _s(const Offset(4, 24), _stand, 100),
          _s(const Offset(20, 24), 3.0, 108),
          _s(const Offset(40, 24), 3.0, 116),
        ]),
      ]);

      expect(
        results.first.map((dab) => dab.pressure),
        everyElement(closeTo(0.5, 1e-9)),
      );
      expect(
        results.last.map((dab) => dab.pressure),
        everyElement(closeTo(1.0, 1e-9)),
      );
    },
    variant: ipad,
  );

  testWidgets(
    'a pencil that measures no force still paints at full pressure',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pen(pressureMax: 0, [
          _s(const Offset(4, 8), 0, 0),
          _s(const Offset(40, 8), 0, 8),
        ]),
      ]);

      expect(
        results.single.map((dab) => dab.pressure),
        everyElement(1.0),
      );
    },
    variant: ipad,
  );

  group('the platform\'s own record decides (the pen ledger)', () {
    // What the native ledger would hold, keyed by the pointer's timestamp.
    late Map<Duration, PenLedgerReading> ledger;

    setUp(() {
      ledger = {};
      QaPenLedger.debugForce = (at) => ledger[at];
    });
    tearDown(() {
      QaPenLedger.debugForce = null;
      InputInspector.reset();
    });

    PenLedgerReading measured(double value) =>
        (state: PenLedgerState.measured, value: value);

    testWidgets(
      '🚨UIKit\'s estimate is READ — what waits is the press repeated before '
      'the Pencil measured (build 1065: 「measured 1 · estimated 9」)',
      (tester) async {
        // The device's own pattern: UIKit calls nearly every force an
        // estimate, final or not, and the first four carry the stand-in.
        for (final at in [0, 8, 16, 24, 32]) {
          ledger[_ms(at)] = _estimatedReading;
        }
        ledger[_ms(40)] = (state: PenLedgerState.estimatedFinal, value: 0.0);
        final results = await _strokes(tester, _pressureBrush, [
          _pencil([
            _s(const Offset(4, 8), _stand, 0),
            _s(const Offset(12, 8), _stand, 8),
            _s(const Offset(20, 8), _stand, 16),
            _s(const Offset(28, 8), _stand, 24),
            _s(const Offset(40, 8), 0.16, 32),
            _s(const Offset(60, 8), 0.12, 40),
          ]),
        ]);

        final dabs = results.single;
        expect(dabs.first.center.x, 4);
        expect(dabs.first.pressure, closeTo(_ipad(0.16), 1e-9));
        expect(
          dabs.map((dab) => dab.pressure),
          everyElement(lessThanOrEqualTo(_ipad(0.16) + 1e-9)),
          reason: 'no dab carries the stand-in',
        );
        expect(
          dabs.last.pressure,
          closeTo(_ipad(0.12), 1e-9),
          reason: 'an estimate UIKit calls final is read like any other',
        );
      },
      variant: ipad,
    );

    testWidgets(
      'a force UIKit calls MEASURED that repeats the press still waits — and '
      'is not painted with its record, which is the stand-in',
      (tester) async {
        for (final at in [0, 8, 16]) {
          ledger[_ms(at)] = measured(_stand);
        }
        ledger[_ms(24)] = measured(0.16);
        final results = await _strokes(tester, _pressureBrush, [
          _pencil([
            _s(const Offset(4, 8), _stand, 0),
            _s(const Offset(20, 8), _stand, 8),
            _s(const Offset(36, 8), _stand, 16),
            _s(const Offset(52, 8), 0.16, 24),
          ]),
        ]);

        expect(
          results.single.map((dab) => dab.pressure).toSet(),
          {closeTo(_ipad(0.16), 1e-9)},
        );
      },
      variant: ipad,
    );

    testWidgets(
      'a sample that waited is painted with the force UIKit later measured '
      'for IT',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        ledger[_ms(0)] = _estimatedReading;
        ledger[_ms(8)] = _estimatedReading;
        _down(
          tester,
          const Offset(4, 8),
          time: _ms(0),
          force: 0.5,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        _move(
          tester,
          const Offset(20, 8),
          time: _ms(8),
          force: 0.5,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        // The Bluetooth report lands: UIKit measures the two estimates...
        ledger[_ms(0)] = measured(1.2);
        ledger[_ms(8)] = measured(1.0);
        // ...and the next sample is measured from the start.
        ledger[_ms(16)] = measured(0.8);
        _move(
          tester,
          const Offset(36, 8),
          time: _ms(16),
          force: 0.8,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        _up(tester, const Offset(36, 8), time: _ms(20));
        await tester.pump();

        final dabs = results.single;
        expect(dabs.first.center.x, 4);
        expect(dabs.first.pressure, closeTo(_ipad(1.2), 1e-9));
        expect(
          dabs.where((dab) => dab.center.x == 20).single.pressure,
          closeTo(_ipad(1.0), 1e-9),
        );
        expect(dabs.last.pressure, closeTo(_ipad(0.8), 1e-9));
      },
      variant: ipad,
    );

    testWidgets(
      'on a Mac the event\'s own record decides — a tablet\'s pressure, or '
      'full pressure for a mouse',
      (tester) async {
        // Flutter's macOS embedder calls every pen a mouse.
        for (final at in [0, 8, 16]) {
          ledger[_ms(at)] = measured(0.3);
        }
        for (final at in [100, 108, 116]) {
          ledger[_ms(at)] = (state: PenLedgerState.noPressure, value: 0.0);
        }
        final results = await _strokes(tester, _pressureBrush, [
          _pen(pressureMax: 1, kind: PointerDeviceKind.mouse, [
            _s(const Offset(4, 8), 0, 0),
            _s(const Offset(20, 8), 0, 8),
            _s(const Offset(36, 8), 0, 16),
          ]),
          _pen(pressureMax: 1, kind: PointerDeviceKind.mouse, [
            _s(const Offset(4, 24), 0, 100),
            _s(const Offset(20, 24), 0, 108),
            _s(const Offset(36, 24), 0, 116),
          ]),
        ]);

        expect(
          results.first.map((dab) => dab.pressure),
          everyElement(closeTo(0.3, 1e-9)),
        );
        expect(results.last.map((dab) => dab.pressure), everyElement(1.0));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'the stroke puts how the ledger answered on the inspector\'s ledger line',
      (tester) async {
        InputInspector.visible.value = true;
        ledger[_ms(0)] = _estimatedReading;
        ledger[_ms(8)] = _estimatedReading;
        ledger[_ms(16)] = measured(0.8);
        await _strokes(tester, _pressureBrush, [
          _pencil([
            _s(const Offset(4, 8), 0.5, 0),
            _s(const Offset(20, 8), 0.6, 8),
            _s(const Offset(40, 8), 0.8, 16),
            // A sample the ledger never saw.
            _s(const Offset(70, 8), 0.8, 24),
          ]),
        ]);

        expect(
          InputInspector.notes['ledger'],
          'ledger meas=1 est=2 fin=0 upd=0 rep=1 none=1',
        );
      },
      variant: ipad,
    );

    testWidgets(
      'the ledger line says how UIKit answered — and whether a correction it '
      'sent reached the ledger by the stroke\'s end',
      (tester) async {
        InputInspector.visible.value = true;
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        ledger[_ms(0)] = _estimatedReading;
        ledger[_ms(8)] = (state: PenLedgerState.estimatedFinal, value: 0.0);
        _down(
          tester,
          const Offset(4, 8),
          time: _ms(0),
          force: 0.5,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        _move(
          tester,
          const Offset(20, 8),
          time: _ms(8),
          force: 0.6,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        // UIKit's correction for the press lands after the move was read.
        ledger[_ms(0)] = measured(0.7);
        _up(tester, const Offset(20, 8), time: _ms(12));
        await tester.pump();

        expect(
          InputInspector.notes['ledger'],
          'ledger meas=0 est=1 fin=1 upd=1 rep=1 none=0',
        );
      },
      variant: ipad,
    );
  });

  group('the lean is read as it comes; the direction waits like pressure', () {
    tearDown(() {
      QaPenLedger.debugAltitude = null;
    });

    testWidgets(
      'where Flutter carries no lean, a pen is not made up to stand upright',
      (tester) async {
        final results = await _strokes(tester, _tiltBrush, [
          _pen(pressureMax: 1, [
            _s(const Offset(4, 8), 0.5, 0, tilt: 0.5),
            _s(const Offset(40, 8), 0.5, 8, tilt: 0.5),
          ]),
        ]);

        expect(
          results.single.map((dab) => dab.tiltAltitude),
          everyElement(isNull),
        );
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );

    testWidgets(
      'a lean UIKit estimates is READ as it comes — the stroke does not wait '
      'on it, and a measurement is the measurement',
      (tester) async {
        // ↩️It waited, as the force did, until build 1065 showed UIKit
        // calling nearly every Pencil sample an estimate.
        QaPenLedger.debugAltitude = (at) => at == _ms(16)
            ? (state: PenLedgerState.measured, value: 0.6)
            : _estimatedReading;
        final laid = debugStrokeDabsLaid = <BrushDab>[];
        addTearDown(() => debugStrokeDabsLaid = null);
        final results = <List<BrushDab>>[];
        await _pump(tester, _tiltBrush, results);
        _down(
          tester,
          const Offset(4, 8),
          time: _ms(0),
          force: 1.0,
          tilt: 0.1,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        expect(laid, isNotEmpty, reason: 'the press lands at once');
        _move(
          tester,
          const Offset(20, 8),
          time: _ms(8),
          force: 1.1,
          tilt: 0.3,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        _move(
          tester,
          const Offset(36, 8),
          time: _ms(16),
          force: 1.2,
          tilt: 0.1,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        _up(tester, const Offset(36, 8), time: _ms(20));
        await tester.pump();

        double own(double tilt) => 1 - tilt / (math.pi / 2);
        final dabs = results.single;
        expect(dabs.first.center.x, 4);
        expect(dabs.first.tiltAltitude, closeTo(own(0.1), 1e-9));
        expect(
          dabs.where((dab) => dab.center.x == 20).single.tiltAltitude,
          closeTo(own(0.3), 1e-9),
        );
        expect(dabs.last.tiltAltitude, closeTo(0.6 / (math.pi / 2), 1e-9));
      },
      variant: ipad,
    );

    testWidgets(
      'a tip that follows the stroke is laid at the press along the way the '
      'stroke set off',
      (tester) async {
        final results = await _strokes(tester, _directionBrush, [
          _pen(pressureMax: 1, [
            _s(const Offset(4, 4), 0.5, 0),
            // Down and to the right: 315° on the screen.
            _s(const Offset(24, 24), 0.5, 8),
            _s(const Offset(44, 24), 0.5, 16),
          ]),
        ]);

        final press = results.single.first;
        expect((press.center.x, press.center.y), (4, 4));
        // The tip-stamp cache bakes the turn into the dab's mask; the
        // mask's key ends with it in whole degrees.
        expect(press.tipMask?.id, endsWith('|315'));
      },
    );

    testWidgets(
      'a lean UIKit estimates between two it measured is its own — not the '
      'last measurement — and a tap lands with its own',
      (tester) async {
        final altitudes = <Duration, PenLedgerReading>{
          _ms(0): (state: PenLedgerState.measured, value: 0.9),
          _ms(8): _estimatedReading,
          _ms(16): (state: PenLedgerState.measured, value: 0.9),
          _ms(100): _estimatedReading,
        };
        QaPenLedger.debugAltitude = (at) => altitudes[at];
        final results = await _strokes(tester, _tiltBrush, [
          _pencil([
            _s(const Offset(4, 8), 1.0, 0, tilt: 0.1),
            // Its own lean differs, and UIKit calls it an estimate.
            _s(const Offset(20, 8), 1.1, 8, tilt: 0.7),
            _s(const Offset(36, 8), 1.2, 16, tilt: 0.1),
          ]),
          _pencil([_s(const Offset(60, 24), 1.0, 100, tilt: 0.7)]),
        ]);

        double own(double tilt) => 1 - tilt / (math.pi / 2);
        const measured = 0.9 / (math.pi / 2);
        final dabs = results.first;
        expect(dabs.first.tiltAltitude, closeTo(measured, 1e-9));
        expect(
          dabs.where((dab) => dab.center.x == 20).single.tiltAltitude,
          closeTo(own(0.7), 1e-9),
        );
        expect(dabs.last.tiltAltitude, closeTo(measured, 1e-9));
        expect(results.last.single.tiltAltitude, closeTo(own(0.7), 1e-9));
      },
      variant: ipad,
    );

    testWidgets(
      'scatter thrown across the stroke throws the press across the way it '
      'set off',
      (tester) async {
        final results = await _strokes(tester, _acrossScatterBrush, [
          _pen(pressureMax: 1, [
            _s(const Offset(20, 16), 0.5, 0),
            // Straight to the right: across is straight up and down.
            _s(const Offset(60, 16), 0.5, 8),
          ]),
        ]);

        expect(results.single.first.center.x, closeTo(20, 1e-9));
      },
    );

    testWidgets('a tap that never moved has no direction to follow', (
      tester,
    ) async {
      final results = await _strokes(tester, _directionBrush, [
        _pen(pressureMax: 1, [_s(const Offset(10, 10), 0.5, 0)]),
      ]);

      expect(results.single.single.tipMask?.id, endsWith('|0'));
    });
  });

  group('on a desktop the lean is the platform\'s own word '
      '(desktop-pen-tilt)', () {
    tearDown(() {
      QaPenLedger.debugTilt = null;
    });

    // 30° from vertical is 60° up: two thirds of a right angle.
    const upright = 2.0 / 3.0;

    testWidgets(
      'on a Mac, the event\'s own record — AppKit\'s tilt — and none for a '
      'mouse',
      (tester) async {
        // Flutter's macOS embedder calls every pen a mouse; the ledger
        // knows which events were a tablet's.
        final tilts = <Duration, PenLedgerTilt>{
          for (final at in [0, 8, 16]) _ms(at): (x: 30 / 90, y: 0),
        };
        QaPenLedger.debugTilt = (at) => tilts[at];
        final results = await _strokes(tester, _tiltBrush, [
          _pen(pressureMax: 1, kind: PointerDeviceKind.mouse, [
            _s(const Offset(4, 8), 0, 0),
            _s(const Offset(20, 8), 0, 8),
            _s(const Offset(40, 8), 0, 16),
          ]),
          _pen(pressureMax: 1, kind: PointerDeviceKind.mouse, [
            _s(const Offset(4, 24), 0, 100),
            _s(const Offset(40, 24), 0, 108),
          ]),
        ]);

        expect(
          results.first.map((dab) => dab.tiltAltitude),
          everyElement(closeTo(upright, 1e-9)),
        );
        expect(
          results.first.map((dab) => dab.tiltAzimuthDegrees),
          everyElement(closeTo(0, 1e-9)),
          reason: 'the top leans right',
        );
        expect(
          results.last.map((dab) => dab.tiltAltitude),
          everyElement(isNull),
          reason: 'a mouse leans nowhere, and is not an upright pen',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'on Windows, the driver\'s — the HID report\'s tilt first, Wintab\'s '
      'orientation where the report has none, and none where neither does',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _tiltBrush, results);
        final hid = RawPenInputService.instance;
        final wintab = WintabPenService.instance;
        RawPenInputService.debugClockOverride = () => DateTime(2024);
        WintabPenService.debugClockOverride = () => DateTime(2024);
        ({double x, double y})? hidTilt = (x: 0, y: 30);
        var sequence = 0;
        hid.debugPollOverride = () {
          sequence += 1;
          return QaPenRawState(flags: 0x01, sequence: sequence, tilt: hidTilt);
        };
        hid.start();
        wintab.debugPollOverride = () => const [];
        wintab.start();
        wintab.debugInjectPacket(
          const QaTabletPacket(
            pressure: 0.5,
            orientation: (bearing: 90, altitude: upright),
            timeMs: 1,
            buttons: 1,
          ),
        );

        await _drive(
          tester,
          _pen(pressureMax: 1, [
            _s(const Offset(4, 8), 0.5, 0),
            _s(const Offset(40, 8), 0.5, 8),
          ]),
        );
        hidTilt = null;
        await _drive(
          tester,
          _pen(pressureMax: 1, [
            _s(const Offset(4, 16), 0.5, 100),
            _s(const Offset(40, 16), 0.5, 108),
          ]),
        );
        wintab.debugInjectPacket(
          const QaTabletPacket(pressure: 0.5, timeMs: 2, buttons: 1),
        );
        await _drive(
          tester,
          _pen(pressureMax: 1, [
            _s(const Offset(4, 24), 0.5, 200),
            _s(const Offset(40, 24), 0.5, 208),
          ]),
        );

        expect(results, hasLength(3));
        // HID: the top leans toward the user.
        expect(
          results[0].map((dab) => dab.tiltAltitude),
          everyElement(closeTo(upright, 1e-9)),
        );
        expect(
          results[0].map((dab) => dab.tiltAzimuthDegrees),
          everyElement(closeTo(90, 1e-9)),
        );
        // Wintab: the top's bearing is east — it leans right.
        expect(
          results[1].map((dab) => dab.tiltAltitude),
          everyElement(closeTo(upright, 1e-9)),
        );
        expect(
          results[1].map((dab) => dab.tiltAzimuthDegrees),
          everyElement(closeTo(0, 1e-9)),
        );
        expect(
          results[2].map((dab) => dab.tiltAltitude),
          everyElement(isNull),
          reason: 'a device that declares no orientation leans nowhere',
        );
        // The poll timers must die BEFORE the binding's pending-timer
        // invariant check (which runs ahead of tearDown callbacks).
        hid.debugReset();
        wintab.debugReset();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'the stroke puts how its samples leaned on the inspector\'s lean line',
      (tester) async {
        InputInspector.visible.value = true;
        final tilts = <Duration, PenLedgerTilt>{
          _ms(0): (x: 30 / 90, y: 0),
          _ms(8): (x: 60 / 90, y: 0),
        };
        QaPenLedger.debugTilt = (at) => tilts[at];
        await _strokes(tester, _tiltBrush, [
          _pen(pressureMax: 1, kind: PointerDeviceKind.mouse, [
            _s(const Offset(4, 8), 0, 0),
            _s(const Offset(20, 8), 0, 8),
            // A sample the ledger holds no tilt for.
            _s(const Offset(40, 8), 0, 16),
          ]),
        ]);

        expect(InputInspector.notes['lean'], 'lean 2/3 alt 0.33–0.67');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('speed waits like pressure (opening-dab-speed-Q1)', () {
    setUp(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        speedReferencePixelsPerSecond: 1000,
      );
    });

    testWidgets(
      'a press that read its pressure keeps it while it waits for a speed',
      (tester) async {
        final results = await _strokes(tester, _speedAndPressureBrush, [
          _pen(pressureMax: 1, [
            _s(const Offset(4, 8), 0.4, 0),
            // 100 canvas px in 200 ms: 500 px/s, half the reference.
            _s(const Offset(104, 8), 0.6, 200),
          ]),
        ]);

        final press = results.single.first;
        expect(press.center.x, 4);
        expect(press.speed, closeTo(0.5, 1e-9), reason: 'the first move');
        expect(press.pressure, closeTo(0.4, 1e-9), reason: 'its own');
      },
    );

    testWidgets(
      'each input is filled by ITS first reading — the first speed measured '
      'and the first real force, whichever came first',
      (tester) async {
        final results = await _strokes(tester, _speedAndPressureBrush, [
          _pencil([
            _s(const Offset(4, 8), _stand, 0),
            // 20 px in 8 ms: past the reference, so 1.
            _s(const Offset(24, 8), _stand, 8),
            // 5 px in 8 ms: 625 px/s.
            _s(const Offset(29, 8), 0.8, 16),
            _s(const Offset(54, 8), 0.8, 24),
          ]),
        ]);

        final press = results.single.first;
        expect(press.center.x, 4);
        expect(press.speed, closeTo(1.0, 1e-9));
        expect(press.pressure, closeTo(_ipad(0.8), 1e-9));
      },
      variant: ipad,
    );

    testWidgets(
      'a move on the press\'s own clock tick measures nothing — the press '
      'waits for one that does',
      (tester) async {
        final results = await _strokes(tester, _speedAndPressureBrush, [
          _pen(pressureMax: 1, [
            _s(const Offset(4, 8), 0.5, 0),
            _s(const Offset(20, 8), 0.5, 0),
            // 50 px in 100 ms: 500 px/s.
            _s(const Offset(70, 8), 0.5, 100),
          ]),
        ]);

        expect(results.single.first.speed, closeTo(0.5, 1e-9));
      },
    );
  });

  group('nothing is held that has nothing to wait for, and a wait ends the '
      'moment it can', () {
    // What the canvas has been handed so far — WHEN a sample landed, which
    // the committed stroke cannot say.
    late List<BrushDab> laid;

    setUp(() {
      debugStrokeDabsLaid = laid = <BrushDab>[];
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        speedReferencePixelsPerSecond: 1000,
      );
    });
    tearDown(() {
      debugStrokeDabsLaid = null;
      QaPenLedger.debugForce = null;
      QaPenLedger.debugAltitude = null;
      InputInspector.reset();
    });

    for (final (name, brush) in [
      ('a brush that reads none of it', BrushEditCanvasInputSettings(size: 10)),
      (
        'scatter thrown all around',
        BrushEditCanvasInputSettings(
          size: 10,
          scatterRadiusRatio: 1.0,
          scatterBothAxes: true,
        ),
      ),
    ]) {
      testWidgets(
        '$name lays its press at the down — whatever the press has yet to '
        'measure',
        (tester) async {
          // UIKit calls the press's force AND lean estimates, and no move has
          // measured a speed or set a direction yet: nothing this brush
          // draws with.
          QaPenLedger.debugForce = (_) => _estimatedReading;
          QaPenLedger.debugAltitude = (_) => _estimatedReading;
          await _pump(tester, brush, <List<BrushDab>>[]);
          _down(
            tester,
            const Offset(4, 8),
            time: _ms(0),
            force: _stand,
            tilt: 0.3,
            pressureMax: _pencilMax,
          );
          await tester.pump();

          expect(
            laid,
            isNotEmpty,
            reason: 'a wait for an input the brush does not read only makes '
                'the stroke start late',
          );
          _up(tester, const Offset(4, 8), time: _ms(4));
          await tester.pump();
        },
        variant: ipad,
      );
    }

    testWidgets(
      'a stroke that waited lands the moment its last reading comes — not '
      'when the patience runs out',
      (tester) async {
        await _pump(tester, _pressureBrush, <List<BrushDab>>[]);
        _down(
          tester,
          const Offset(4, 8),
          time: _ms(0),
          force: _stand,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        _move(
          tester,
          const Offset(20, 8),
          time: _ms(8),
          force: _stand,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        expect(laid, isEmpty, reason: '⛔premise: the stand-in is held');

        _move(
          tester,
          const Offset(36, 8),
          time: _ms(16),
          force: 0.5,
          pressureMax: _pencilMax,
        );
        await tester.pump();
        expect(laid.first.center.x, 4, reason: 'the press, at the reading');
        expect(laid.any((dab) => dab.center.x == 36), isTrue);

        _up(tester, const Offset(36, 8), time: _ms(20));
        await tester.pump();
      },
      variant: ipad,
    );

    testWidgets(
      'a tap UIKit never measured lands with its stand-in in Apple\'s unit',
      (tester) async {
        QaPenLedger.debugForce = (_) => _estimatedReading;
        final results = await _strokes(tester, _pressureBrush, [
          _pencil([_s(const Offset(10, 8), 0.5, 0)]),
        ]);

        expect(results.single.single.pressure, closeTo(_ipad(0.5), 1e-9));
      },
      variant: ipad,
    );

    testWidgets(
      'samples whose lean was never measured land with their own',
      (tester) async {
        QaPenLedger.debugAltitude = (_) => _estimatedReading;
        final results = await _strokes(tester, _tiltBrush, [
          _pencil([
            _s(const Offset(4, 8), 1.0, 0, tilt: 0.1),
            _s(const Offset(20, 8), 1.1, 8, tilt: 0.5),
            _s(const Offset(36, 8), 1.2, 16, tilt: 0.9),
          ]),
        ]);

        double own(double tilt) => 1 - tilt / (math.pi / 2);
        final dabs = results.single;
        expect(dabs.first.tiltAltitude, closeTo(own(0.1), 1e-9));
        for (final (x, tilt) in const [(20.0, 0.5), (36.0, 0.9)]) {
          expect(
            dabs.where((dab) => dab.center.x == x).single.tiltAltitude,
            closeTo(own(tilt), 1e-9),
          );
        }
      },
      variant: ipad,
    );

    testWidgets(
      'an input the brush does not read is not filled — the press keeps the '
      'force the device reported',
      (tester) async {
        // The press waits for the first move's SPEED; that move is also the
        // first real force, which this brush never reads.
        final results = await _strokes(tester, _speedBrush, [
          _pencil([
            _s(const Offset(4, 8), _stand, 0),
            _s(const Offset(24, 8), 0.8, 8),
            _s(const Offset(44, 8), 0.8, 16),
          ]),
        ]);

        expect(results.single.first.pressure, closeTo(_ipad(_stand), 1e-9));
      },
      variant: ipad,
    );

    testWidgets(
      '… and likewise the lean the device reported',
      (tester) async {
        QaPenLedger.debugAltitude = (at) => at == _ms(0)
            ? _estimatedReading
            : (state: PenLedgerState.measured, value: 0.6);
        final results = await _strokes(tester, _speedBrush, [
          _pencil([
            _s(const Offset(4, 8), 1.0, 0, tilt: 0.3),
            _s(const Offset(24, 8), 1.0, 8, tilt: 0.3),
            _s(const Offset(44, 8), 1.0, 16, tilt: 0.3),
          ]),
        ]);

        expect(
          results.single.first.tiltAltitude,
          closeTo(1 - 0.3 / (math.pi / 2), 1e-9),
        );
      },
      variant: ipad,
    );

    testWidgets(
      'each stroke\'s press follows the way THAT stroke set off',
      (tester) async {
        final results = await _strokes(tester, _directionBrush, [
          _pen(pressureMax: 1, [
            _s(const Offset(4, 4), 0.5, 0),
            _s(const Offset(24, 24), 0.5, 8),
            _s(const Offset(44, 24), 0.5, 16),
          ]),
          _pen(pressureMax: 1, [
            _s(const Offset(64, 28), 0.5, 100),
            // Up and to the right: 45° on the screen.
            _s(const Offset(84, 8), 0.5, 108),
            _s(const Offset(104, 8), 0.5, 116),
          ]),
        ]);

        expect(results.first.first.tipMask?.id, endsWith('|315'));
        expect(results.last.first.tipMask?.id, endsWith('|45'));
      },
    );

    testWidgets(
      'what a cancelled stroke held is not painted by a next press that has '
      'nothing to wait for',
      (tester) async {
        // The first contact waits on its stand-in and is cancelled; the
        // second must not paint what it held.
        QaPenLedger.debugForce = (at) => at < _ms(100)
            ? _estimatedReading
            : (state: PenLedgerState.measured, value: 1.0);
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);

        await _drive(
          tester,
          _pencil([
            _s(const Offset(4, 20), 0.5, 0),
            _s(const Offset(30, 20), 0.5, 8),
          ]),
          end: _End.cancel,
        );
        await _drive(
          tester,
          _pencil([
            _s(const Offset(50, 8), 1.0, 100),
            _s(const Offset(80, 8), 1.0, 108),
          ]),
        );

        expect(results, hasLength(1));
        expect(
          results.single.map((dab) => dab.center.y).toSet(),
          {8},
          reason: 'nothing the cancelled press held is painted',
        );
      },
      variant: ipad,
    );

    testWidgets(
      'each stroke\'s ledger line counts that stroke alone',
      (tester) async {
        InputInspector.visible.value = true;
        final ledger = <Duration, PenLedgerReading>{
          _ms(0): _estimatedReading,
          _ms(8): (state: PenLedgerState.measured, value: 0.8),
          _ms(100): (state: PenLedgerState.measured, value: 0.6),
        };
        QaPenLedger.debugForce = (at) => ledger[at];
        await _strokes(tester, _pressureBrush, [
          _pencil([
            _s(const Offset(4, 8), 0.5, 0),
            _s(const Offset(40, 8), 0.8, 8),
          ]),
          _pencil([_s(const Offset(4, 24), 0.6, 100)]),
        ]);

        expect(
          InputInspector.notes['ledger'],
          'ledger meas=1 est=0 fin=0 upd=0 rep=1 none=0',
        );
      },
      variant: ipad,
    );
  });

  group('Wintab', () {
    late List<QaTabletPacket> queue;

    void live() {
      final service = WintabPenService.instance;
      WintabPenService.debugClockOverride = () => DateTime(2024);
      queue = <QaTabletPacket>[];
      service.debugPollOverride = () {
        final drained = queue;
        queue = [];
        return drained;
      };
      service.start();
    }

    /// HID already reports the tip down — the press is a press — while
    /// Wintab's queue still ends with the pen above the tablet.
    RawPenInputService hidTipDown() {
      final hid = RawPenInputService.instance;
      RawPenInputService.debugClockOverride = () => DateTime(2024);
      hid.debugPollOverride = () =>
          const QaPenRawState(flags: 0x01, sequence: 1);
      hid.start();
      return hid;
    }

    testWidgets(
      'a packet the driver took while the pen still hovered is not the '
      'contact\'s first reading — a pen the OS calls a mouse waits for one',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;
        final hid = hidTipDown();

        service.debugInjectPacket(_packet(pressure: 0, buttons: 0));
        const mouse = PointerDeviceKind.mouse;
        _down(tester, const Offset(4, 8), time: _ms(0), kind: mouse);
        await tester.pump();
        // The contact's packet reaches the queue before the first move.
        queue = [_packet(pressure: 0.6, buttons: 1)];
        _move(tester, const Offset(40, 8), time: _ms(8), kind: mouse);
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16), kind: mouse);
        await tester.pump();

        expect(results.single.first.center.x, 4);
        expect(
          results.single.map((dab) => dab.pressure).toSet(),
          {closeTo(0.6, 1e-9)},
        );
        // The poll timers must die BEFORE the binding's pending-timer
        // invariant check (which runs ahead of tearDown callbacks).
        service.debugReset();
        hid.debugReset();
      },
    );

    testWidgets(
      'while Wintab has not reached the contact, an Ink stylus opens with '
      'its own reading — it has one',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;
        final hid = hidTipDown();

        service.debugInjectPacket(_packet(pressure: 0, buttons: 0));
        _down(tester, const Offset(4, 8), time: _ms(0), force: 0.3);
        await tester.pump();
        queue = [_packet(pressure: 0.6, buttons: 1)];
        _move(tester, const Offset(40, 8), time: _ms(8), force: 0.3);
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16));
        await tester.pump();

        expect(results.single.first.pressure, closeTo(0.3, 1e-9));
        expect(results.single.last.pressure, closeTo(0.6, 1e-9));
        service.debugReset();
        hid.debugReset();
      },
    );

    testWidgets(
      'a press whose contact packet the timer had not taken yet still draws '
      '— at that packet\'s pressure',
      (tester) async {
        // The press's BUTTONS come off the same packet (PEN-7a), so the
        // timer's hovering copy did not just misweigh the first dab: it said
        // the tip was up, and the press drew nothing at all.
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;

        service.debugInjectPacket(_packet(pressure: 0, buttons: 0));
        queue = [_packet(pressure: 0.6, buttons: 1)];
        _down(tester, const Offset(4, 8), time: _ms(0));
        await tester.pump();
        _move(tester, const Offset(40, 8), time: _ms(8));
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16));
        await tester.pump();

        expect(results.single.first.center.x, 4);
        expect(results.single.first.pressure, closeTo(0.6, 1e-9));
        service.debugReset();
      },
    );

    testWidgets(
      'once the contact has read, a hovering packet is the pen lifting — '
      'and 0 is its reading',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;

        service.debugInjectPacket(_packet(pressure: 0.6, buttons: 1));
        _down(tester, const Offset(4, 8), time: _ms(0), force: 0.3);
        await tester.pump();
        queue = [_packet(pressure: 0, buttons: 0)];
        // The pointer still reports a pressure of its own: the driver's
        // word is the one that stands mid-stroke (PEN-2), not the pointer's.
        _move(tester, const Offset(40, 8), time: _ms(8), force: 0.3);
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16));
        await tester.pump();

        expect(results.single.first.pressure, closeTo(0.6, 1e-9));
        expect(results.single.last.pressure, 0.0);
        service.debugReset();
      },
    );
  });
}

/// Apple Pencil's `maximumPossibleForce`, which the iOS engine hands over
/// as the pointer's `pressureMax` — and which the app does not divide by.
const double _pencilMax = 25 / 6;

/// The pressure an iPad pencil's force lands as: Apple's average touch
/// (1.0) is half pressure (유저 2026-09-27, `ipad-pencil-pressure-scale-Q1`).
double _ipad(double force) => (force / 2.0).clamp(0.0, 1.0);

/// A stand-in force, as the user's inspector showed it on build 1064. The
/// rule does not read the value — only that the press's force repeats — so
/// it is deliberately not the 1/3 the forums logged.
const double _stand = 0.33;

final BrushEditCanvasInputSettings _pressureBrush =
    BrushEditCanvasInputSettings(
      size: 40,
      sizePressureCurve: BrushPressureCurve.identity(),
    );

final BrushEditCanvasInputSettings _tiltBrush = BrushEditCanvasInputSettings(
  size: 40,
  curves: {
    (BrushPressureTarget.size, BrushInputSource.tilt):
        BrushPressureCurve.identity(),
  },
);

final BrushEditCanvasInputSettings _directionBrush =
    BrushEditCanvasInputSettings(
      size: 10,
      roundness: 0.5,
      rotationMode: BrushTipRotationMode.direction,
    );

final BrushEditCanvasInputSettings _acrossScatterBrush =
    BrushEditCanvasInputSettings(
      size: 10,
      scatterRadiusRatio: 1.0,
      scatterBothAxes: false,
    );

const PenLedgerReading _estimatedReading = (
  state: PenLedgerState.estimated,
  value: 0.0,
);

final BrushEditCanvasInputSettings _speedAndPressureBrush =
    BrushEditCanvasInputSettings(
      size: 40,
      curves: {
        (BrushPressureTarget.size, BrushInputSource.pressure):
            BrushPressureCurve.identity(),
        (BrushPressureTarget.size, BrushInputSource.speed):
            BrushPressureCurve.identity(),
      },
    );

final BrushEditCanvasInputSettings _speedBrush = BrushEditCanvasInputSettings(
  size: 40,
  curves: {
    (BrushPressureTarget.size, BrushInputSource.speed):
        BrushPressureCurve.identity(),
  },
);

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

typedef _Sample = ({Offset at, double force, Duration time, double tilt});

/// One pen sample: where, the RAW force the device reported, when (in ms),
/// and how far the pen leans from upright (radians, Flutter's `tilt`).
_Sample _s(Offset at, double force, int ms, {double tilt = 0}) =>
    (at: at, force: force, time: _ms(ms), tilt: tilt);

typedef _Stroke = ({
  List<_Sample> samples,
  double pressureMax,
  PointerDeviceKind kind,
});

_Stroke _pencil(List<_Sample> samples) =>
    _pen(samples, pressureMax: _pencilMax);

_Stroke _pen(
  List<_Sample> samples, {
  required double pressureMax,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) => (samples: samples, pressureMax: pressureMax, kind: kind);

/// What a landed dab is — where, how big, how opaque, and every input it
/// was drawn with — in the order it was laid.
List<Object?> _look(List<BrushDab> dabs) => [
  for (final dab in dabs)
    (
      dab.center.x,
      dab.center.y,
      dab.size,
      dab.opacity,
      dab.pressure,
      dab.speed,
      dab.tiltAltitude,
    ),
];

/// Draws [waited] on an iPad, then the same hand where nothing ever stands
/// in — on Android, every sample already at the [reading] the wait filled
/// in — and returns both strokes.
Future<List<List<BrushDab>>> _parity(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings, {
  required List<_Sample> waited,
  required double reading,
}) async {
  final results = <List<BrushDab>>[];
  await _pump(tester, settings, results);
  await _drive(tester, _pencil(waited));
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await _drive(
    tester,
    _pen(pressureMax: 1, [
      for (final sample in waited)
        (at: sample.at, force: reading, time: sample.time, tilt: sample.tilt),
    ]),
  );
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  expect(results, hasLength(2));
  return results;
}

Future<List<List<BrushDab>>> _strokes(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings,
  List<_Stroke> strokes,
) async {
  final results = <List<BrushDab>>[];
  await _pump(tester, settings, results);
  for (final stroke in strokes) {
    await _drive(tester, stroke);
  }
  return results;
}

Future<void> _pump(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings,
  List<List<BrushDab>> results,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: InteractiveBrushEditCanvasView(
            sessionState: BrushEditSessionState(
              canvasState: CanvasSurfaceState(
                currentSurface: BitmapSurface(
                  canvasSize: const CanvasSize(width: 160, height: 32),
                  tileSize: 16,
                ),
              ),
              materializationHistoryState:
                  BrushBitmapMaterializationHistoryState(),
            ),
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            inputSettings: () => settings,
            onSourceStrokeCommitted: (data) => results.add(data.sourceDabs),
          ),
        ),
      ),
    ),
  );
}

enum _End { lift, cancel }

/// One stylus contact through raw pointer events — the only way a test can
/// set pressure — with the pointer id and clock stamps held constant between
/// runs, so two strokes of the same hand roll the same dice.
Future<void> _drive(
  WidgetTester tester,
  _Stroke stroke, {
  _End end = _End.lift,
}) async {
  final first = stroke.samples.first;
  _down(
    tester,
    first.at,
    time: first.time,
    force: first.force,
    tilt: first.tilt,
    pressureMax: stroke.pressureMax,
    kind: stroke.kind,
  );
  await tester.pump();
  for (final sample in stroke.samples.skip(1)) {
    _move(
      tester,
      sample.at,
      time: sample.time,
      force: sample.force,
      tilt: sample.tilt,
      pressureMax: stroke.pressureMax,
      kind: stroke.kind,
    );
    await tester.pump();
  }
  final last = stroke.samples.last;
  tester.binding.handlePointerEvent(
    end == _End.lift
        ? PointerUpEvent(
            pointer: 1,
            kind: stroke.kind,
            position: canvasGlobalOffset(tester, last.at),
            timeStamp: last.time + _ms(4),
            pressureMax: stroke.pressureMax,
          )
        : PointerCancelEvent(
            pointer: 1,
            kind: stroke.kind,
            position: canvasGlobalOffset(tester, last.at),
            timeStamp: last.time + _ms(4),
          ),
  );
  await tester.pump();
}

void _down(
  WidgetTester tester,
  Offset at, {
  required Duration time,
  double force = 0,
  double tilt = 0,
  double pressureMax = 1,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) => tester.binding.handlePointerEvent(
  PointerDownEvent(
    pointer: 1,
    kind: kind,
    position: canvasGlobalOffset(tester, at),
    timeStamp: time,
    pressure: force,
    pressureMin: 0,
    pressureMax: pressureMax,
    tilt: tilt,
  ),
);

void _move(
  WidgetTester tester,
  Offset at, {
  required Duration time,
  double force = 0,
  double tilt = 0,
  double pressureMax = 1,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) => tester.binding.handlePointerEvent(
  PointerMoveEvent(
    pointer: 1,
    kind: kind,
    position: canvasGlobalOffset(tester, at),
    timeStamp: time,
    pressure: force,
    pressureMin: 0,
    pressureMax: pressureMax,
    tilt: tilt,
  ),
);

void _up(
  WidgetTester tester,
  Offset at, {
  required Duration time,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) => tester.binding.handlePointerEvent(
  PointerUpEvent(
    pointer: 1,
    kind: kind,
    position: canvasGlobalOffset(tester, at),
    timeStamp: time,
  ),
);

QaTabletPacket _packet({required double pressure, required int buttons}) =>
    QaTabletPacket(
      pressure: pressure,
      timeMs: 1,
      buttons: buttons,
    );
