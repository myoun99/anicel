import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/debug/frame_stats.dart';
import 'package:anicel/src/ui/debug/frame_stats_readout.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/screen_check.dart';

void main() {
  test('says same where Flutter shows what the engine wrote, and both '
      'fingerprints where it does not', () {
    expect(
      ScreenCheck.verdict(shown: 0x0badf00d, written: 0x0badf00d),
      'same 0badf00d',
    );
    expect(
      ScreenCheck.verdict(shown: 0x12, written: 0x0badf00d),
      'differs  shown 00000012  written 0badf00d',
    );
  });

  test('probes two layouts, not one twice — the one a screen asks for '
      'first, the driver\'s own beside it', () {
    expect(ScreenCheck.probes, [
      (name: 'cpu', asTheDriverChooses: false),
      (name: 'driver', asTheDriverChooses: true),
    ]);
  });

  test('makes each probe\'s surface in the layout it names', () {
    for (final probe in ScreenCheck.probes) {
      final surface = ScreenCheck.surfaceOf(appGpuEngine, probe);
      addTearDown(surface.free);
      expect(surface.asTheDriverChooses, probe.asTheDriverChooses,
          reason: probe.name);
      expect((surface.width, surface.height),
          (ScreenCheck.side, ScreenCheck.side));
    }
  });

  test('says each probe — its name, what it found, and its buffer read '
      'back where the platform says one', () {
    expect(
      ScreenCheck.row([
        (name: 'cpu', found: 'same 0badf00d', laid: 'usage 0x102'),
        (
          name: 'driver',
          found: 'differs  shown 00000012  written 0badf00d',
          laid: '',
        ),
      ]),
      'cpu same 0badf00d  usage 0x102  ·  '
      'driver differs  shown 00000012  written 0badf00d',
    );
  });

  test('names a read of no texel for what it is — the import that failed '
      'says so nowhere else', () {
    expect(
      ScreenCheck.verdict(shown: 0x12, written: 0x0badf00d, blank: true),
      'nothing  Flutter drew none of it — its import failed, or it was '
      'never drawn  written 0badf00d',
    );
  });

  testWidgets('the check has its row and its probe\'s room before any check '
      'has run', (tester) async {
    MeasurementMode.frameStats.value = true;
    addTearDown(() => MeasurementMode.frameStats.value = false);
    addTearDown(ScreenCheck.debugForget);
    ScreenCheck.debugForget();
    FrameStats.debugFeed(<FrameTiming>[
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 1000,
        rasterStart: 1000,
        rasterFinish: 2000,
        rasterFinishWallTime: 2000,
      ),
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
    );
    FrameStats.publish();
    await tester.pump();

    expect(find.text(' check  —'), findsOneWidget);
    final dpr = tester.view.devicePixelRatio;
    expect(
      tester.getSize(find.byType(ScreenCheck)),
      Size.square(ScreenCheck.side / dpr),
      reason: 'its room is there whether or not a texture is shown in it',
    );
    expect(find.byType(Texture), findsNothing);
  });
}
