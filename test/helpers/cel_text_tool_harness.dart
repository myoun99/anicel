import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_finders.dart';
import 'settle_async.dart';

/// THE TEXT TOOL, DRIVEN ON THE REAL APP (R9-rest): the project it works
/// on, the baker that stands in for the engine, and the few verbs a test
/// of it keeps saying — pick the tool, press where a canvas pixel is, type.
///
/// ⚠️THE ENGINE IS STOOD IN FOR ([boxFillingBake], through
/// `debugCelTextBaker`). Under a widget test's clock the engine's raster
/// never answers, so a text typed into the real app would never be shown,
/// let alone land. What the engine draws for a text is pinned against the
/// engine itself in `cel_text_bake_test.dart`; these tests are about what
/// the TOOL does with a text, and a plate that fills the text's box says
/// that as well as letters would.

const textToolFrameId = FrameId('text-tool-frame');
const textToolSecondFrameId = FrameId('text-tool-frame-2');
const textToolLayerId = LayerId('text-tool-layer');
const textToolKey = BrushFrameKey(
  projectId: ProjectId('text-tool-project'),
  trackId: TrackId('text-tool-track'),
  cutId: textToolCutId,
  layerId: textToolLayerId,
  frameId: textToolFrameId,
);
const textToolSecondKey = BrushFrameKey(
  projectId: ProjectId('text-tool-project'),
  trackId: TrackId('text-tool-track'),
  cutId: textToolCutId,
  layerId: textToolLayerId,
  frameId: textToolSecondFrameId,
);

/// The row [textToolProject] adds with no cel at all.
const textToolEmptyLayerId = LayerId('text-tool-empty-layer');

/// The cut the text tool works in.
const textToolCutId = CutId('text-tool-cut');

/// The cut [textToolProject] adds after it — one row, no cel anywhere.
const textToolSecondCutId = CutId('text-tool-second-cut');

/// One cut, one layer, a drawing at the first frame — and with [drawings]
/// two, another at the second. Every frame after them is EMPTY: no cel.
/// The layer wears [effects]. With [emptyLayer], a second row beside it
/// has no cel anywhere ([textToolEmptyLayerId]). With [secondCut], another
/// cut follows on the track ([textToolSecondCutId]).
Project textToolProject({
  int drawings = 1,
  List<LayerEffect> effects = const [],
  bool emptyLayer = false,
  bool secondCut = false,
}) => Project(
  id: const ProjectId('text-tool-project'),
  name: 'Text Tool',
  createdAt: DateTime.utc(2026),
  tracks: [
    Track(
      id: const TrackId('text-tool-track'),
      name: 'Video Track',
      cuts: [
        Cut(
          id: textToolCutId,
          name: 'Text Tool Cut',
          duration: defaultCutDuration,
          canvasSize: defaultCutCanvasSize,
          layers: [
            Layer(
              id: textToolLayerId,
              name: 'Text Tool Layer',
              effects: effects,
              frames: [
                for (final (index, id) in _drawings.take(drawings).indexed)
                  Frame(
                    id: id,
                    name: 'ABCD'[index],
                    duration: 1,
                    strokes: const [],
                  ),
              ],
              timeline: {
                for (final (index, id) in _drawings.take(drawings).indexed)
                  index: TimelineExposure.drawing(id, length: 1),
              },
            ),
            if (emptyLayer)
              Layer(
                id: textToolEmptyLayerId,
                name: 'Empty Layer',
                frames: [],
              ),
          ],
        ),
        if (secondCut)
          Cut(
            id: textToolSecondCutId,
            name: 'Second Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: const LayerId('text-tool-second-cut-layer'),
                name: 'Second Cut Layer',
                frames: [],
              ),
            ],
          ),
      ],
    ),
  ],
);

const _drawings = [textToolFrameId, textToolSecondFrameId];

/// A plate that fills the text's BLOCK, upright where the text stands, in
/// its first letter's colour — the stand-in for the engine.
Future<Map<TileCoord, BitmapTile>> boxFillingBake(
  CelTextLayout layout, {
  required PasteboardWall pasteboard,
  required int tileSize,
  Map<TileCoord, BitmapTile> previous = const {},
}) async {
  final content = layout.content;
  final block = layout.block.shift(
    Offset(content.anchor.x, content.anchor.y),
  );
  final argb = content.spans.first.style.color;
  final rgba = [
    (argb >> 16) & 0xFF,
    (argb >> 8) & 0xFF,
    argb & 0xFF,
    (argb >> 24) & 0xFF,
  ];
  final buffers = <TileCoord, Uint8List>{};
  for (var y = block.top.floor(); y < block.bottom.ceil(); y += 1) {
    for (var x = block.left.floor(); x < block.right.ceil(); x += 1) {
      final coord = TileCoord(
        x: floorDiv(x, tileSize),
        y: floorDiv(y, tileSize),
      );
      final buffer = buffers.putIfAbsent(
        coord,
        () => Uint8List(BitmapTile.bytesFor(tileSize)),
      );
      final offset =
          ((y - coord.y * tileSize) * tileSize + (x - coord.x * tileSize)) * 4;
      buffer.setRange(offset, offset + 4, rgba);
    }
  }
  return {
    for (final entry in buffers.entries)
      entry.key: BitmapTile(size: tileSize, pixels: entry.value),
  };
}

/// The real app on [project], with the engine stood in for — or, with
/// [engine], left to set the text itself ([settleWithTheEngine]) — in a
/// window of [size].
Future<void> pumpTextToolApp(
  WidgetTester tester, {
  Project? project,
  bool engine = false,
  Size size = const Size(1600, 900),

  /// The fonts this device was brought; null leaves the workspace to its
  /// own library — the test sandbox, which is empty.
  FontLibraryService? fonts,

  /// The fx plugins this device has installed; null leaves the app its
  /// own, which has none.
  InstalledFxPlugins? fxPlugins,
}) async {
  debugCelTextBaker = engine ? null : boxFillingBake;
  addTearDown(() => debugCelTextBaker = null);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: project ?? textToolProject(),
        fontLibraryService: fonts,
        fxPlugins: fxPlugins,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Lets the REAL engine set the text in hand: its raster answers on the
/// machine's own clock, which a widget test's does not turn — so real time
/// is let pass, and what it answered is then let run, until the text on
/// screen is the text wanted.
Future<void> settleWithTheEngine(WidgetTester tester) async {
  bool settled() {
    final session = textToolOf(tester).session;
    return session == null || session.settled;
  }

  if (!await settleAsync(tester, settled)) {
    fail('the engine did not set the text');
  }
}

EditorSessionManager sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

BrushFrameEditingCoordinator coordinatorOf(WidgetTester tester) =>
    sessionOf(tester).pixelEditing.coordinator!;

/// The cel's picture as it is STORED — what an edit that has landed
/// changed.
BitmapSurface celOf(WidgetTester tester, [BrushFrameKey key = textToolKey]) =>
    coordinatorOf(tester).currentSurfaceOf(key);

/// Puts the text tool in hand, by its button on the rail.
Future<void> takeTextTool(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('tool-text-button')));
  await pumpFrames(tester);
}

Finder textLayer() => find.byKey(const ValueKey<String>('cel-text-tool-layer'));

/// The field the keyboard types into. ⚠️It is OFFSTAGE — laid out and
/// focused, never painted — so a finder has to be told to look there.
Finder textField() => find.byKey(
  const ValueKey<String>('cel-text-field'),
  skipOffstage: false,
);

/// The picture the canvas draws IN THE PLACE of the cel under the tool,
/// texts laid in: the cel itself, or with a text in hand the hole it left
/// — what floats over that is [canvasPixel]'s (F-344).
///
/// ⚠️Laid in means none is left as a text: its [BitmapSurface.texts] are
/// empty whatever the cel carries. What floats is [canvasFloat].
BitmapSurface canvasShows(WidgetTester tester) =>
    _canvasPainter(tester).surface;

/// What floats over [canvasShows] while a text is in hand — its own pixels
/// (`CelTextFloat`), or on a row that keys its colours what the cel will
/// show where it lands (`CelTextLanding`) — null with none lifted.
LandingPreview? canvasFloat(WidgetTester tester) =>
    _canvasPainter(tester).landingPreview?.value;

/// One pixel of what the canvas DRAWS for the cel under the tool, as
/// straight RGBA — [canvasShows] and what floats over it, the text in hand,
/// drawn by the canvas's own painter at full size.
Future<List<int>> canvasPixel(WidgetTester tester, int x, int y) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(-x.toDouble(), -y.toDouble())
    ..clipRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1));
  _canvasPainter(tester).paintContentInto(canvas, pixelRatio: 1);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
  );
  image.dispose();
  return List<int>.from(bytes!.buffer.asUint8List());
}

/// What the canvas DRAWS for the cel under the tool over [region] of the
/// canvas, at 1/2^[level] — 100% at 0, half that at each step — as raw
/// RGBA: [canvasPixel]'s draw, of a whole region.
Future<Uint8List> canvasRaster(
  WidgetTester tester,
  Rect region, {
  int level = 0,
}) async {
  final scale = 1 / (1 << level);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(-region.left, -region.top)
    ..clipRect(region);
  _canvasPainter(tester).paintContentInto(canvas, scale: scale, pixelRatio: 1);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(
    region.width.toInt() >> level,
    region.height.toInt() >> level,
  );
  picture.dispose();
  final bytes = await tester.runAsync(image.toByteData);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

BitmapSurfacePainter _canvasPainter(WidgetTester tester) => tester
    .widgetList<FramePictureView>(find.byType(FramePictureView))
    .map((view) => view.live?.activeSurfacePainter)
    .whereType<BitmapSurfacePainter>()
    .single;

/// The hand the canvas holds texts with.
CelTextTool textToolOf(WidgetTester tester) =>
    tester.widget<CelTextToolLayer>(find.byType(CelTextToolLayer)).tool;

/// The cel under the text tool — null on a frame that has none.
CelTextCel? celUnderTool(WidgetTester tester) =>
    tester.widget<CelTextToolLayer>(find.byType(CelTextToolLayer)).cel;

/// What the text tool draws over the canvas: the box, the handles, the
/// caret.
Finder textChrome() => find.descendant(
  of: textLayer(),
  matching: find.byType(CustomPaint),
);

/// The canvas pixel in the middle of what the artist can SEE of the drawing
/// canvas — a whole one, so a text set there stands exactly where a test
/// says. ⚠️The canvas is the app's floor and the panels lie on it: a pixel
/// named by its numbers alone is as likely under the timeline as not
/// (`visibleCanvasPoint`).
Offset canvasPixelInView(WidgetTester tester) {
  final layer = tester.widget<CelTextToolLayer>(find.byType(CelTextToolLayer));
  final artwork = layer.stage.artworkAt(
    visibleCanvasPoint(tester) - tester.getTopLeft(textLayer()),
  )!;
  return Offset(artwork.dx.roundToDouble(), artwork.dy.roundToDouble());
}

/// Where the canvas pixel ([x], [y]) is on the text tool's own layer — the
/// frame everything it draws is drawn in.
Offset onLayer(WidgetTester tester, double x, double y) => tester
    .widget<CelTextToolLayer>(find.byType(CelTextToolLayer))
    .stage
    .onPanel(Offset(x, y));

/// Where the canvas pixel ([x], [y]) is on the screen.
Offset onScreen(WidgetTester tester, double x, double y) =>
    tester.getTopLeft(textLayer()) + onLayer(tester, x, y);

/// A mouse press on the canvas pixel ([x], [y]) — or a [kind]'s — still
/// down a frame later.
Future<TestGesture> pressAt(
  WidgetTester tester,
  double x,
  double y, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final hand = await tester.startGesture(onScreen(tester, x, y), kind: kind);
  await tester.pump();
  return hand;
}

/// A mouse click on the canvas pixel ([x], [y]).
Future<void> clickAt(WidgetTester tester, double x, double y) async {
  final mouse = await pressAt(tester, x, y);
  await mouse.up();
  await pumpFrames(tester);
}

/// A mouse drag from one canvas pixel to another — or a [kind]'s — in a
/// few steps.
Future<void> dragFrom(
  WidgetTester tester,
  Offset from,
  Offset to, {
  int steps = 4,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final start = onScreen(tester, from.dx, from.dy);
  final end = onScreen(tester, to.dx, to.dy);
  final hand = await pressAt(tester, from.dx, from.dy, kind: kind);
  for (var i = 1; i <= steps; i += 1) {
    await hand.moveTo(Offset.lerp(start, end, i / steps)!);
    await tester.pump();
  }
  await hand.up();
  await pumpFrames(tester);
}

/// Types [text] into the text in hand, as a keyboard hands it over: the
/// field's whole text, the caret after it.
Future<void> typeText(WidgetTester tester, String text) async {
  await tester.enterText(textField(), text);
  await pumpFrames(tester);
}

/// One pixel of the picture [surface] SHOWS — its drawing with its texts
/// laid over it — as straight RGBA, or null where it shows nothing.
List<int>? shownPixel(BitmapSurface surface, int x, int y) {
  final laid = celSurfaceWithTextsLaid(surface);
  final size = laid.tileSize;
  final tile = laid.tileAt(
    TileCoord(x: floorDiv(x, size), y: floorDiv(y, size)),
  );
  if (tile == null) {
    return null;
  }
  final offset = ((y - floorDiv(y, size) * size) * size +
          (x - floorDiv(x, size) * size)) *
      4;
  return tile.readPixels(
    (_, view) => List<int>.from(view.sublist(offset, offset + 4)),
  );
}
