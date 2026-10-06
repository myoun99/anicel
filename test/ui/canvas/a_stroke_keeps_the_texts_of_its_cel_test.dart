import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨★★★A STROKE KEEPS THE TEXTS OF ITS CEL (R9-rest, the text tool — 유저
/// 2026-10-02: 「텍스트도구가 아닌 브러시 등 다른도구 선택된상태에선 … 조작불가
/// … 즉 무관함」).
///
/// The real app, a real pen. A cel's texts live in its picture's own value,
/// and a stroke commits a NEW value: this is the place a text would be lost
/// if any step of the commit built that value fresh, and the place its
/// letters would flicker if the live overlay showed the stroke's tiles bare.
void main() {
  const frameId = FrameId('tx-frame');
  const layerId = LayerId('tx-layer');
  const key = BrushFrameKey(
    projectId: ProjectId('tx-project'),
    trackId: TrackId('tx-track'),
    cutId: CutId('tx-cut'),
    layerId: layerId,
    frameId: frameId,
  );

  Project oneFrameProject() => Project(
    id: const ProjectId('tx-project'),
    name: 'Text Cel',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('tx-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('tx-cut'),
            name: 'Text Cel Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'Text Cel Layer',
                frames: [
                  Frame(id: frameId, name: 'A', duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(frameId, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  BrushFrameEditingCoordinator coordinatorOf(WidgetTester tester) {
    final coordinator = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .pixelEditing
        .coordinator;
    expect(coordinator, isNotNull, reason: '⛔fixture: the canvas built one');
    return coordinator!;
  }

  /// A text whose plate covers the whole page in thin red — wherever the
  /// pen lands, it lands under a letter.
  CelText textOverThePage(BitmapSurface surface) {
    final pixels = Uint8List(BitmapTile.bytesFor(surface.tileSize));
    for (var offset = 0; offset < pixels.length; offset += 4) {
      pixels[offset] = 220;
      pixels[offset + 3] = 96;
    }
    final letters = BitmapTile(size: surface.tileSize, pixels: pixels);
    return CelText(
      id: 1,
      content: CelTextContent(
        spans: const [CelTextSpan(text: 'over', style: TextLetterStyle())],
        anchor: CanvasPoint(x: 0, y: 0),
      ),
      plate: {
        for (var y = 0; y < surface.tileRowCount; y += 1)
          for (var x = 0; x < surface.tileColumnCount; x += 1)
            TileCoord(x: x, y: y): letters,
      },
    );
  }

  testWidgets('🚨the text is on the cel after the stroke, and through an '
      'undo of it; the pen\'s tiles showed the letters while it was down '
      'and handed their pictures to the tiles that show them', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: oneFrameProject())),
    );
    await tester.pumpAndSettle();
    final coordinator = coordinatorOf(tester);
    final text = textOverThePage(coordinator.currentSurfaceOf(key));
    coordinator.restoreSurfaceSnapshot(
      key,
      coordinator.currentSurfaceOf(key).withTexts([text]),
    );
    await pumpFrames(tester);
    final before = coordinator.currentSurfaceOf(key);
    expect(before.texts.single, same(text), reason: '⛔fixture');
    expect(before.tiles, isEmpty, reason: '⛔fixture: nothing drawn yet');

    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();

    // The pen is down: the overlay stands on the cel WITH its text.
    final overlay = tester
        .widget<InteractiveBrushEditCanvasView>(
          find.byKey(const ValueKey<String>('brush-canvas-view')),
        )
        .overlayModel!;
    expect(overlay.preBlendBase!.texts.single, same(text));
    expect(overlay.tileImages, isNotEmpty, reason: '⛔fixture: it drew');

    await pen.up();
    await pumpFrames(tester);

    final after = coordinator.currentSurfaceOf(key);
    expect(after.tiles, isNotEmpty, reason: '⛔fixture: the stroke landed');
    expect(
      after.texts.single,
      same(text),
      reason: 'the commit made a new picture — and it is the same text',
    );

    // Every tile the stroke made is shown under the letters, and it is THAT
    // tile — not the bare drawing's — that holds a picture.
    final shown = celSurfaceWithTextsLaid(after);
    final cache = BitmapTileImageCache.instance;
    for (final entry in after.tiles.entries) {
      final laid = shown.tileAt(entry.key)!;
      expect(laid, isNot(same(entry.value)), reason: '⛔fixture: under text');
      expect(
        cache.imageFor(laid),
        isNotNull,
        reason: '${entry.key}: the tile the canvas draws has its picture',
      );
      expect(
        cache.imageFor(entry.value),
        isNull,
        reason:
            '${entry.key}: a picture with letters in it was pinned to the '
            'bare drawing\'s tile — it would go on showing them after the '
            'text is gone',
      );
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester);

    final undone = coordinator.currentSurfaceOf(key);
    expect(undone.tiles, isEmpty, reason: 'the stroke is gone');
    expect(undone.texts.single, same(text), reason: 'and the text is not');
  });
}
