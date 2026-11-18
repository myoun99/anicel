import 'dart:ui' as ui show PointerChange, PointerData, PointerDataPacket;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/native/qa_pen_points.dart';
import 'package:anicel/src/services/input/pen_path.dart';
import 'package:anicel/src/ui/ui_scale.dart';

import '../helpers/scaled_test_binding.dart';

/// H56: where the platform's events come in, each datum is paired with the
/// points the OS saw of its message ([PenPath]) — in the pixels the tree is
/// laid out in, in the frame of whoever hears it — and every datum asks,
/// the ones the door keeps out too, so their message's points leave the
/// book with them.
void main() {
  final binding = ScaledTestBinding.ensureInitialized();

  tearDown(() {
    AppUiScale.value.value = AppUiScale.defaultScale;
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    QaPenPoints.debugTake = null;
  });

  /// The book as a reader would have written it: [points] for the message
  /// handed at [handed] (physical pixels) — of a contact of [kind] where
  /// one is named —, and nothing for any other. Every ask is noted in
  /// [asked], and its kind in [kinds].
  void book(
    Offset handed,
    List<({Offset at, Duration time, double? force})> points,
    List<Offset> asked, {
    List<double?> driven = const [],
    PointerDeviceKind? kind,
    List<PointerDeviceKind>? kinds,
  }) {
    QaPenPoints.debugTake = (asking, x, y) {
      asked.add(Offset(x, y));
      kinds?.add(asking);
      if (Offset(x, y) != handed || (kind != null && asking != kind)) {
        return null;
      }
      return [
        for (final (index, point) in points.indexed)
          (
            x: point.at.dx,
            y: point.at.dy,
            at: point.time,
            pressure: point.force,
            tilt: null,
            orientation: null,
            driven: index < driven.length ? driven[index] : null,
          ),
      ];
    };
  }

  ui.PointerData datum(
    WidgetTester tester,
    ui.PointerChange change,
    Offset physical, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    Offset? from,
    int buttons = 0,
  }) => ui.PointerData(
    viewId: tester.view.viewId,
    change: change,
    kind: kind,
    buttons: buttons,
    physicalX: physical.dx,
    physicalY: physical.dy,
    // The step from the pointer's last place, as the engine works it
    // out (pointer_data_packet_converter.cc) and the framework reads it.
    physicalDeltaX: from == null ? 0 : physical.dx - from.dx,
    physicalDeltaY: from == null ? 0 : physical.dy - from.dy,
    pressure: 500,
    pressureMax: 1024,
    timeStamp: const Duration(milliseconds: 40),
  );

  testWidgets('a move hears the points of its message, the newest its own', (
    tester,
  ) async {
    AppUiScale.value.value = 1.25;
    final heard = <PointerEvent>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.only(left: 30, top: 10),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerMove: (event) => heard.addAll(PenPath.eventsOf(event)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final ratio = tester.view.devicePixelRatio * 1.25;
    const handed = Offset(600, 400);
    final asked = <Offset>[];
    book(handed, [
      (at: const Offset(500, 380), time: const Duration(milliseconds: 31), force: 0.25),
      (at: const Offset(560, 390), time: const Duration(milliseconds: 35), force: null),
      (at: handed, time: const Duration(milliseconds: 39), force: 0.75),
    ], asked);

    binding.pumpPointerPacket(
      ui.PointerDataPacket(
        data: [
          datum(tester, ui.PointerChange.down, const Offset(400, 360)),
          datum(
            tester,
            ui.PointerChange.move,
            handed,
            from: const Offset(400, 360),
          ),
          datum(tester, ui.PointerChange.up, handed),
        ],
      ),
    );
    await tester.pump();

    expect(heard, hasLength(3));
    Offset local(Offset physical) => physical / ratio - const Offset(30, 10);
    for (final (index, physical) in [
      const Offset(500, 380),
      const Offset(560, 390),
      handed,
    ].indexed) {
      expect(heard[index].localPosition.dx, closeTo(local(physical).dx, 1e-9));
      expect(heard[index].localPosition.dy, closeTo(local(physical).dy, 1e-9));
    }
    expect(heard.map((event) => event.timeStamp), [
      const Duration(milliseconds: 31),
      const Duration(milliseconds: 35),
      const Duration(milliseconds: 39),
    ]);
    expect(heard.map((event) => event.pressure), [
      closeTo(256, 1e-9),
      500,
      closeTo(768, 1e-9),
    ], reason: 'a point the OS gave no pressure keeps its message\'s');
    final steps = [
      const Offset(500, 380) - const Offset(400, 360),
      const Offset(560, 390) - const Offset(500, 380),
      handed - const Offset(560, 390),
    ];
    for (final (index, step) in steps.indexed) {
      expect(heard[index].delta.dx, closeTo(step.dx / ratio, 1e-9));
      expect(heard[index].delta.dy, closeTo(step.dy / ratio, 1e-9));
    }
    expect(
      heard.last.position,
      heard.last.original!.position,
      reason: 'the newest point is the datum\'s own, in the shape handed',
    );
    expect(asked, [
      const Offset(400, 360),
      handed,
      handed,
    ], reason: 'the press, the move and the lift each ask, in order');
  });

  testWidgets(
    "a point's driver pressure rides beside its event, a mouse's and a "
    "stylus's alike — a mouse's range measures none",
    (tester) async {
      final heard = <PointerEvent>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.only(left: 30, top: 10),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: (event) => heard.addAll(PenPath.eventsOf(event)),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      const handed = Offset(600, 400);
      book(handed, [
        (at: const Offset(500, 380), time: const Duration(milliseconds: 31), force: 0.25),
        (at: const Offset(560, 390), time: const Duration(milliseconds: 35), force: null),
        (at: handed, time: const Duration(milliseconds: 39), force: 0.75),
      ], [], driven: [0.2, null, 0.7]);
      List<double?> driven(PointerDeviceKind kind) {
        heard.clear();
        final buttons = kind == PointerDeviceKind.mouse ? kPrimaryButton : 0;
        binding.pumpPointerPacket(
          ui.PointerDataPacket(
            data: [
              for (final (change, at, from) in [
                (ui.PointerChange.down, const Offset(400, 360), null),
                (ui.PointerChange.move, handed, const Offset(400, 360)),
                (ui.PointerChange.up, handed, null),
              ])
                datum(
                  tester,
                  change,
                  at,
                  kind: kind,
                  from: from,
                  buttons: change == ui.PointerChange.up ? 0 : buttons,
                ),
            ],
          ),
        );
        return [for (final event in heard) PenPath.drivenPressureOf(event)];
      }

      expect(driven(PointerDeviceKind.mouse), [0.2, null, 0.7]);
      expect(heard.first.original, isNotNull, reason: 'heard in its frame');
      expect(driven(PointerDeviceKind.stylus), [0.2, null, 0.7]);
    },
  );

  testWidgets(
    "🚨H61 a datum asks for its own kind's points — the cursor that follows "
    "a pen writes its own on the pen's pixels",
    (tester) async {
      final heard = <PointerEvent>[];
      await tester.pumpWidget(
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove: (event) => heard.addAll(PenPath.eventsOf(event)),
          child: const SizedBox.expand(),
        ),
      );
      const handed = Offset(600, 400);
      final kinds = <PointerDeviceKind>[];
      book(
        handed,
        [
          (at: const Offset(500, 380), time: Duration.zero, force: null),
          (at: handed, time: Duration.zero, force: null),
        ],
        [],
        kind: PointerDeviceKind.stylus,
        kinds: kinds,
      );
      List<Offset> moved(PointerDeviceKind kind) {
        heard.clear();
        final buttons = kind == PointerDeviceKind.mouse ? kPrimaryButton : 0;
        binding.pumpPointerPacket(
          ui.PointerDataPacket(
            data: [
              for (final (change, at, from) in [
                (ui.PointerChange.down, const Offset(400, 360), null),
                (ui.PointerChange.move, handed, const Offset(400, 360)),
                (ui.PointerChange.up, handed, null),
              ])
                datum(
                  tester,
                  change,
                  at,
                  kind: kind,
                  from: from,
                  buttons: change == ui.PointerChange.up ? 0 : buttons,
                ),
            ],
          ),
        );
        return [for (final event in heard) event.position];
      }

      expect(
        moved(PointerDeviceKind.mouse),
        hasLength(1),
        reason: "a mouse's move at the pen's pixel is its own point alone",
      );
      expect(
        moved(PointerDeviceKind.stylus),
        hasLength(2),
        reason: "the pen's, its batch's",
      );
      expect(kinds, [
        ...List.filled(3, PointerDeviceKind.mouse),
        ...List.filled(3, PointerDeviceKind.stylus),
      ]);
    },
  );

  testWidgets('a datum the door keeps out still takes its message\'s points', (
    tester,
  ) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchIgnored: true,
    );
    final heard = <PointerEvent>[];
    await tester.pumpWidget(
      Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: heard.add,
        child: const SizedBox.expand(),
      ),
    );
    final asked = <Offset>[];
    book(const Offset(300, 200), const [], asked);

    binding.pumpPointerPacket(
      ui.PointerDataPacket(
        data: [
          datum(
            tester,
            ui.PointerChange.down,
            const Offset(300, 200),
            kind: PointerDeviceKind.touch,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(heard, isEmpty, reason: 'the finger is kept out');
    expect(asked, [const Offset(300, 200)]);
  });

  testWidgets('a datum no message of a contact made asks nothing', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    final asked = <Offset>[];
    book(const Offset(10, 10), const [], asked);

    binding.pumpPointerPacket(
      ui.PointerDataPacket(
        data: [
          datum(tester, ui.PointerChange.add, const Offset(10, 10)),
          datum(tester, ui.PointerChange.remove, const Offset(10, 10)),
        ],
      ),
    );
    await tester.pump();

    expect(asked, isEmpty);
  });
}
