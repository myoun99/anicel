import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuPlaceTook;

import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/debug/debug_window.dart';
import 'package:anicel/src/ui/debug/engine_stages.dart';
import 'package:anicel/src/ui/debug/frame_stats.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/text_finders.dart';

/// 🔬The debug window on the Galaxy Tab's screen, 1579x986 logical
/// (🗣️관제 2026-11-24, card one-debug-window-shows-everything: 「갤탭 한
/// 화면에 잘림 없이, 자리 예약」): every line in the app's own face is as
/// wide as its column lets it be, and no column runs past the screen —
/// with every place of the engine's stages it shows told, the longest the
/// window says. On a smaller screen the window is made smaller, never cut.
void main() {
  setUpAll(loadTheAppFaces);

  setUp(() {
    MeasurementMode.reset();
    EngineStages.install();
    FrameStats.install();
    FrameStats.reset();
  });

  tearDown(() {
    MeasurementMode.reset();
    EngineStages.forget();
    FrameStats.reset();
    ScreenTexture.tookAsItWentUp = null;
  });

  testWidgets('every line fits its column and every column the screen', (
    tester,
  ) async {
    await _openAtItsLongest(tester, const Size(1579, 986));

    expect(tester.takeException(), isNull, reason: 'a column ran past');

    // Laid as they are, not made smaller to fit: on this screen the
    // columns are as tall as the window lets them be.
    final body = _body(tester);
    final laid = body.child!.size;
    expect(
      laid.height,
      lessThanOrEqualTo(body.size.height + 0.5),
      reason: 'the columns are ${laid.height.round()} tall in '
          '${body.size.height.round()} — made smaller to fit',
    );
    expect(laid.width, lessThanOrEqualTo(body.size.width + 0.5));

    final clipped = _clipped(tester);
    expect(clipped, isEmpty, reason: clipped.join('\n'));
  });

  testWidgets('on a smaller screen the columns are laid as on the Galaxy '
      'Tab and made smaller, no line cut', (tester) async {
    await _openAtItsLongest(tester, const Size(1000, 700));

    expect(tester.takeException(), isNull, reason: 'a column ran past');
    final body = _body(tester);
    expect(body.child!.size.width, 1579);
    expect(body.size.width, lessThan(1579));

    final clipped = _clipped(tester);
    expect(clipped, isEmpty, reason: clipped.join('\n'));
  });
}

final _window = find.byKey(const ValueKey<String>('debug-window'));

RenderFittedBox _body(WidgetTester tester) =>
    tester.renderObject<RenderFittedBox>(
      find.byKey(const ValueKey<String>('debug-window-body')),
    );

/// The window open on a screen of [size], with the stages at their
/// longest: more places than are shown, each with the widest figures a
/// frame is likely to say.
Future<void> _openAtItsLongest(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    // No theme: the window sets its own face (DebugType), whatever the
    // app's theme says.
    const MaterialApp(home: DebugWindowHost(child: SizedBox())),
  );
  MeasurementMode.debugWindow.value = true;
  await tester.pump();

  GpuPlaceTook place(int at) => (
    gpu: at.isEven,
    place: 'packages/gpu_engine/rust/src/kernels/composite/a_place_$at.rs:'
        '${1000 + at}',
    times: 125,
    micros: 123456 + at,
    longest: 98765,
    groups: 123456,
  );
  EngineStages.wentUp((draw: 12345, finish: 234567, show: 3456, went: null), [
    for (var at = 0; at < EngineStages.placesShown + 4; at += 1) place(at),
  ]);
  FrameStats.debugFeed([
    for (var at = 0; at < 120; at += 1)
      FrameTiming(
        vsyncStart: at * 16000,
        buildStart: at * 16000 + 1000,
        buildFinish: at * 16000 + 45000,
        rasterStart: at * 16000 + 46000,
        rasterFinish: at * 16000 + 123000,
        rasterFinishWallTime: at * 16000 + 123000,
        layerCacheCount: 12,
        layerCacheBytes: 123 << 20,
        pictureCacheCount: 34,
        pictureCacheBytes: 456 << 20,
      ),
  ]);
  FrameStats.publish();
  await tester.pump();
  expect(_window, findsOneWidget);
}

/// The window's lines laid to one row and wider than it — a line that
/// wraps is not cut.
List<String> _clipped(WidgetTester tester) => [
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: _window, matching: find.anyRichText()),
  ))
    if (!(paragraph.softWrap && paragraph.maxLines != 1) &&
        paragraph.getMaxIntrinsicWidth(double.infinity) >
            paragraph.size.width + 0.5)
      '${paragraph.text.toPlainText()} '
          '(${paragraph.getMaxIntrinsicWidth(double.infinity).round()} in '
          '${paragraph.size.width.round()})',
];
