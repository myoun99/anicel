import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/words_cut_off.dart';

/// 🚨text-scale-sheet-plates (유저 2026-09-25, answering
/// text-scale-sheet-plates-Q1: 「판은 그대로, 글자를 판에 맞춰 줄인다(레일과
/// 같은 법)」). The x-sheet's column header writes its label plates' words
/// across a plate 14 tall; at 2× the take's T1 stood 18 tall in it and was
/// cut top and bottom, while the rail's same plate shrinks its writing into
/// the column (「길면 글자 축소 허용」). The plate keeps its size, and the
/// words shrink into it — evenly, and only past it. The colour plate beside
/// it stretches its words to fill (유저 2026-08-28: 「꽉 채우게」), so it was
/// never cut; it is pinned here too, so both plates answer.
///
/// ⚠️In the app's face or not at all ([loadTheAppFaces]), and in the real
/// root ([AnicelApp]).
void main() {
  setUpAll(loadTheAppFaces);

  void atTextScale(WidgetTester tester, double scale) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// The app on the x-sheet, its first drawing row labelled 레이아웃, take 1.
  Future<String> onTheSheetWithATake(WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layer = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    session.layerMarks.setLayerMark(
      layer.id,
      const LayerMark(process: LayerProcess.layout, take: 1),
    );
    await tester.tap(
      find
          .byKey(const ValueKey<String>('timeline-orientation-toggle-button'))
          .first,
    );
    await tester.pumpAndSettle();
    return layer.id.value;
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('at $scale× the take\'s words stand inside the sheet\'s '
        'plate, uncut — shrunk only past it', (tester) async {
      atTextScale(tester, scale);
      final layerId = await onTheSheetWithATake(tester);

      final plate = find.descendant(
        of: find.byType(XSheetTimelineGrid),
        matching: find.byKey(ValueKey<String>('xsheet-layer-take-$layerId')),
      );
      expect(plate, findsOneWidget, reason: 'LIVENESS — the sheet shows it');
      final take = find.descendant(of: plate, matching: find.text('T1'));
      expect(take, findsOneWidget, reason: 'LIVENESS — the take is written');

      expect(wordsCutOff(plate), isEmpty);
      expect(wordsCutAcross(plate), isEmpty);

      final room = tester.getRect(plate);
      final written = tester.getRect(take);
      expect(written.top, greaterThanOrEqualTo(room.top - 0.5));
      expect(written.bottom, lessThanOrEqualTo(room.bottom + 0.5));
      expect(written.left, greaterThanOrEqualTo(room.left - 0.5));
      expect(written.right, lessThanOrEqualTo(room.right + 0.5));

      // Shrunk only past the plate: at 1× the words are their own size.
      final own = tester.renderObject<RenderParagraph>(take).size;
      final shown = written.height / own.height;
      if (scale == 1.0) {
        expect(shown, closeTo(1, 0.001), reason: '1× fits — nothing shrinks');
      } else if (own.height > room.height) {
        expect(shown, lessThan(1), reason: 'past the plate, it shrinks');
      }
    });

    testWidgets('at $scale× the colour plate beside it keeps its words '
        'inside it too — stretched to fill, never cut', (tester) async {
      atTextScale(tester, scale);
      final layerId = await onTheSheetWithATake(tester);

      final plate = find.descendant(
        of: find.byType(XSheetTimelineGrid),
        matching: find.byKey(ValueKey<String>('xsheet-layer-mark-$layerId')),
      );
      expect(plate, findsOneWidget, reason: 'LIVENESS — the sheet shows it');
      final words = find.descendant(of: plate, matching: find.byType(Text));
      expect(words, findsWidgets, reason: 'LIVENESS — the stage is written');

      expect(wordsCutOff(plate), isEmpty);
      expect(wordsCutAcross(plate), isEmpty);
      final room = tester.getRect(plate);
      for (final word in words.evaluate()) {
        final written = tester.getRect(find.byWidget(word.widget));
        expect(written.top, greaterThanOrEqualTo(room.top - 0.5));
        expect(written.bottom, lessThanOrEqualTo(room.bottom + 0.5));
      }
    });
  }
}
