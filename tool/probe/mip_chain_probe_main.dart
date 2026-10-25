// MIP CHAIN PROBE — which pictures carry the engine's mip chain on THIS
// engine, and how far a surface's tiles drawn reduced stand from its one
// picture drawn reduced.
//
//   flutter run -d windows --release -t tool/probe/mip_chain_probe_main.dart \
//     --dart-define=MIP_OUT=<dir>
//
// Writes `report.txt` into MIP_OUT and exits. Measurement, not a feature.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/chained_picture.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';

const _outDir = String.fromEnvironment('MIP_OUT', defaultValue: '');
const side = 512;
const tileSize = 256;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final out = Directory(_outDir.isEmpty ? 'mip_probe_out' : _outDir);
    await out.create(recursive: true);
    final report = StringBuffer();
    try {
      await _measure(report);
      report.writeln('DONE');
    } on Object catch (e, st) {
      report.writeln('FAILED: $e\n$st');
    }
    await File('${out.path}/report.txt').writeAsString(report.toString());
    exit(0);
  }

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: Text('mip probe')));
}

List<int> inkAt(int x, int y) {
  final line =
      (x * 7 + y * 13) % 11 == 0 ||
      (x - y).abs() < 1 ||
      (x % 9 == 0 && y > 100 && y < 400) ||
      (y % 6 == 0 && x > 200 && x < 330) ||
      (x >= 254 && x <= 257 && y % 3 != 0) ||
      (y >= 254 && y <= 256 && x % 2 == 0);
  if (line) {
    return [20, 30, 40, 255];
  }
  final dx = x - 256.0;
  final dy = y - 256.0;
  final r = math.sqrt(dx * dx + dy * dy);
  if ((r - 120).abs() < 2) {
    return [200, 40, 40, ((2 - (r - 120).abs()) / 2 * 255).round()];
  }
  return [0, 0, 0, 0];
}

Future<Uint8List> bytesOf(void Function(ui.Canvas) paint, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

String diffOf(Uint8List a, Uint8List b, int w, int h, double s) {
  var n = 0;
  var over2 = 0;
  var over8 = 0;
  var max = 0;
  var onSeam = 0;
  final seam = tileSize * s;
  for (var y = 0; y < h; y += 1) {
    for (var x = 0; x < w; x += 1) {
      final i = (y * w + x) * 4;
      var d = 0;
      for (var c = 0; c < 3; c += 1) {
        d = math.max(d, (a[i + c] - b[i + c]).abs());
      }
      if (d > 0) {
        n += 1;
        if (d > 2) over2 += 1;
        if (d > 8) over8 += 1;
        if (d > max) max = d;
        if ((x + 0.5 - seam).abs() < 1.5 || (y + 0.5 - seam).abs() < 1.5) {
          onSeam += 1;
        }
      }
    }
  }
  return 'diff=$n >2=$over2 >8=$over8 max=$max onSeam=$onSeam of ${w * h}';
}

Future<void> _measure(StringBuffer report) async {
  final tiles = <TileCoord, BitmapTile>{};
  for (var ty = 0; ty < side ~/ tileSize; ty += 1) {
    for (var tx = 0; tx < side ~/ tileSize; tx += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var y = 0; y < tileSize; y += 1) {
        for (var x = 0; x < tileSize; x += 1) {
          final rgba = inkAt(tx * tileSize + x, ty * tileSize + y);
          pixels.setRange(
            (y * tileSize + x) * 4,
            (y * tileSize + x) * 4 + 4,
            rgba,
          );
        }
      }
      tiles[TileCoord(x: tx, y: ty)] = BitmapTile(
        size: tileSize,
        pixels: pixels,
      );
    }
  }
  final images = {
    for (final e in tiles.entries)
      e.key: BitmapTileImageCache.pictureOfTile(e.value),
  };
  final chained = {
    for (final e in images.entries) e.key: chainedPictureOf(e.value),
  };
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final e in images.entries) {
    canvas.drawImage(
      e.value,
      ui.Offset(e.key.x * tileSize * 1.0, e.key.y * tileSize * 1.0),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
  }
  final onePicture = recorder.endRecording();
  final one = await onePicture.toImage(side, side);
  final oneSync = onePicture.toImageSync(side, side);
  onePicture.dispose();

  Future<Uint8List> plain(ui.Image image, double s, ui.FilterQuality q, int w) =>
      bytesOf((c) {
        c.scale(s);
        c.drawImage(image, ui.Offset.zero, ui.Paint()..filterQuality = q);
      }, w, w);

  Future<Uint8List> perTile(
    Map<TileCoord, ui.Image> of,
    CanvasViewport viewport,
    int w,
  ) => bytesOf((c) {
    applyViewportTransform(c, viewport);
    for (final e in of.entries) {
      drawOnTheDisplay(
        c,
        e.value,
        const ui.Rect.fromLTWH(0, 0, tileSize * 1.0, tileSize * 1.0),
        ui.Rect.fromLTWH(
          e.key.x * tileSize * 1.0,
          e.key.y * tileSize * 1.0,
          tileSize * 1.0,
          tileSize * 1.0,
        ),
        viewport: viewport,
        devicePixelRatio: 1,
      );
    }
  }, w, w);

  for (final s in [0.75, 0.6, 0.5, 0.45, 0.33, 0.25, 0.2, 0.125]) {
    final w = (side * s).ceil();
    final viewport = CanvasViewport(zoom: s);
    final ofOne = await bytesOf((c) {
      applyViewportTransform(c, viewport);
      drawOnTheDisplay(
        c,
        one,
        const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
        const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
        viewport: viewport,
        devicePixelRatio: 1,
      );
    }, w, w);
    final ofSync = await bytesOf((c) {
      applyViewportTransform(c, viewport);
      drawOnTheDisplay(
        c,
        oneSync,
        const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
        const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
        viewport: viewport,
        devicePixelRatio: 1,
      );
    }, w, w);
    final ofTiles = await perTile(images, viewport, w);
    final ofChained = await perTile(chained, viewport, w);
    final tile = images.values.first;
    final chainedTile = chained.values.first;
    report
      ..writeln('s=$s fq=${filterQualityForDisplayScale(s)}')
      ..writeln('  sync picture    vs one: ${diffOf(ofSync, ofOne, w, w, s)}')
      ..writeln('  door tiles      vs one: ${diffOf(ofTiles, ofOne, w, w, s)}')
      ..writeln('  chained tiles   vs one: ${diffOf(ofChained, ofOne, w, w, s)}')
      ..writeln(
        '  door tile  medium vs low: ${diffOf(await plain(tile, s, ui.FilterQuality.medium, w), await plain(tile, s, ui.FilterQuality.low, w), w, w, 99)}',
      )
      ..writeln(
        '  chained    medium vs low: ${diffOf(await plain(chainedTile, s, ui.FilterQuality.medium, w), await plain(chainedTile, s, ui.FilterQuality.low, w), w, w, 99)}',
      )
      ..writeln(
        '  sync       medium vs low: ${diffOf(await plain(oneSync, s, ui.FilterQuality.medium, w), await plain(oneSync, s, ui.FilterQuality.low, w), w, w, 99)}',
      )
      ..writeln(
        '  one        medium vs low: ${diffOf(await plain(one, s, ui.FilterQuality.medium, w), await plain(one, s, ui.FilterQuality.low, w), w, w, 99)}',
      );
  }
}
