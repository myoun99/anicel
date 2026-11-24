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
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;

import '../../helpers/app_faces.dart';

/// 🔬The debug window on the Galaxy Tab's screen, 1579x986 logical
/// (🗣️관제 2026-11-24, card one-debug-window-shows-everything: 「갤탭 한
/// 화면에 잘림 없이, 자리 예약」): every line in the app's own face is as
/// wide as its column lets it be, and no column runs past the screen —
/// with every place of the engine's stages it shows told, the longest the
/// window says.
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
    tester.view
      ..physicalSize = const Size(1579, 986)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: AppTypography.bundledFamily,
          fontFamilyFallback: AppTypography.bundledFallback,
        ),
        home: const DebugWindowHost(child: SizedBox()),
      ),
    );
    MeasurementMode.debugWindow.value = true;
    await tester.pump();

    // The stages at their longest: more places than are shown, each with
    // the widest figures a frame is likely to say.
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

    expect(tester.takeException(), isNull, reason: 'a column ran past');
    final window = find.byKey(const ValueKey<String>('debug-window'));
    expect(window, findsOneWidget);

    final clipped = <String>[];
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: window, matching: find.byType(RichText)),
    )) {
      final wants = paragraph.getMaxIntrinsicWidth(double.infinity);
      if (wants > paragraph.size.width + 0.5) {
        clipped.add(
          '${paragraph.text.toPlainText()} '
          '(${wants.toStringAsFixed(0)} in '
          '${paragraph.size.width.toStringAsFixed(0)})',
        );
      }
    }
    expect(clipped, isEmpty, reason: clipped.join('\n'));
  });
}
