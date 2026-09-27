import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/color/color_wheel_panel.dart';
import 'package:anicel/src/ui/export/export_nav_bar.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

/// 🗣️F-200 (유저 2026-09-27): 「띠에 여러 패널 열려있어서 스크롤바
/// 활성화되있을시, 컬러휠 조작 빠르게 스크롤하다보면 다중패널의 스크롤바가
/// 작동해버림. 관련 문제 다른곳도 확인해서 절대 스크롤 밖으로 안새게」.
///
/// The law is CLAUDE.md's: a gesture that starts on a control is that
/// control's, and scrolling happens elsewhere. Every control here drags a
/// value, and each sits in a list that scrolls — the strip of panels is
/// exactly that.
///
/// The pull is [WidgetTester.dragFrom]'s: a first step of 20px, then the
/// rest. 20px is past a scroller's slop (18) and short of a stock pan's
/// (36), which is the race a fast pull lost: the panels' scroller reached
/// its threshold first. A control that takes the arena on its first
/// movement (`axis_bar_gesture.dart`) is not in that race at all.
void main() {
  /// A list that can scroll, with [control] a little way down it.
  Future<ScrollController> inAScrollingList(
    WidgetTester tester,
    Widget control,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 100),
              Center(child: control),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  group('the colour wheel', () {
    Future<(ScrollController, HSVColor Function())> mountWheel(
      WidgetTester tester,
    ) async {
      var hsv = const HSVColor.fromAHSV(1, 0, 1, 1);
      final controller = await inAScrollingList(
        tester,
        SizedBox.square(
          dimension: 200,
          child: StatefulBuilder(
            builder: (context, setState) => ColorWheel(
              hsv: hsv,
              onChanged: (next) => setState(() => hsv = next),
            ),
          ),
        ),
      );
      return (controller, () => hsv);
    }

    /// The hue ring at three o'clock — hue 0.
    Offset ringAtThree(WidgetTester tester) {
      final wheel = tester.getRect(find.byType(ColorWheel));
      return Offset(wheel.right - 9, wheel.center.dy);
    }

    /// The hue the ring reads at [point] — the angle from the centre,
    /// clockwise from three o'clock.
    double hueAt(WidgetTester tester, Offset point) {
      final delta = point - tester.getCenter(find.byType(ColorWheel));
      final degrees = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
      return (degrees + 360) % 360;
    }

    testWidgets('a fast pull turns the wheel and scrolls nothing', (
      tester,
    ) async {
      final (controller, hsv) = await mountWheel(tester);
      final start = ringAtThree(tester);
      await tester.dragFrom(start, const Offset(0, -80));
      await tester.pump();
      expect(
        controller.offset,
        0,
        reason: 'the pull started on the wheel, so the list gets nothing',
      );
      expect(
        hsv().hue,
        moreOrLessEquals(
          hueAt(tester, start + const Offset(0, -80)),
          epsilon: 0.5,
        ),
        reason: 'the wheel followed the pull to where it ended',
      );
    });

    testWidgets('a flick of one move lands where it lifts', (tester) async {
      final (_, hsv) = await mountWheel(tester);
      final start = ringAtThree(tester);
      // The move that wins the arena is the only one — it is reported as
      // the drag's start, never as an update.
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -80));
      await gesture.up();
      await tester.pump();
      expect(
        hsv().hue,
        moreOrLessEquals(
          hueAt(tester, start + const Offset(0, -80)),
          epsilon: 0.5,
        ),
        reason: 'the winning move is applied, not only the press',
      );
    });
  });

  testWidgets('the export scrub bar keeps its drag', (tester) async {
    final positions = <int>[];
    final controller = await inAScrollingList(
      tester,
      SizedBox(
        width: 400,
        child: ExportNavBar(
          axis: const ExportNavAxis(length: 100),
          position: 0,
          onChanged: positions.add,
          enabled: true,
        ),
      ),
    );
    final scrub = find.byKey(const ValueKey<String>('export-nav-scrub'));
    await tester.dragFrom(tester.getCenter(scrub), const Offset(0, -80));
    await tester.pump();
    expect(
      controller.offset,
      0,
      reason: 'the pull started on the scrub bar, so the list gets nothing',
    );
    expect(positions, isNotEmpty, reason: 'the bar was the one dragged');
    expect(positions.toSet(), {50}, reason: 'a pull straight up stays put');
  });

  testWidgets('the transport track keeps its drag', (tester) async {
    final seeks = <int>[];
    final controller = await inAScrollingList(
      tester,
      SizedBox(
        width: 400,
        child: TransportTrack(
          showRange: false,
          frameCount: 101,
          currentFrame: 0,
          inFrame: 0,
          outFrame: 100,
          onSeek: seeks.add,
          onRangeChanged: (_, _) {},
        ),
      ),
    );
    final track = find.byKey(const ValueKey<String>('transport-track'));
    await tester.dragFrom(tester.getCenter(track), const Offset(0, -80));
    await tester.pump();
    expect(
      controller.offset,
      0,
      reason: 'the pull started on the track, so the list gets nothing',
    );
    expect(seeks, isNotEmpty, reason: 'the press seeks on the spot');
    expect(seeks.toSet(), {50}, reason: 'a pull straight up stays put');
  });

  testWidgets('a flick of one move on the transport track lands where it '
      'lifts', (tester) async {
    final seeks = <int>[];
    await inAScrollingList(
      tester,
      SizedBox(
        width: 400,
        child: TransportTrack(
          showRange: false,
          frameCount: 101,
          currentFrame: 0,
          inFrame: 0,
          outFrame: 100,
          onSeek: seeks.add,
          onRangeChanged: (_, _) {},
        ),
      ),
    );
    final track = tester.getRect(
      find.byKey(const ValueKey<String>('transport-track')),
    );
    // In a list the arena is CONTESTED, so the move that wins it is the only
    // one — it is reported as the drag's start, never as an update. (Alone
    // in the arena the drag is accepted at the press, and the move is an
    // update: only here does the start carry it.)
    final gesture = await tester.startGesture(
      track.centerLeft + Offset(track.width * 0.2, 0),
    );
    await gesture.moveBy(Offset(track.width * 0.6, 0));
    await gesture.up();
    await tester.pump();
    expect(
      seeks.last,
      80,
      reason: 'the winning move is applied, not only the press (at 20)',
    );
  });
}
