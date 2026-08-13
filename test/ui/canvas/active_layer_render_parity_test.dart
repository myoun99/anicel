import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// BEING THE ROW YOU ARE DRAWING ON IS NOT A REASON TO COMPOSITE DIFFERENTLY.
///
/// 유저 실기 2026-08-13: 「액티브 레이어랑 그 외 레이어랑 렌더처리가 다른가?
/// 액티브 레이어로 하면 그림이 미묘하게 바껴. 렌더처리같은거 차이 안두고싶어.
/// 동일하게.」
///
/// This has now happened twice with the same shape, and both times the value
/// was correct everywhere except at the one place that could carry it:
///
///  * ㊱ — the row's OPACITY. `CanvasActiveLayerNode` had the field, the
///    painter's `_PaintActiveSurface` did not, so the live surface drew at
///    full strength while every other row honoured its slider.
///  * this round — the row's BLEND. Neither class had the field at all, so a
///    multiply row went back to srcOver the moment you stood on it.
///
/// Fixing the second one by hand would leave the third to be found by the
/// user. So these tests are about the SHAPE of the divergence rather than
/// about blend: [_sourceFieldParity] fails on any property one class carries
/// and its twin does not, and the pixel and session tests below cover the two
/// ways a field that DOES exist can still be dropped.
void main() {
  group('L1 — the two node kinds carry the same render properties', () {
    test('every render property of a cached row has a live-surface twin', () {
      final lines = File(
        'lib/src/ui/canvas/canvas_layer_stack_view.dart',
      ).readAsLinesSync();

      final cached = _fieldsOf(lines, 'CanvasLayerImageRequest');
      final live = _fieldsOf(lines, 'CanvasActiveLayerNode');

      expect(
        cached,
        isNotEmpty,
        reason: 'the parse found no fields — the class was renamed or moved, '
            'and a contract that parses nothing passes forever',
      );
      expect(live, isNotEmpty, reason: 'same, for the active node');

      final missingFromLive = cached
          .difference(live)
          .where((field) => !_asymmetryReasons.containsKey(field))
          .toList();
      final missingFromCached = live
          .difference(cached)
          .where((field) => !_asymmetryReasons.containsKey(field))
          .toList();

      expect(
        [...missingFromLive, ...missingFromCached],
        isEmpty,
        reason:
            'A render property exists on one node kind and not the other, so '
            'the layer you are drawing on composites differently from the '
            'same layer when you step off it — which is exactly what the '
            'user reported twice (㊱ opacity, then blendMode).\n'
            '  only on CanvasLayerImageRequest: $missingFromLive\n'
            '  only on CanvasActiveLayerNode:   $missingFromCached\n'
            'Either give the twin the field, or add it to _asymmetryReasons '
            'with the reason it genuinely cannot exist there.',
      );
    });

    test('the asymmetry allowlist stays honest — no stale entries', () {
      final lines = File(
        'lib/src/ui/canvas/canvas_layer_stack_view.dart',
      ).readAsLinesSync();
      final known = _fieldsOf(
        lines,
        'CanvasLayerImageRequest',
      ).union(_fieldsOf(lines, 'CanvasActiveLayerNode'));

      final stale = _asymmetryReasons.keys
          .where((field) => !known.contains(field))
          .toList();
      expect(
        stale,
        isEmpty,
        reason:
            'These fields no longer exist on either node, so their exemptions '
            'are protecting nothing and would silently excuse a future field '
            'that happens to reuse the name: $stale',
      );
    });
  });

  group('L2 — the painter puts the property on the pixels', () {
    const canvasSize = CanvasSize(width: 4, height: 4);

    BitmapSurfacePainter redSurfacePainter() {
      var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 4);
      tile = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 0,
        y: 0,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );
      return BitmapSurfacePainter(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 4,
          tiles: {tile.coord: tile},
        ),
        showTransparentBackground: false,
      );
    }

    /// The stack view's own painter, taken from the tree — the class is
    /// private and [CustomPainter] is the whole surface this needs.
    Future<CustomPainter> pumpStack(
      WidgetTester tester, {
      required LayerBlendMode blend,
      required BitmapSurfacePainter surfacePainter,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 4,
                height: 4,
                child: CanvasLayerStackView(
                  nodes: [
                    CanvasActiveLayerNode(opacity: 1, blendMode: blend),
                  ],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: surfacePainter,
                  // Something to blend AGAINST: multiply over nothing is
                  // indistinguishable from a dropped blend.
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFF00FF00),
                ),
              ),
            ),
          ),
        ),
      );
      final painted = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(CanvasLayerStackView),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.painter != null)
          .toList();
      expect(painted, isNotEmpty, reason: 'the stack view paints through one');
      return painted.first.painter!;
    }

    testWidgets('a blended live surface composites differently from a plain '
        'one', (tester) async {
      final surfacePainter = redSurfacePainter();

      final plain = await pumpStack(
        tester,
        blend: LayerBlendMode.normal,
        surfacePainter: surfacePainter,
      );
      final multiplied = await pumpStack(
        tester,
        blend: LayerBlendMode.multiply,
        surfacePainter: surfacePainter,
      );

      // ⚠️`toImage` is a REAL async round-trip: awaited under a widget test's
      // fake clock it simply hangs. Rasterizing belongs inside `runAsync`
      // (the sibling ㊱ test learned this the expensive way).
      final plainBytes = (await tester.runAsync(() => _rasterize(plain)))!;
      final multipliedBytes = (await tester.runAsync(
        () => _rasterize(multiplied),
      ))!;

      expect(
        multipliedBytes,
        isNot(equals(plainBytes)),
        reason:
            'The row carries a blend and the painter drew as if it did not. '
            'The live surface is drawn tile by tile, so the blend has to ride '
            'the assembled buffer the way opacity does — a per-tile blend '
            'would seam, and no blend at all is what the user saw: a multiply '
            'row that goes back to normal the moment you stand on it.',
      );
    });

    testWidgets('a blend change ALONE must repaint', (tester) async {
      final surfacePainter = redSurfacePainter();

      final plain = await pumpStack(
        tester,
        blend: LayerBlendMode.normal,
        surfacePainter: surfacePainter,
      );
      final multiplied = await pumpStack(
        tester,
        blend: LayerBlendMode.multiply,
        surfacePainter: surfacePainter,
      );

      expect(
        multiplied.shouldRepaint(plain),
        isTrue,
        reason:
            'Picking a blend from the row menu changes NOTHING else about '
            'this node. A gate that does not compare it shows the new value '
            'only when some unrelated fact happens to move — the ㉘/㉞ shape, '
            'and the reason ㊱ had to add the alpha to this same gate.',
      );
    });
  });

  group('L3 — the session reports the same property either way', () {
    /// Two drawing rows, each with a cel at the current frame. [target] is
    /// the one under test; [other] exists only to be stood on instead, so the
    /// same row can be observed from both sides.
    (EditorSessionManager, LayerId, LayerId) sessionWithTwoRows(
      LayerBlendMode blend,
    ) {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      // `createDrawingAtCurrentFrame` gives the ACTIVE row a cel; it does not
      // make a row. `addLayer` is what makes the second one.
      s.createDrawingAtCurrentFrame();
      final target = s.activeLayer!.id;
      s.setLayerBlendMode(target, blend);
      s.addLayer();
      s.createDrawingAtCurrentFrame();
      final other = s.activeLayer!.id;
      expect(other, isNot(target), reason: 'the fixture needs two real rows');
      return (s, target, other);
    }

    CanvasActiveLayerNode? activeNodeIn(List<CanvasLayerStackNode> nodes) {
      for (final node in nodes) {
        if (node is CanvasActiveLayerNode) {
          return node;
        }
        if (node is CanvasLayerGroupNode) {
          final found = activeNodeIn(node.children);
          if (found != null) {
            return found;
          }
        }
      }
      return null;
    }

    Iterable<CanvasLayerImageRequest> imageRequestsIn(
      List<CanvasLayerStackNode> nodes,
    ) sync* {
      for (final node in nodes) {
        if (node is CanvasLayerImageNode) {
          yield node.request;
        } else if (node is CanvasLayerGroupNode) {
          yield* imageRequestsIn(node.children);
        }
      }
    }

    test('the blend a row composites with does not depend on whether you are '
        'standing on it', () {
      final (s, target, other) = sessionWithTwoRows(LayerBlendMode.multiply);

      s.selectLayer(other);
      final asImage = imageRequestsIn(s.editingCanvasStack.nodes).toList();
      expect(
        asImage.map((r) => r.blendMode),
        contains(LayerBlendMode.multiply),
        reason: 'the CONTROL: a non-active row already carried its blend',
      );

      s.selectLayer(target);
      final asActive = activeNodeIn(s.editingCanvasStack.nodes);
      expect(asActive, isNotNull, reason: 'the active row stands in the tree');
      expect(
        asActive!.blendMode,
        LayerBlendMode.multiply,
        reason:
            'Same row, same frame, same project — only the cursor moved. The '
            'session used to forward four of the entry\'s five render fields '
            'to the active node and drop the blend on the floor.',
      );
    });

    test('so does the opacity — the ㊱ wiring, pinned at the session', () {
      final (s, target, other) = sessionWithTwoRows(LayerBlendMode.normal);
      s.setLayerOpacity(layerId: target, opacity: 0.4);

      s.selectLayer(other);
      final asImage = imageRequestsIn(s.editingCanvasStack.nodes)
          .where((r) => r.opacity < 1)
          .toList();
      expect(asImage, hasLength(1), reason: 'the CONTROL, again');
      final cachedOpacity = asImage.single.opacity;

      s.selectLayer(target);
      final asActive = activeNodeIn(s.editingCanvasStack.nodes);
      expect(
        asActive!.opacity,
        closeTo(cachedOpacity, 1e-9),
        reason:
            'ㅡ㊱ fixed the PAINTER. Nothing pinned the SESSION, so replacing '
            '`opacity: entry.opacity` with a literal 1.0 passed the whole '
            'suite. This is the test that mutation should kill.',
      );
    });
  });
}

/// Why a field legitimately exists on one node kind and not the other.
///
/// The allowlist is the point: it is short, and each entry is a place where
/// the property genuinely cannot cross. Anything NOT in here has to be on
/// both, because "the row you are drawing on" is not a rendering mode.
const _asymmetryReasons = <String, String>{
  'frameKey':
      'the cached image\'s ADDRESS in the frame store. A live surface is not '
      'addressed — it is the surface the brush is writing into.',
  'tint':
      'onion-skin Colors mode only, and a ghost is always built as a '
      'CanvasLayerImageNode (editor_canvas_area builds them that way), so an '
      'active node can never carry one.',
};

/// The `final <type> <name>;` declarations inside the class body that starts
/// at the line ending with [declaration].
///
/// Deliberately a plain scan rather than a real parse: the contract has to
/// stay readable by the next person who has to add a field to it.
Set<String> _fieldsOf(List<String> lines, String className) {
  // The declaration may carry `final`, `extends`, `implements` — match the
  // NAME and the opening brace, not a spelling of the whole line. (Matching
  // the whole line is how this contract first passed while parsing nothing:
  // `CanvasActiveLayerNode` declares `extends CanvasLayerStackNode`.)
  final declaration = RegExp(r'\bclass\s+' + className + r'\b.*\{\s*$');
  final start = lines.indexWhere(declaration.hasMatch);
  if (start < 0) {
    return const {};
  }
  final fields = <String>{};
  final field = RegExp(r'^\s*final\s+[\w<>,\s\?]+\s+(\w+)\s*;');
  for (var i = start + 1; i < lines.length; i += 1) {
    if (lines[i] == '}') {
      break;
    }
    final match = field.firstMatch(lines[i]);
    if (match != null) {
      fields.add(match.group(1)!);
    }
  }
  return fields;
}

/// The painter's output as raw RGBA bytes.
Future<Uint8List> _rasterize(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  const size = Size(4, 4);
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(4, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}
