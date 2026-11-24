import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_picture_place.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_tool_harness.dart' show boxFillingBake;
import '../helpers/draw_on_current_frame.dart';

/// 🗣️I-180-Q7 a (유저 2026-11-20 「a 숫자를 키워 다시 조판」): a canvas
/// resize that fits its picture sets each cel's texts again from their
/// grown numbers — by the app's one setting of a text (`setCelTextPlate`),
/// which the app hands its cut commands. Without it a fit of a cel with a
/// text takes no step.
///
/// ⚠️The engine's bake is stood in for ([boxFillingBake]) as the text
/// tool's tests stand it in: under a widget test's clock its raster never
/// answers.
void main() {
  testWidgets('a cel\'s text fitted ×2 through the app\'s own cut commands '
      'is set again at twice its size', (tester) async {
    debugCelTextBaker = boxFillingBake;
    addTearDown(() => debugCelTextBaker = null);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects
        .active;
    drawOnCurrentFrame(s);
    final cut = s.requireActiveCut;
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final key = s.brushFrameKeyForCut(
      cut,
      selection.layerId,
      selection.frameId,
    );
    final store = s.renderCaches.brushFrameStore;
    store.storeBakedSurface(
      key,
      store.bakedSurfaceOrNull(key)!.withTexts([
        CelText(
          id: 1,
          content: CelTextContent(
            spans: [
              const CelTextSpan(
                text: 'A',
                style: TextLetterStyle(fontSize: 24),
              ),
            ],
            anchor: CanvasPoint(x: 30, y: 20),
          ),
        ),
      ]),
    );
    final twice = CanvasSize(
      width: cut.canvasSize.width * 2,
      height: cut.canvasSize.height * 2,
    );
    const place = PictureFittedBy(MediaFitMode.stretch);

    await tester.runAsync(
      () => s.cutCommandCoordinator.placeCutCanvasAhead(
        cutId: cut.id,
        canvasSize: twice,
        place: place,
      ),
    );
    s.cutCommandCoordinator.placeCutCanvas(
      cutId: cut.id,
      canvasSize: twice,
      place: place,
    );
    await tester.pump();

    final text = store.bakedSurfaceOrNull(key)!.texts.single;
    expect(text.content.anchor, CanvasPoint(x: 60, y: 40));
    expect(text.content.spans.single.style.fontSize, 48);
    expect(text.plate, isNotEmpty, reason: 'set again, by the app\'s bake');
  });
}
