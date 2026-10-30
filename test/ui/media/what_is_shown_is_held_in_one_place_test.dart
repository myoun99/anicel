import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/media/shown_rasters.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';

/// [ShownRasters] — the one holding of every picture drawn as large as it
/// is shown (the viewer's pages, the storyboard's panels, the sheets'
/// images; 유저 10-30 「붙잡는 곳 하나」). Its owners pin what they each
/// see of it; this pins what none of them can: a surface that is still
/// there when what it shows goes away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> picture() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawColor(const ui.Color(0xFF00FFFF), ui.BlendMode.src);
    return recorder.endRecording().toImage(2, 2);
  }

  ShownRasters<int, int> rastersOf(List<int> rebuilds) => ShownRasters(
    budget: ViewerRasterBudget(physicalMemoryBytes: null),
    wantedAt: (_) => null,
    lastUsed: (page) => page,
    rebuild: (change) {
      change();
      rebuilds.add(1);
    },
    // The surface stays: only what it shows is let go.
    mounted: () => true,
    report: (_) {},
  );

  test('a render still out when everything is let go lands nowhere — the '
      'surface that asked is still there, showing something else', () async {
    final rebuilds = <int>[];
    final rasters = rastersOf(rebuilds);
    final out = Completer<ui.Image>();
    rasters.ask(0, 1, () => out.future);

    rasters.clear();
    final late = await picture();
    out.complete(late);
    await pumpEventQueue();

    expect(rasters.imageOf(0), isNull, reason: 'not installed');
    expect(late.debugDisposed, isTrue, reason: 'and not leaked');
    expect(rebuilds, isEmpty);
    expect(rasters.rendering, isFalse);
  });

  test('a render still out when its source is turned away lands nowhere, '
      'and what is drawn stays', () async {
    final rasters = rastersOf([]);
    final first = await picture();
    rasters.ask(0, 1, () async => first);
    await pumpEventQueue();
    final out = Completer<ui.Image>();
    rasters.ask(0, 2, () => out.future);

    rasters.turnAway();
    final late = await picture();
    out.complete(late);
    await pumpEventQueue();

    expect(identical(rasters.imageOf(0), first), isTrue);
    expect(late.debugDisposed, isTrue);
    rasters.clear();
  });
}
