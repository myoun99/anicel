import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 📨I-14: a cut from the media viewer holds its source at full size, so the
/// held piece can be the largest single picture the app keeps — and a
/// holding the census does not read lands in 「untracked」, where it reads as
/// the engine's (the import-export session: 「새로 이미지를 쥐는 곳은
/// 메모리 인구조사에 올려야 합니다」).
void main() {
  testWidgets('the held piece is on the census, on the brush tips row it '
      'stamps like', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final slot = tester
        .widgetList<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .map((panel) => panel.cutPieceSlot)
        .firstWhere((held) => held != null)!;
    int brushTipsRow() => collectMemoryCensus(
      session,
    ).items.firstWhere((item) => item.id == 'brushTips').bytes;
    final before = brushTipsRow();

    slot.hold(
      CutPiece(
        image: BrushStampImage(
          id: 'counted',
          width: 30,
          height: 20,
          rgba: Uint8List(30 * 20 * 4),
        ),
        originLeft: 0,
        originTop: 0,
      ),
    );

    expect(session.renderCaches.cutPieceBytes, 30 * 20 * 4);
    expect(brushTipsRow() - before, 30 * 20 * 4);

    // The workspace goes, and with it the piece it held.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(session.renderCaches.cutPieceBytes, 0);
  });
}
