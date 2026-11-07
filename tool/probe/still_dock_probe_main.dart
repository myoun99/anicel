// STILL DOCK PROBE — the app itself, its still images off and on at one
// state (card dock-pixels-differ-between-runs-at-one-scroll-position-on-the-
// surface, Q2 b: 「원인을 재서 그림 가장자리를 라이브와 맞춘다」).
//
// The edge probe (`still_edge_probe_main.dart`) found the app's still path
// the same pixels as the live one round every widget it imitates — 🔬the
// Surface, 11-07 22:31 and 23:36: at most 2/255, nested regions and ticks
// included — while the dock parted by up to 25 (16:43). What the imitation
// left out is not guessed at here: this runs the APP — its own `main`, any
// project — and turns its images off and on while it stands still, so two
// screenshots of one state part only where an image does.
//
//   flutter build windows --release -t tool/probe/still_dock_probe_main.dart \
//     --dart-define=EDGE_OUT=<dir>
//   build\windows\x64\runner\Release\anicel.exe [<project file>]
//
// Drive it by writing one word into <EDGE_OUT>/want.txt:
//
//   image   the app as it ships: each region drawn from its image once still
//   live    every still region drawn live (`StillRaster.cachePays` off)
//
// It answers four times a second in <EDGE_OUT>/now.json: the phase it is in,
// how long the regions have stood as they are (`still`, seconds), and every
// region — its label, the nearest name above it, where it stands in device
// pixels from the magenta mark in the window's top-left corner, what the
// scene draws it from (its own image, the image of a region above it, or
// nothing — live) and why it last painted. In each phase, once `still` is a
// few seconds, take a screenshot at the screen's own resolution and keep the
// now.json beside it; then:
//
//   dart run tool/probe/still_edge_compare.dart <image.png> <live.png> \
//     <now.json of the image shot>
//
// `StaticRaster` is left as it ships: on Impeller it paints through already.
//
// It reads and turns the regions' test hooks (`@visibleForTesting`) — the
// only switch there is for their images, and the only record of what they
// took — so each such line says so to the analyzer.
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:anicel/main.dart' as app;
import 'package:anicel/src/ui/widgets/named.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

const _outDir = String.fromEnvironment('EDGE_OUT', defaultValue: '');

/// The mark the compare finds the window by: magenta, this many device
/// pixels a side, in the window's top-left corner.
const int _mark = 8;

Future<void> main(List<String> args) async {
  await app.main(args);
  if (_outDir.isEmpty) {
    return;
  }
  _Probe(Directory(_outDir)..createSync(recursive: true)).start();
}

final class _Probe {
  _Probe(this.out);

  final Directory out;

  final _markKey = GlobalKey();
  var _marked = false;
  var _phase = 'image';

  /// What the regions said at the last look, and since when.
  var _stood = '';
  var _since = DateTime.now();

  void start() =>
      Timer.periodic(const Duration(milliseconds: 250), (_) => _look());

  void _look() {
    // A frame at every look: a region shows the image it took from the
    // frame after, and an app nothing moves in asks for none — 🔬the main
    // PC, 11-07: every region had taken its image and still painted live,
    // three seconds on.
    WidgetsBinding.instance.scheduleFrame();
    if (!_marked) {
      _marked = _putMark();
    }
    final want = _wanted();
    if (want != null && want != _phase) {
      _turn(want);
    }
    final markAt = _markAt();
    if (markAt == null) {
      return;
    }
    final ratio = WidgetsBinding.instance.platformDispatcher.views.first
        .devicePixelRatio;
    final regions = _regions(markAt, ratio);
    final stood = jsonEncode([
      for (final region in regions)
        [region['from'], region['standDown'], region['captures']],
    ]);
    final now = DateTime.now();
    if (stood != _stood) {
      _stood = stood;
      _since = now;
    }
    _write({
      'phase': _phase,
      'still': now.difference(_since).inMilliseconds / 1000,
      'devicePixelRatio': ratio,
      'mark': _mark,
      'regions': regions,
    });
  }

  /// The word in want.txt, if it is one this probe knows.
  String? _wanted() {
    final file = File('${out.path}/want.txt');
    if (!file.existsSync()) {
      return null;
    }
    final word = file.readAsStringSync().trim();
    return word == 'image' || word == 'live' ? word : null;
  }

  void _turn(String phase) {
    _phase = phase;
    // ignore: invalid_use_of_visible_for_testing_member
    StillRaster.debugCachePaysOverride = phase == 'live' ? false : null;
    void repaint(RenderObject node) {
      node.markNeedsPaint();
      node.visitChildren(repaint);
    }

    RendererBinding.instance.renderViews.forEach(repaint);
  }

  /// Puts the mark over the app, in the first overlay that holds it all.
  bool _putMark() {
    OverlayState? overlay;
    void visit(Element element) {
      if (overlay != null) {
        return;
      }
      if (element is StatefulElement && element.state is OverlayState) {
        overlay = element.state as OverlayState;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final into = overlay;
    if (into == null) {
      return false;
    }
    final side =
        _mark /
        WidgetsBinding.instance.platformDispatcher.views.first
            .devicePixelRatio;
    into.insert(
      OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: SizedBox(
              key: _markKey,
              width: side,
              height: side,
              child: const ColoredBox(color: Color(0xFFFF00FF)),
            ),
          ),
        ),
      ),
    );
    return true;
  }

  Offset? _markAt() {
    final box = _markKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : null;
  }

  /// Every region on the screen, outermost first.
  List<Map<String, Object?>> _regions(Offset markAt, double ratio) {
    final out = <Map<String, Object?>>[];
    void visit(Element element, String? name) {
      final widget = element.widget;
      final named = widget is Named ? widget.name ?? name : name;
      final region = element.renderObject;
      if (widget is StillRaster &&
          region is RenderStillRaster &&
          region.attached &&
          region.hasSize) {
        final topLeft = (region.localToGlobal(Offset.zero) - markAt) * ratio;
        final size = region.size * ratio;
        out.add({
          'label': region.debugLabel,
          'name': named,
          'rect': [
            topLeft.dx.floor(),
            topLeft.dy.floor(),
            (topLeft.dx + size.width).ceil() - topLeft.dx.floor(),
            (topLeft.dy + size.height).ceil() - topLeft.dy.floor(),
          ],
          'from': _drawnFrom(region),
          'standDown': region.standDown.name,
          'bytes': region.rasterBytes,
          // ignore: invalid_use_of_visible_for_testing_member
          'captures': region.debugCaptureCount,
        });
      }
      element.visitChildren((child) => visit(child, named));
    }

    WidgetsBinding.instance.rootElement?.visitChildren(
      (child) => visit(child, null),
    );
    return out;
  }

  /// What the scene draws [region] from ([RenderStillRaster.debugDrawnFrom]):
  /// its own image, a region's above it, or nothing — null, live.
  String? _drawnFrom(RenderStillRaster region) =>
      // ignore: invalid_use_of_visible_for_testing_member
      switch (region.debugDrawnFrom) {
        null => null,
        final from when identical(from, region) => 'own',
        final from => 'above ${from.debugLabel}',
      };

  void _write(Map<String, Object?> now) {
    final path = '${out.path}/now.json';
    final next = File('$path.next')
      ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(now));
    try {
      next.renameSync(path);
    } on FileSystemException {
      File(path).writeAsStringSync(next.readAsStringSync());
    }
  }
}
