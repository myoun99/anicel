// SEAM PROBE — does drawing a picture as TILES differ from drawing it as
// ONE IMAGE, under the display filter law, on THIS engine?
//
//   flutter run -d windows --release -t tool/probe/seam_probe_main.dart \
//     --dart-define=SEAM_OUT=<dir> \
//     [--dart-define=SEAM_MODE=seams|compare|policy|cost] \
//     [--dart-define=SEAM_STAY=1]
//
// Writes `report.txt` and PNGs (reference / tiled / diff) into SEAM_OUT and
// exits; with SEAM_STAY=1 it stays open showing the same pairs on screen.
//
// It runs in the REAL app process so the answer is the renderer the app
// ships with (Impeller since 3.47) — `flutter test` runs on flutter_tester
// and would answer for a renderer nobody ships. The paint settings are the
// product's own laws, imported from `display_resample.dart`; the tile paint
// mirrors `_tileImagePaint` (`isAntiAlias = false`); what is NEW here is
// only the shapes being measured (filtered tiles, padded tiles, pyramid
// levels), because those are the proposal, not the product.
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply. Every configuration is compared against a WHOLE image
// of the SAME content at the SAME scale — that isolates the tile edges.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:anicel/src/services/straight_rgba_image.dart'
    show uploadRawRgba;
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart'
    show samplingPhaseFor;

/// ≥100%: the product never draws at an arbitrary phase — the render snap
/// puts the translation at `samplingPhaseFor(scale)`, so those are the
/// phases that decide the absolute rule. Phase 0 is kept beside it as the
/// control (it is the product's phase at every whole zoom).
const List<double> _magnifyScales = [1.0, 1.1, 1.25, 1.37, 1.5, 2.0, 2.5, 3.0];

const _outDir = String.fromEnvironment('SEAM_OUT', defaultValue: '');
const _stay = bool.fromEnvironment('SEAM_STAY', defaultValue: false);

/// `seams` (default) measures tiles-vs-whole; `compare` renders line art
/// the way the product does TODAY (canvas-resolution + bilinear under the
/// cap; nearest-minified tiles past it) beside the way the unified plan
/// would (a pyramid level + one bilinear blit), across three one-pixel
/// pans so shimmer is visible, and writes one magnified gallery per zoom.
const _mode = String.fromEnvironment('SEAM_MODE', defaultValue: 'seams');
const List<double> _compareZooms = [0.75, 0.5, 0.33, 0.25, 0.12, 0.09];

const int _srcW = 640;
const int _srcH = 512;
const int _tile = 128;
const List<double> _scales = [1.0, 1.37, 2.0, 0.75, 0.63, 0.5, 0.42, 0.25, 0.09];
const List<double> _phases = [0.0, 0.42, 0.5];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _SeamProbeApp());
}

class _SeamProbeApp extends StatefulWidget {
  const _SeamProbeApp();

  @override
  State<_SeamProbeApp> createState() => _SeamProbeAppState();
}

class _SeamProbeAppState extends State<_SeamProbeApp> {
  final List<_Shown> _shown = [];
  String _status = 'measuring…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    final out = Directory(_outDir.isEmpty ? 'seam_probe_out' : _outDir);
    await out.create(recursive: true);
    final report = StringBuffer();
    try {
      final probe = _SeamProbe(out, report, _shown);
      if (_mode == 'compare') {
        await probe.runCompare();
      } else if (_mode == 'policy') {
        await probe.runPolicy();
      } else if (_mode == 'cost') {
        await probe.runCost();
      } else {
        await probe.runAll();
      }
      report.writeln('DONE');
    } on Object catch (e, st) {
      report.writeln('FAILED: $e\n$st');
    }
    await File('${out.path}/report.txt').writeAsString(report.toString());
    if (!_stay) {
      exit(0);
    }
    setState(() => _status = 'done — ${out.path}');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('seam probe: $_status')),
        body: ListView.builder(
          itemCount: _shown.length,
          itemBuilder: (_, i) {
            final s = _shown[i];
            Widget img(Uint8List b) => Image.memory(
              b,
              filterQuality: FilterQuality.none,
              scale: 0.25,
            );
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label),
                  Row(children: [img(s.ref), img(s.tiled), img(s.diff)]),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Shown {
  _Shown(this.label, this.ref, this.tiled, this.diff);
  final String label;
  final Uint8List ref;
  final Uint8List tiled;
  final Uint8List diff;
}

class _Rgba {
  _Rgba(this.w, this.h, this.bytes);
  final int w;
  final int h;
  final Uint8List bytes;
}

class _SeamProbe {
  _SeamProbe(this.out, this.report, this.shown);
  final Directory out;
  final StringBuffer report;
  final List<_Shown> shown;

  late final ui.Image _source;
  final List<ui.Image> _levels = [];

  Future<void> runAll() async {
    report.writeln('seam probe — source ${_srcW}x$_srcH tile $_tile');
    _source = await _drawSource();
    _levels.add(_source);
    for (var k = 1; k <= 4; k++) {
      _levels.add(await _halve(_levels[k - 1]));
    }
    // ≥100% at the product's own phases, both tile primitives.
    for (final s in _magnifyScales) {
      final phases = {0.0, samplingPhaseFor(s)};
      for (final ph in phases) {
        await _measureMagnify(s, ph);
      }
    }
    for (final s in _scales) {
      for (final ph in _phases) {
        await _measureScale(s, ph);
      }
    }
    await Future.wait(_pending);
  }

  Future<void> _measureMagnify(double s, double ph) async {
    // `s` IS the device scale here (zoom × ratio), so the ratio is 1.
    final f = filterQualityForDisplayScale(displayScaleOf(s, 1));
    final tag = 'MAG s=${s.toStringAsFixed(2)} ph=${ph.toStringAsFixed(4)}';
    report.writeln('\n== $tag  filter=${f.name}');
    final a0 = await _renderWhole(_source, s, ph, f, f != FilterQuality.none);
    final t0 = await _renderTiles(_source, s, ph, f, false, 0);
    _compare('$tag L0 tiles(drawImage) vs whole', a0, t0, s, 0, ph,
        png: 'MAG_drawImage');
    final r0 = await _renderTiles(_source, s, ph, f, false, 0, useRect: true);
    _compare('$tag L0 tiles(drawImageRect) vs whole', a0, r0, s, 0, ph,
        png: 'MAG_drawImageRect');
  }

  // ---------------------------------------------------------------- source
  Future<ui.Image> _drawSource() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final w = _srcW.toDouble();
    final h = _srcH.toDouble();
    final crisp = Paint()..isAntiAlias = false;
    // Fine lines at spacings that never coincide with tile edges.
    crisp.color = const Color(0xFF000000);
    for (var x = 5.0; x < w; x += 37) {
      c.drawRect(Rect.fromLTWH(x, 0, 1, h), crisp);
    }
    for (var y = 7.0; y < h; y += 41) {
      c.drawRect(Rect.fromLTWH(0, y, w, 1), crisp);
    }
    // A hard opaque edge EXACTLY on a tile boundary (x = 256), and one a
    // pixel off it (y = 257): the seam-sensitive placements.
    crisp.color = const Color(0xFF1040C0);
    c.drawRect(const Rect.fromLTWH(256, 40, 90, 120), crisp);
    crisp.color = const Color(0xFFC04010);
    c.drawRect(const Rect.fromLTWH(60, 257, 150, 70), crisp);
    // Semi-transparent ink over transparent ground — premultiplied
    // filtering shows at these edges.
    crisp.color = const Color(0x99D01010);
    c.drawCircle(const Offset(420, 300), 90, crisp);
    // A gradient bar and a 1px checker.
    c.drawRect(
      const Rect.fromLTWH(30, 400, 580, 40),
      Paint()
        ..isAntiAlias = false
        ..shader = ui.Gradient.linear(
          const Offset(30, 0),
          const Offset(610, 0),
          const [Color(0xFF000000), Color(0xFFFFFFFF)],
        ),
    );
    crisp.color = const Color(0xFF000000);
    for (var y = 460; y < 500; y++) {
      for (var x = 380; x < 620; x++) {
        if ((x + y).isEven) {
          c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), crisp);
        }
      }
    }
    // A thin diagonal.
    c.drawLine(
      const Offset(20, 480),
      const Offset(620, 20),
      Paint()
        ..isAntiAlias = false
        ..strokeWidth = 1
        ..color = const Color(0xFF008040),
    );
    final pic = rec.endRecording();
    try {
      return await pic.toImage(_srcW, _srcH);
    } finally {
      pic.dispose();
    }
  }

  /// One exact 2× reduction with the display filter: at exactly 0.5 a
  /// bilinear sample sits on the centre of each 2×2 block, which is a box
  /// average — the pyramid step a real implementation would take on the
  /// GPU.
  Future<ui.Image> _halve(ui.Image src) async {
    final w = math.max(1, src.width ~/ 2);
    final h = math.max(1, src.height ~/ 2);
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.low
        ..isAntiAlias = false,
    );
    final pic = rec.endRecording();
    try {
      return await pic.toImage(w, h);
    } finally {
      pic.dispose();
    }
  }

  /// A tile cut from [src] at 1:1 nearest — a byte copy, plus [pad]
  /// texels of neighbours on every side (transparent past the picture).
  Future<ui.Image> _cut(ui.Image src, int tx, int ty, int pad) async {
    final size = _tile + 2 * pad;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.translate(-(tx - pad).toDouble(), -(ty - pad).toDouble());
    c.drawImage(
      src,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
    final pic = rec.endRecording();
    try {
      return await pic.toImage(size, size);
    } finally {
      pic.dispose();
    }
  }

  // ------------------------------------------------------------ renderers
  int _outSide(int srcSide, double scale, double phase) =>
      (srcSide * scale + phase).ceil() + 1;

  Future<_Rgba> _renderWhole(
    ui.Image img,
    double scale,
    double phase,
    FilterQuality f,
    bool aa,
  ) async {
    final ow = _outSide(img.width, scale, phase);
    final oh = _outSide(img.height, scale, phase);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.translate(phase, phase);
    c.scale(scale);
    // The product's buffer blit: drawImageRect of the whole image.
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Paint()
        ..filterQuality = f
        ..isAntiAlias = aa,
    );
    return _readback(rec, ow, oh);
  }

  Future<_Rgba> _renderTiles(
    ui.Image img,
    double scale,
    double phase,
    FilterQuality f,
    bool aa,
    int pad, {
    bool useRect = false,
  }) async {
    final ow = _outSide(img.width, scale, phase);
    final oh = _outSide(img.height, scale, phase);
    final tiles = <ui.Image>[];
    try {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.translate(phase, phase);
      c.scale(scale);
      final paint = Paint()
        ..filterQuality = f
        ..isAntiAlias = aa;
      for (var ty = 0; ty < img.height; ty += _tile) {
        for (var tx = 0; tx < img.width; tx += _tile) {
          final t = await _cut(img, tx, ty, pad);
          tiles.add(t);
          if (pad == 0 && useRect) {
            // The buffer's primitive, applied per tile.
            c.drawImageRect(
              t,
              Rect.fromLTWH(0, 0, _tile.toDouble(), _tile.toDouble()),
              Rect.fromLTWH(
                tx.toDouble(),
                ty.toDouble(),
                _tile.toDouble(),
                _tile.toDouble(),
              ),
              paint,
            );
          } else if (pad == 0) {
            // The product's tile paint: drawImage at the tile origin.
            c.drawImage(t, Offset(tx.toDouble(), ty.toDouble()), paint);
          } else {
            // A padded tile: the SAME on-screen rect, sourced from the
            // inner window so the filter can reach the neighbours' texels.
            c.drawImageRect(
              t,
              Rect.fromLTWH(
                pad.toDouble(),
                pad.toDouble(),
                _tile.toDouble(),
                _tile.toDouble(),
              ),
              Rect.fromLTWH(
                tx.toDouble(),
                ty.toDouble(),
                _tile.toDouble(),
                _tile.toDouble(),
              ),
              paint,
            );
          }
        }
      }
      return await _readback(rec, ow, oh);
    } finally {
      for (final t in tiles) {
        t.dispose();
      }
    }
  }

  Future<_Rgba> _readback(ui.PictureRecorder rec, int w, int h) async {
    final pic = rec.endRecording();
    ui.Image? img;
    try {
      img = await pic.toImage(w, h);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        throw StateError('toByteData returned null');
      }
      return _Rgba(w, h, bd.buffer.asUint8List());
    } finally {
      pic.dispose();
      img?.dispose();
    }
  }

  // ------------------------------------------------------------ measuring
  Future<void> _measureScale(double s, double ph) async {
    final f = filterQualityForDisplayScale(displayScaleOf(s, 1));
    // The buffer edge's anti-alias law for an axis-aligned view.
    final bufferAa = f != FilterQuality.none;
    final tag = 's=${s.toStringAsFixed(2)} ph=${ph.toStringAsFixed(2)}';
    report.writeln('\n== $tag  filter=${f.name}');

    // Level 0 — the content as stored.
    final a0 = await _renderWhole(_source, s, ph, f, bufferAa);
    final t0 = await _renderTiles(_source, s, ph, f, false, 0);
    _compare('$tag L0 tiles(${f.name},aa0) vs whole', a0, t0, s, 0, ph,
        png: 'L0_tiles');
    if (s < 1) {
      final t0aa = await _renderTiles(_source, s, ph, f, true, 0);
      _compare('$tag L0 tiles(${f.name},aa1) vs whole', a0, t0aa, s, 0, ph,
          png: 'L0_tiles_aa');
      for (final pad in [1, 2]) {
        final p = await _renderTiles(_source, s, ph, f, false, pad);
        _compare('$tag L0 padded$pad(${f.name},aa0) vs whole', a0, p, s, 0, ph,
            png: 'L0_pad$pad');
      }
      // Pyramid: the level whose residual scale lands in (0.5, 1].
      var k = 0;
      var r = s;
      while (r <= 0.5 && k < _levels.length - 1) {
        k++;
        r = s * math.pow(2, k);
      }
      if (k > 0) {
        final lv = _levels[k];
        final rf = filterQualityForDisplayScale(displayScaleOf(r, 1));
        final ak = await _renderWhole(lv, r, ph, rf, rf != FilterQuality.none);
        final tk = await _renderTiles(lv, r, ph, rf, false, 0);
        _compare(
          '$tag L$k(r=${r.toStringAsFixed(2)}) tiles(${rf.name},aa0) vs whole',
          ak, tk, r, k, ph, png: 'L${k}_tiles',
        );
        final pk = await _renderTiles(lv, r, ph, rf, false, 1);
        _compare(
          '$tag L$k(r=${r.toStringAsFixed(2)}) padded1(${rf.name},aa0) vs whole',
          ak, pk, r, k, ph, png: 'L${k}_pad1',
        );
        // How far the pyramid's look is from the canvas-resolution look —
        // allowed below 100%, but worth a number.
        _compare('$tag L$k whole vs L0 whole (look)', a0, ak, r, k, ph);
      }
    }
  }

  void _compare(
    String label,
    _Rgba ref,
    _Rgba got,
    double scale,
    int level,
    double phase, {
    String? png,
  }) {
    final w = math.min(ref.w, got.w);
    final h = math.min(ref.h, got.h);
    var diffCount = 0;
    var maxDelta = 0;
    var boundaryDiff = 0;
    var boundaryAll = 0;
    var sumBoundary = 0;
    var sumInterior = 0;
    var interiorDiff = 0;
    final diffPng = Uint8List(w * h * 4);
    // Tile boundaries at this level project to phase + j·tile·scale.
    final boundaries = <double>[];
    for (var j = 1; j * _tile < (level == 0 ? _srcW : _srcW >> level); j++) {
      boundaries.add(phase + j * _tile * scale);
    }
    final boundariesY = <double>[];
    for (var j = 1; j * _tile < (level == 0 ? _srcH : _srcH >> level); j++) {
      boundariesY.add(phase + j * _tile * scale);
    }
    bool near(double v, List<double> bs) {
      for (final b in bs) {
        if ((v - b).abs() <= 1.5) {
          return true;
        }
      }
      return false;
    }

    for (var y = 0; y < h; y++) {
      final nearY = near(y + 0.5, boundariesY);
      for (var x = 0; x < w; x++) {
        final onBoundary = nearY || near(x + 0.5, boundaries);
        if (onBoundary) {
          boundaryAll++;
        }
        final ri = (y * ref.w + x) * 4;
        final gi = (y * got.w + x) * 4;
        var d = 0;
        for (var ch = 0; ch < 4; ch++) {
          final dd = (ref.bytes[ri + ch] - got.bytes[gi + ch]).abs();
          if (dd > d) {
            d = dd;
          }
        }
        // Visual: reference composited over white, differences in red.
        final o = (y * w + x) * 4;
        final a = ref.bytes[ri + 3] / 255.0;
        diffPng[o] = (ref.bytes[ri] * a + 255 * (1 - a)).round();
        diffPng[o + 1] = (ref.bytes[ri + 1] * a + 255 * (1 - a)).round();
        diffPng[o + 2] = (ref.bytes[ri + 2] * a + 255 * (1 - a)).round();
        diffPng[o + 3] = 255;
        if (d > 0) {
          diffCount++;
          if (d > maxDelta) {
            maxDelta = d;
          }
          if (onBoundary) {
            boundaryDiff++;
            sumBoundary += d;
          } else {
            interiorDiff++;
            sumInterior += d;
          }
          final v = math.min(255, 96 + d * 8);
          diffPng[o] = v;
          diffPng[o + 1] = 0;
          diffPng[o + 2] = 0;
        }
      }
    }
    final total = w * h;
    final baseFrac = boundaryAll / total;
    final diffFrac = diffCount == 0 ? 0.0 : boundaryDiff / diffCount;
    final ratio = baseFrac == 0 ? 0.0 : diffFrac / baseFrac;
    final meanB = boundaryDiff == 0 ? 0.0 : sumBoundary / boundaryDiff;
    final meanI = interiorDiff == 0 ? 0.0 : sumInterior / interiorDiff;
    report.writeln(
      '$label: diff=$diffCount/$total max=$maxDelta '
      'onBoundary=${(diffFrac * 100).toStringAsFixed(1)}% '
      '(base ${(baseFrac * 100).toStringAsFixed(1)}%, x${ratio.toStringAsFixed(1)}) '
      'meanΔ boundary=${meanB.toStringAsFixed(1)} interior=${meanI.toStringAsFixed(1)}',
    );
    if (png != null && (diffCount > 0 || phase == 0.0)) {
      _pending.add(_savePngs(label, png, ref, got, _Rgba(w, h, diffPng)));
    }
  }

  /// PNG writes run beside the measuring; the run waits for them before
  /// it exits, or the last files would be cut off mid-write.
  final List<Future<void>> _pending = [];

  Future<void> _savePngs(
    String label, String stem, _Rgba ref, _Rgba got, _Rgba diff,
  ) async {
    final safe = label
        .replaceAll(RegExp('[^A-Za-z0-9.=]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    final r = await _png(ref);
    final g = await _png(got);
    final d = await _png(diff);
    if (r == null || g == null || d == null) {
      return;
    }
    await File('${out.path}/${safe}_${stem}_ref.png').writeAsBytes(r);
    await File('${out.path}/${safe}_${stem}_tiled.png').writeAsBytes(g);
    await File('${out.path}/${safe}_${stem}_diff.png').writeAsBytes(d);
    shown.add(_Shown(label, r, g, d));
  }

  /// The repo's one awaitable upload, as the product uses it — a decode
  /// that never completes is its problem to time out, not a second copy's.
  Future<ui.Image?> _imageFrom(_Rgba p) => uploadRawRgba(
    p.bytes,
    width: p.w,
    height: p.h,
  ).then<ui.Image?>((image) => image).timeout(
    const Duration(seconds: 5),
    onTimeout: () => null,
  );

  Future<Uint8List?> _png(_Rgba p) async {
    final img = await _imageFrom(p);
    if (img == null) {
      return null;
    }
    try {
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }

  // ============================================================ compare
  Future<void> runCompare() async {
    report.writeln('compare — line art ${_srcW}x$_srcH, tile $_tile');
    report.writeln(
      'rows: NOW-A canvas-res + bilinear (route A, under the cap) | '
      'NOW-B tiles nearest-minified (route B, past the cap) | '
      'PLAN-1 level with residual in (0.5,1] + one bilinear blit | '
      'PLAN-2 level with residual in [0.71,1.41) + one bilinear blit. '
      'columns: pan 0 / +1 / +2 device px. '
      'shimmer = pixels that change between pan 0 and pan 1 after shifting '
      'back by one pixel (|delta| > 16), as a share of inked pixels.',
    );
    _source = await _drawLineArt();
    _levels
      ..clear()
      ..add(_source);
    for (var k = 1; k <= 4; k++) {
      _levels.add(await _halve(_levels[k - 1]));
    }
    // The artwork at 1:1, so the reader knows what is being reduced.
    final ref = await _renderWhole(_source, 1, 0, FilterQuality.none, false);
    _pending.add(_saveOne('compare_z=1.00_reference', ref));
    for (final z in _compareZooms) {
      await _compareZoom(z);
    }
    await Future.wait(_pending);
  }

  Future<void> _compareZoom(double z) async {
    final variants = <String, List<_Rgba>>{};
    Future<List<_Rgba>> frames(Future<_Rgba> Function(double dx) one) async =>
        [for (final dx in [0.0, 1.0, 2.0]) await one(dx)];

    variants['NOW-A canvas-res bilinear'] = await frames(
      (dx) => _renderWhole(_source, z, dx, FilterQuality.low, true),
    );
    variants['NOW-B tiles nearest (past the cap)'] = await frames(
      (dx) => _renderTiles(_source, z, dx, FilterQuality.none, false, 0),
    );
    // PLAN-1: residual in (0.5, 1].
    var k1 = 0;
    var r1 = z;
    while (r1 <= 0.5 && k1 < _levels.length - 1) {
      k1++;
      r1 = z * math.pow(2, k1);
    }
    // PLAN-2: residual in [0.71, 1.41).
    final k2 = math.min(
      _levels.length - 1,
      math.max(0, (-math.log(z) / math.ln2).round()),
    );
    final r2 = z * math.pow(2, k2);
    variants['PLAN-1 L$k1 r=${r1.toStringAsFixed(2)} bilinear'] = await frames(
      (dx) => _renderWhole(
        _levels[k1], r1, dx, filterQualityForDisplayScale(r1), true,
      ),
    );
    variants['PLAN-2 L$k2 r=${r2.toStringAsFixed(2)} bilinear'] = await frames(
      (dx) => _renderWhole(_levels[k2], r2, dx, FilterQuality.low, true),
    );

    final tag = 'z=${z.toStringAsFixed(2)}';
    report.writeln('\n== $tag');
    for (final e in variants.entries) {
      final sh = _shimmer(e.value[0], e.value[1]);
      report.writeln(
        '$tag ${e.key}: shimmer=${sh.changed}/${sh.inked} '
        '(${(100 * sh.changed / math.max(1, sh.inked)).toStringAsFixed(1)}%)',
      );
    }
    _pending.add(_saveGallery('compare_$tag', z, variants));
  }

  // ============================================================= policy
  /// Level policy 1 (residual in (0.5,1], always a slight downscale) against
  /// policy 2 (residual in [0.71,1.41), nearest level, upscaled up to 1.41×
  /// half the time). Zooms chosen so the two DISAGREE on the level; the
  /// sharpness figure is the mean luminance gradient over white — lower is
  /// softer. Buffer px is the level render's own size, i.e. what the
  /// display buffer would be for this picture.
  Future<void> runPolicy() async {
    report.writeln('policy — line art ${_srcW}x$_srcH');
    report.writeln(
      'columns: NOW-A canvas-res bilinear | PLAN-1 (0.5,1] | PLAN-2 [0.71,1.41). '
      'sharpness = mean |gradient| of luminance over white (0..255/px).',
    );
    _source = await _drawLineArt();
    _levels
      ..clear()
      ..add(_source);
    for (var k = 1; k <= 5; k++) {
      _levels.add(await _halve(_levels[k - 1]));
    }
    const zooms = [0.75, 0.62, 0.55, 0.5, 0.45, 0.38, 0.33, 0.28, 0.25, 0.19, 0.16, 0.14, 0.12, 0.09];
    for (final z in zooms) {
      var k1 = 0;
      var r1 = z;
      while (r1 <= 0.5 && k1 < _levels.length - 1) {
        k1++;
        r1 = z * math.pow(2, k1);
      }
      final k2 = math.min(
        _levels.length - 1,
        math.max(0, (-math.log(z) / math.ln2).round()),
      );
      final r2 = z * math.pow(2, k2);
      final a = await _renderWhole(_source, z, 0, FilterQuality.low, true);
      final p1 = await _renderWhole(_levels[k1], r1, 0, FilterQuality.low, true);
      final p2 = await _renderWhole(_levels[k2], r2, 0, FilterQuality.low, true);
      final sa = _sharpness(a);
      final s1 = _sharpness(p1);
      final s2 = _sharpness(p2);
      final same = k1 == k2 ? ' (same level)' : '';
      report.writeln(
        'z=${z.toStringAsFixed(2)}$same  NOW-A sharp=${sa.toStringAsFixed(2)}  '
        'PLAN-1 L$k1 r=${r1.toStringAsFixed(2)} sharp=${s1.toStringAsFixed(2)} '
        'bufferPx=x${(1 / (r1 * r1)).toStringAsFixed(2)}  '
        'PLAN-2 L$k2 r=${r2.toStringAsFixed(2)} sharp=${s2.toStringAsFixed(2)} '
        'bufferPx=x${(1 / (r2 * r2)).toStringAsFixed(2)}  '
        'PLAN-2/PLAN-1=${(s2 / math.max(0.001, s1)).toStringAsFixed(2)}',
      );
      _pending.add(_saveGallery(
        'policy_z=${z.toStringAsFixed(2)}',
        z,
        {
          'NOW-A | PLAN-1 L$k1 r=${r1.toStringAsFixed(2)} | '
                  'PLAN-2 L$k2 r=${r2.toStringAsFixed(2)}$same':
              [a, p1, p2],
        },
      ));
    }
    await Future.wait(_pending);
  }

  // =============================================================== cost
  /// The two costs the plan has not measured, at the engine-primitive level
  /// the product would pay them at:
  ///  1. composing a level buffer of a screen's size from 128px tiles at
  ///     1:1 (N drawImage + toImage), and PATCHING it the way
  ///     DisplayBufferCache does (blit the old buffer + redraw the dirty
  ///     rect's tiles + toImage of the whole buffer again);
  ///  2. refreshing the pyramid under a dirty rect: a Dart box downsample
  ///     of the dirty region through three levels (an upper bound — the
  ///     native lane would be several times faster) and the synchronous
  ///     upload of the resulting level tiles.
  /// Each figure is the median of 7 runs after one warm-up.
  Future<void> runCost() async {
    report.writeln('cost — engine primitives, median of 7 after warm-up');
    const screens = [(1920, 1080), (3840, 2160), (7680, 4320)];
    for (final (w, h) in screens) {
      final tiles = <ui.Image>[];
      final cols = (w + _tile - 1) ~/ _tile;
      final rows = (h + _tile - 1) ~/ _tile;
      // Tiles with content (a pattern), so the GPU actually samples.
      final src = await _patternImage(cols * _tile, rows * _tile);
      try {
        for (var ty = 0; ty < rows; ty++) {
          for (var tx = 0; tx < cols; tx++) {
            tiles.add(await _cut(src, tx * _tile, ty * _tile, 0));
          }
        }
        Future<ui.Image> compose() async {
          final rec = ui.PictureRecorder();
          final c = Canvas(rec);
          final paint = Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false;
          var i = 0;
          for (var ty = 0; ty < rows; ty++) {
            for (var tx = 0; tx < cols; tx++) {
              c.drawImage(
                tiles[i++],
                Offset((tx * _tile).toDouble(), (ty * _tile).toDouble()),
                paint,
              );
            }
          }
          final pic = rec.endRecording();
          try {
            return await pic.toImage(w, h);
          } finally {
            pic.dispose();
          }
        }

        final full = await _median(7, () async {
          final img = await compose();
          img.dispose();
        });
        // Patch: old buffer blit + the tiles under a dirty rect, then a
        // whole new buffer — the shape of DisplayBufferCache.patchBaseFor.
        final base = await compose();
        try {
          for (final dirty in [256, 512, 1024]) {
            final ms = await _median(7, () async {
              final rec = ui.PictureRecorder();
              final c = Canvas(rec);
              final paint = Paint()
                ..filterQuality = FilterQuality.none
                ..isAntiAlias = false;
              c.drawImage(base, Offset.zero, paint);
              c.save();
              c.clipRect(Rect.fromLTWH(200, 200, dirty.toDouble(), dirty.toDouble()));
              const t0 = 200 ~/ _tile;
              final t1 = (200 + dirty + _tile - 1) ~/ _tile;
              for (var ty = t0; ty < math.min(rows, t1); ty++) {
                for (var tx = t0; tx < math.min(cols, t1); tx++) {
                  c.drawImage(
                    tiles[ty * cols + tx],
                    Offset((tx * _tile).toDouble(), (ty * _tile).toDouble()),
                    paint,
                  );
                }
              }
              c.restore();
              final pic = rec.endRecording();
              try {
                final img = await pic.toImage(w, h);
                img.dispose();
              } finally {
                pic.dispose();
              }
            });
            report.writeln(
              'buffer ${w}x$h (${cols * rows} tiles): full compose '
              '${full.toStringAsFixed(1)} ms · patch dirty ${dirty}px '
              '${ms.toStringAsFixed(1)} ms',
            );
          }
        } finally {
          base.dispose();
        }
      } finally {
        src.dispose();
        for (final t in tiles) {
          t.dispose();
        }
      }
    }
    // 2. Pyramid refresh under a dirty rect: box downsample in Dart, then
    // the synchronous upload of the level tiles (Impeller only).
    for (final dirty in [256, 512, 1024]) {
      final px = Uint8List(dirty * dirty * 4);
      for (var i = 0; i < px.length; i++) {
        px[i] = (i * 7) & 0xFF;
      }
      final down = await _median(7, () async {
        var cur = px;
        var side = dirty;
        for (var k = 0; k < 3 && side >= 2; k++) {
          cur = _boxHalve(cur, side);
          side ~/= 2;
        }
      });
      final l1 = _boxHalve(px, dirty);
      final l1Side = dirty ~/ 2;
      final l1Tiles = (l1Side + _tile - 1) ~/ _tile;
      // One 128px tile's worth of level-1 pixels, uploaded once per tile
      // the dirty rect touches at level 1 — the shape the cache would pay.
      final tilePx = Uint8List(_tile * _tile * 4)
        ..setRange(0, math.min(l1.length, _tile * _tile * 4), l1);
      final up = await _median(7, () async {
        for (var i = 0; i < l1Tiles * l1Tiles; i++) {
          final img = ui.decodeImageFromPixelsSync(
            tilePx, _tile, _tile, ui.PixelFormat.rgba8888,
          );
          img.dispose();
        }
      });
      report.writeln(
        'dirty ${dirty}px: box downsample x3 levels (Dart) '
        '${down.toStringAsFixed(2)} ms · sync upload ${l1Tiles * l1Tiles} '
        'level-1 tile(s) ${up.toStringAsFixed(2)} ms',
      );
    }
  }

  Uint8List _boxHalve(Uint8List src, int side) {
    final half = side ~/ 2;
    final out = Uint8List(half * half * 4);
    for (var y = 0; y < half; y++) {
      for (var x = 0; x < half; x++) {
        final o = (y * half + x) * 4;
        final i0 = ((y * 2) * side + x * 2) * 4;
        final i1 = i0 + 4;
        final i2 = i0 + side * 4;
        final i3 = i2 + 4;
        for (var ch = 0; ch < 4; ch++) {
          out[o + ch] = (src[i0 + ch] + src[i1 + ch] + src[i2 + ch] + src[i3 + ch] + 2) >> 2;
        }
      }
    }
    return out;
  }

  Future<double> _median(int runs, Future<void> Function() body) async {
    await body();
    final times = <double>[];
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      await body();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    times.sort();
    return times[times.length ~/ 2];
  }

  Future<ui.Image> _patternImage(int w, int h) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;
    for (var y = 0; y < h; y += 16) {
      p.color = Color(0xFF000000 | ((y * 37) & 0xFFFFFF));
      c.drawRect(Rect.fromLTWH(0, y.toDouble(), w.toDouble(), 8), p);
    }
    final pic = rec.endRecording();
    try {
      return await pic.toImage(w, h);
    } finally {
      pic.dispose();
    }
  }

  double _sharpness(_Rgba p) {
    double lum(int i) {
      final a = p.bytes[i + 3] / 255.0;
      final l = 0.299 * p.bytes[i] + 0.587 * p.bytes[i + 1] + 0.114 * p.bytes[i + 2];
      return l * a + 255 * (1 - a);
    }

    var sum = 0.0;
    var n = 0;
    for (var y = 0; y < p.h - 1; y++) {
      for (var x = 0; x < p.w - 1; x++) {
        final i = (y * p.w + x) * 4;
        final l = lum(i);
        sum += (lum(i + 4) - l).abs() + (lum(i + p.w * 4) - l).abs();
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Pixels that change between two frames one device pixel apart, once
  /// the second is shifted back — what the eye sees as shimmer on a pan.
  ({int changed, int inked}) _shimmer(_Rgba a, _Rgba b) {
    var changed = 0;
    var inked = 0;
    final w = math.min(a.w, b.w) - 1;
    final h = math.min(a.h, b.h) - 1;
    // The pan is diagonal — `_renderWhole` translates by (dx, dx) — so the
    // second frame is shifted back on BOTH axes. Sanity: at an exact 1:1
    // residual this must come out near zero (bilinear at 1:1 is identity).
    for (var y = 1; y < h; y++) {
      for (var x = 1; x < w; x++) {
        final ia = ((y - 1) * a.w + (x - 1)) * 4;
        final ib = (y * b.w + x) * 4;
        if (a.bytes[ia + 3] > 0 || b.bytes[ib + 3] > 0) {
          inked++;
        }
        var d = 0;
        for (var ch = 0; ch < 4; ch++) {
          final dd = (a.bytes[ia + ch] - b.bytes[ib + ch]).abs();
          if (dd > d) {
            d = dd;
          }
        }
        if (d > 16) {
          changed++;
        }
      }
    }
    return (changed: changed, inked: inked);
  }

  Future<void> _saveOne(String stem, _Rgba p) async {
    final png = await _png(p);
    if (png != null) {
      await File('${out.path}/$stem.png').writeAsBytes(png);
    }
  }

  /// One PNG per zoom: a row per variant, a column per pan frame, every
  /// frame magnified with NEAREST so its pixels can be seen, composited
  /// over white, with a label on the left.
  Future<void> _saveGallery(
    String stem,
    double z,
    Map<String, List<_Rgba>> variants,
  ) async {
    final m = math.max(1, math.min(8, (1 / z).round()));
    final cellW = variants.values.first.first.w * m;
    final cellH = variants.values.first.first.h * m;
    const label = 230.0;
    const gap = 12.0;
    final gw = (label + 3 * (cellW + gap)).ceil();
    final gh = (variants.length * (cellH + gap) + gap).ceil();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(
      Rect.fromLTWH(0, 0, gw.toDouble(), gh.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final images = <ui.Image>[];
    try {
      var row = 0;
      for (final e in variants.entries) {
        final top = gap + row * (cellH + gap);
        _label(c, e.key, Offset(8, top + 4), label - 16);
        for (var col = 0; col < e.value.length; col++) {
          final f = e.value[col];
          final img = await _imageFrom(f);
          if (img == null) {
            continue;
          }
          images.add(img);
          final left = label + col * (cellW + gap);
          c.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, f.w.toDouble(), f.h.toDouble()),
            Rect.fromLTWH(left, top, f.w * m.toDouble(), f.h * m.toDouble()),
            Paint()
              ..filterQuality = FilterQuality.none
              ..isAntiAlias = false,
          );
        }
        row++;
      }
      _label(c, 'zoom ${(z * 100).round()}%  ×$m  pan 0 / +1 / +2 px',
          Offset(8, gh - 14), gw - 16);
      final pic = rec.endRecording();
      ui.Image? gallery;
      try {
        gallery = await pic.toImage(gw, gh);
        final bd = await gallery.toByteData(format: ui.ImageByteFormat.png);
        if (bd != null) {
          await File('${out.path}/$stem.png')
              .writeAsBytes(bd.buffer.asUint8List());
        }
      } finally {
        pic.dispose();
        gallery?.dispose();
      }
    } finally {
      for (final i in images) {
        i.dispose();
      }
    }
  }

  void _label(Canvas c, String text, Offset at, double width) {
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 12, maxLines: 4),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFF202020)))
      ..addText(text);
    final p = pb.build()..layout(ui.ParagraphConstraints(width: width));
    c.drawParagraph(p, at);
  }

  /// Line art in the shapes brushwork actually has: thin anti-aliased
  /// curves, hatching, a fine grid, small glyph-like marks.
  Future<ui.Image> _drawLineArt() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..color = const Color(0xFF101010);
    // Concentric circles, 1px, 9px apart.
    for (var r = 10.0; r < 180; r += 9) {
      c.drawCircle(const Offset(200, 200), r, ink);
    }
    // Hatching at 30°, 1px every 3px.
    c.save();
    c.clipRect(const Rect.fromLTWH(400, 40, 220, 160));
    for (var i = -200.0; i < 500; i += 3) {
      c.drawLine(Offset(400 + i, 40), Offset(400 + i + 92, 200), ink);
    }
    c.restore();
    // A 2px stroke curve and a 1px one crossing it.
    final wide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true
      ..color = const Color(0xFF203070);
    final path = Path()
      ..moveTo(30, 460)
      ..cubicTo(180, 300, 320, 520, 470, 380)
      ..cubicTo(560, 300, 600, 460, 630, 420);
    c.drawPath(path, wide);
    final thin = Path()
      ..moveTo(40, 300)
      ..cubicTo(200, 500, 400, 240, 620, 500);
    c.drawPath(thin, ink);
    // Fine grid 1px every 16px.
    final crisp = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFF404040);
    for (var x = 420.0; x < 630; x += 16) {
      c.drawRect(Rect.fromLTWH(x, 260, 1, 120), crisp);
    }
    for (var y = 260.0; y < 380; y += 16) {
      c.drawRect(Rect.fromLTWH(420, y, 210, 1), crisp);
    }
    // Glyph-like marks: 2×6 bars with 1px gaps, rows.
    for (var row = 0; row < 6; row++) {
      for (var i = 0; i < 40; i++) {
        final x = 30.0 + i * 4 + (i % 7 == 0 ? 2 : 0);
        c.drawRect(Rect.fromLTWH(x, 30 + row * 10, 2, 6), crisp);
      }
    }
    // A filled shape with a hard edge and a soft one.
    c.drawRect(
      const Rect.fromLTWH(60, 120, 90, 60),
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFF9A3020),
    );
    c.drawCircle(
      const Offset(330, 120),
      40,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0x88208040),
    );
    final pic = rec.endRecording();
    try {
      return await pic.toImage(_srcW, _srcH);
    } finally {
      pic.dispose();
    }
  }
}
