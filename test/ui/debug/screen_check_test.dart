import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('says both probes — the layout a screen asks for first, the '
      'driver\'s own beside it', () {
    expect(
      ScreenCheck.both(
        forTheCpuToo: 'same 0badf00d',
        driversOwn: 'differs  shown 00000012  written 0badf00d',
      ),
      'cpu same 0badf00d  ·  driver differs  shown 00000012  written 0badf00d',
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
