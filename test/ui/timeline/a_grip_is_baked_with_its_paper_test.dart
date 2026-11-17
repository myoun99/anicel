import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PictureRecorder;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' as rendering;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart'
    show blockEdgeGripRightAngle;
import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart'
    show TimelineGridScreenTile;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';
import 'package:anicel/src/ui/timeline/timeline_tile_raster_source.dart'
    show TimelineRowGrip;

import '../../helpers/a_shown_surface.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/tiles_laid.dart';
import '../../helpers/timeline_host.dart';
import 'tile_store_idle.dart';
import 'timeline_cell_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// 🗣️F-604 (유저 2026-11-16): 「밑의 블록의 오른쪽위 엣지 위에 블록 공간이
/// 보임 … 행 off로하면 또 이번엔 왼쪽아래 엣지가 밖으로 나간다거나. 타임라인
/// 줌 드래그할때 엣지랑 블록이랑 따로논다거나 … 진짜 근본/구조적으로해결」.
///
/// A grip is its paper's corner, inked: the row's tile bakes it with its
/// paper, by one coordinate and one rounding, and the chrome over it takes
/// its pointer and draws none. ↩️The chrome drew it in Flutter at the
/// block's exact place while the tile's paper stood on the tile's pixels —
/// a sliver of paper over it at 0.9, its foot past the paper's, and the two
/// apart through a zoom drag, which stretches the tile alone.
void main() {
  setUpAll(openAppGpuEngine);

  Layer rowOf(String id) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    mark: const LayerMark(process: LayerProcess.finish),
    frames: [
      for (var cel = 0; cel < 6; cel += 1)
        Frame(id: FrameId('$id-$cel'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (var cel = 0; cel < 6; cel += 1)
        cel * 3: TimelineExposure.drawing(FrameId('$id-$cel'), length: 3),
    },
  );

  Project film() => Project(
    id: const ProjectId('grips'),
    name: 'Grips',
    createdAt: DateTime.utc(2026, 11, 17),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 18,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [for (var row = 0; row < 3; row += 1) rowOf('r$row')],
          ),
        ],
      ),
    ],
  );

  Future<void> settle(WidgetTester tester) async {
    final store = TimelineGridTileStore.instance;
    for (var turn = 0; turn < 8; turn += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tileStoreIdle(store, tester: tester);
      await tester.pump();
    }
  }

  Future<EditorSessionManager> pumpAt(
    WidgetTester tester,
    double ratio,
    TimelineOrientation orientation,
  ) async {
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = inkEveryCel(EditorSessionManager(initialProject: film()));
    addTearDown(session.dispose);
    await pumpTimelineHostOn(
      tester,
      session,
      surface: const Size(900, 500),
      orientation: orientation,
    );
    await settle(tester);
    return session;
  }

  /// [tile]'s pixels as it is laid: one a device pixel, RGB, read at a
  /// point of its row's own (logical, row-local).
  int Function(Offset at) pixelsOf(TimelineGridScreenTile tile) {
    final picture = tile.picture.picture;
    final width = picture.width;
    final height = picture.height;
    final surface = shownSurfaceOf(width, height);
    addTearDown(surface.free);
    final lay = GpuGridLay(appGpuEngine);
    addTearDown(lay.free);
    final all = (0.0, 0.0, width.toDouble(), height.toDouble());
    lay.lay(surface, (0, 0, width, height), [
      (picture: picture, from: all, onto: all),
    ]);
    final rgba = surface.read();
    final scale = tile.from.width / tile.onto.width;
    return (at) {
      final x = (tile.from.left + (at.dx - tile.onto.left) * scale).floor();
      final y = (tile.from.top + (at.dy - tile.onto.top) * scale).floor();
      if (x < 0 || y < 0 || x >= width || y >= height) {
        return -1;
      }
      return _rgbAt(rgba, (y * width + x) * 4);
    };
  }

  for (final orientation in TimelineOrientation.values) {
    final (axis, prefix) = orientation == TimelineOrientation.horizontal
        ? (Axis.horizontal, 'timeline')
        : (Axis.vertical, 'xsheet');
    for (final ratio in const [0.9, 1.25]) {
      testWidgets('${axis.name} at $ratio: a row\'s tile bakes its grips '
          'with its paper — each in its corner, its edge on its paper\'s own '
          'line and coverage — and the chrome draws none', (tester) async {
        await pumpAt(tester, ratio, orientation);
        final painter = timelineRowCellsPainterFor(
          tester,
          'r1',
          prefix: prefix,
        );
        final size = tester.getSize(find.named('$prefix-row-cells-r1'));
        final laid = tilesLaidBy(
          () => painter.paint(Canvas(PictureRecorder()), size),
        );
        expect(laid, isNotEmpty, reason: '⛔premise: the row lays tiles');
        final tile = laid.first;
        final at = pixelsOf(tile);
        final scale = tile.from.width / tile.onto.width;
        expect(scale, moreOrLessEquals(ratio), reason: 'one a device pixel');

        final grips = [
          for (final grip in painter.gripsIn(0, 18))
            if (tile.onto.inflate(1e-6).contains(grip.box.topLeft) &&
                tile.onto.inflate(1e-6).contains(grip.box.bottomRight))
              grip,
        ];
        expect(grips.length, greaterThan(2), reason: 'the tile holds grips');

        double tileAcross(double logical) =>
            startAcross(axis, tile.from) +
            (logical - startAcross(axis, tile.onto)) * scale;
        double rowAcross(double pixel) =>
            startAcross(axis, tile.onto) +
            (pixel - startAcross(axis, tile.from)) / scale;
        double tileAlong(double logical) =>
            startAlong(axis, tile.from) +
            (logical - startAlong(axis, tile.onto)) * scale;
        double rowAlong(double pixel) =>
            startAlong(axis, tile.onto) +
            (pixel - startAlong(axis, tile.from)) / scale;
        final picture = tile.picture.picture;
        final pixelsAcross = axis == Axis.horizontal
            ? picture.height
            : picture.width;

        var fractional = 0;
        for (final grip in grips) {
          final corner = blockEdgeGripRightAngle(
            grip.box,
            edge: grip.edge,
            axis: axis,
          );
          final inward = Offset(
            corner.dx == grip.box.right ? -1 : 1,
            corner.dy == grip.box.bottom ? -1 : 1,
          );
          final towards = partAlong(axis, inward);
          final from = partAlong(axis, corner);
          // Its paper, two past it along.
          final clear = extentAlong(axis, grip.box.size) + 2;
          // In its corner, two device pixels inside the paper's circle on
          // its diagonal, is the grip's — its ink over its paper.
          final inCorner = _inCorner(corner, inward, grip.paperCorner, scale);
          final besideCorner = at(
            offsetAlong(
              axis,
              along: from + towards * clear,
              across: partAcross(axis, inCorner),
            ),
          );

          expect(
            at(inCorner),
            _isRgb(_over(besideCorner, grip.color, 1)),
            reason: '${grip.edge.name} grip at ${grip.box}: in its corner',
          );

          // Its edge across, where it is the paper's: the line that edge
          // crosses is covered by the grip as much as by the paper — the
          // same coordinate, the same rounding.
          final edge = tileAcross(partAcross(axis, corner));
          final line = edge.floor();
          if (edge == line) {
            continue;
          }
          final far = partAcross(axis, inward) < 0;
          final covered = far ? edge - line : line + 1 - edge;
          fractional += 1;
          final across = rowAcross(line + 0.5);
          Offset point(double along) => offsetAlong(
            axis,
            along: along,
            across: across,
          );
          // The grip between its round end and its tip, where its leg is
          // straight; its paper past the grip.
          final length = extentAlong(axis, grip.box.size);
          final roundEnds = tileAlong(from + towards * grip.paperCorner);
          final tip = tileAlong(from + towards * length);
          expect(
            (tip - roundEnds).abs(),
            greaterThanOrEqualTo(1.5),
            reason: '⛔premise: a pixel of its leg past its round end',
          );
          final straight = rowAlong((roundEnds + tip) / 2);
          final onGrip = at(point(straight));
          final onPaper = at(point(from + towards * clear));
          expect(
            onGrip,
            _isRgb(_over(onPaper, grip.color, covered)),
            reason:
                '${grip.edge.name} grip at ${grip.box}: the line its edge '
                'crosses at $edge, covered $covered — the paper there '
                '${onPaper.toRadixString(16)}, read '
                '${onGrip.toRadixString(16)}',
          );
          // Past that line, nothing of it: the paper's line is its last.
          final beyond = far ? line + 1 : line - 1;
          if (beyond >= 0 && beyond < pixelsAcross) {
            Offset past(double along) => offsetAlong(
              axis,
              along: along,
              across: rowAcross(beyond + 0.5),
            );
            expect(
              at(past(straight)),
              at(past(from + towards * clear)),
              reason: '${grip.edge.name} grip at ${grip.box}: nothing of '
                  'it past its paper',
            );
          }
        }
        expect(
          fractional,
          greaterThan(0),
          reason: '⛔premise: an edge on no whole pixel — what the rounding '
              'is about',
        );

        // Outside a screen the row draws its cells itself, and its grips
        // with them, as its tile bakes them.
        final inks = {for (final grip in grips) grip.color.toARGB32()};
        final itself = TestRecordingCanvas();
        painter.paint(itself, size);
        expect(
          {
            for (final call in itself.invocations)
              if (call.invocation.memberName == #drawPath)
                (call.invocation.positionalArguments[1] as Paint).color
                    .toARGB32(),
          },
          containsAll(inks),
          reason: 'drawing its cells itself, the row draws its grips',
        );

        // The chrome takes their pointer and draws none of them.
        final chrome = timelineRowChromePainter(tester, 'r1', prefix: prefix)!;
        final canvas = TestRecordingCanvas();
        chrome.paint(
          canvas,
          tester.getSize(timelineRowChromeFinder('r1', prefix: prefix)),
        );
        expect(
          [
            for (final call in canvas.invocations)
              if (call.invocation.memberName == #drawPath &&
                  inks.contains(
                    (call.invocation.positionalArguments[1] as Paint).color
                        .toARGB32(),
                  ))
                call,
          ],
          isEmpty,
          reason: 'the chrome draws no grip over its paper',
        );
      });
    }
  }

  testWidgets('the pointer coming to rest on a grip inks it on the screen in '
      'that frame — the tile under it baked again in its paint', (
    tester,
  ) async {
    await pumpAt(tester, 0.9, TimelineOrientation.horizontal);
    final target = timelineRowChromeTargets(tester, 'r1')
        .whereType<TimelineRowGripTarget>()
        .firstWhere(
          (target) =>
              target.blockOrdinal == 1 &&
              target.edge == TimelineBlockEdge.start,
        );
    TimelineRowGrip gripNow() => timelineRowCellsPainterFor(
      tester,
      'r1',
    ).gripsIn(0, 18).firstWhere((grip) => grip.box == target.rect);
    final rest = gripNow().color;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(timelineRowChromeCenter(tester, 'r1', target.id));
    await tester.pump();

    final hovered = gripNow().color;
    expect(hovered, isNot(rest), reason: '⛔premise: a hover inks it');
    final corner = blockEdgeGripRightAngle(
      target.rect,
      edge: target.edge,
      axis: Axis.horizontal,
    );
    final inward = Offset(
      corner.dx == target.rect.right ? -1 : 1,
      corner.dy == target.rect.bottom ? -1 : 1,
    );
    final row = tester.getTopLeft(find.named('timeline-row-cells-r1'));
    final screen = _gridScreenOf(tester);
    final inCorner = _inCorner(corner, inward, target.paperCorner, 0.9);
    final onGrip = screen((row + inCorner) * 0.9);
    final onPaper = screen(
      (row +
              Offset(
                corner.dx + inward.dx * (target.rect.width + 2),
                inCorner.dy,
              )) *
          0.9,
    );
    expect(
      _isRgb(_over(onPaper, rest, 1)).matches(_over(onPaper, hovered, 1), {}),
      isFalse,
      reason: '⛔premise: the two inks read apart on its paper',
    );
    expect(
      onGrip,
      _isRgb(_over(onPaper, hovered, 1)),
      reason: 'the screen shows the hovered ink in the frame it came to rest',
    );
  });
}

/// A point in a grip's corner whose pixel is the grip's whole: on the
/// diagonal from its right angle [corner], [inward], two device pixels
/// inside the paper's circle of radius [round] — the grip's round end.
Offset _inCorner(Offset corner, Offset inward, double round, double scale) =>
    corner + inward * (round - (round - 2 / scale) / math.sqrt2);

/// [ink] laid over [under] as much as [covered]: the RGB the grid's blend
/// leaves.
int _over(int under, Color ink, double covered) {
  final share = ink.a * covered;
  var rgb = 0;
  for (final (shift, channel) in [(16, ink.r), (8, ink.g), (0, ink.b)]) {
    final below = under >> shift & 0xff;
    final mixed = channel * 255 * share + below * (1 - share);
    rgb |= mixed.round() << shift;
  }
  return rgb;
}

/// [expected] to the blend's rounding, a channel at a time.
Matcher _isRgb(int expected) => predicate<int>(
  (actual) => [16, 8, 0].every(
    (shift) =>
        ((actual >> shift & 0xff) - (expected >> shift & 0xff)).abs() <= 3,
  ),
  'within 3 of ${expected.toRadixString(16)} a channel',
);

/// The grid's screen as the compositor lays it, read at a device point: the
/// texel there, its RGB, through every layer above it.
int Function(Offset device) _gridScreenOf(WidgetTester tester) {
  final screen = tester.layers.whereType<rendering.TextureLayer>().firstWhere(
    (layer) => shownScreens.containsKey(layer.textureId),
  );
  final path = <rendering.Layer>[];
  for (rendering.Layer? layer = screen; layer != null; layer = layer.parent) {
    path.add(layer);
  }
  final transform = Matrix4.identity();
  for (var at = path.length - 1; at > 0; at -= 1) {
    (path[at] as rendering.ContainerLayer).applyTransform(
      path[at - 1],
      transform,
    );
  }
  final placed = MatrixUtils.transformRect(transform, screen.rect);
  final surface = shownScreens[screen.textureId]!;
  final texels = surface.read();
  return (device) {
    final x = (device.dx - placed.left).floor();
    final y = (device.dy - placed.top).floor();
    return _rgbAt(texels, (y * surface.width + x) * 4);
  };
}

int _rgbAt(Uint8List rgba, int at) =>
    rgba[at] << 16 | rgba[at + 1] << 8 | rgba[at + 2];
