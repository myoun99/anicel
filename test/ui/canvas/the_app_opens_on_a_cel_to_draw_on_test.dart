import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

/// 🚨F-211 (유저 2026-09-28): 「… 1번인덱스에 프레임도 만들어서 **키자마자
/// 그리는게 가능하도록** 하고싶음. 신규유저 배려」 — said of the whole app,
/// so it is asked of the whole app: nothing pressed before it, the FIRST
/// press on the canvas draws.
///
/// ⚠️With the auto-frame OFF. With it on, a press on an empty row makes its
/// own cel (F-171), and this would pass on the row the app used to open on.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  testWidgets('the app as it opens takes the first stroke: into the cel it '
      'opened with, with no notice and no new block', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      autoCreateFrameOnDraw: false,
    );
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layerId = session.activeLayerId!;
    Layer layer() => session.activeCutOrNull!.layers.firstWhere(
      (candidate) => candidate.id == layerId,
    );
    final opened = layer();
    expect(
      session.renderCaches.layerContentBoundsAt(opened, 0),
      isNull,
      reason: 'premise: nothing is drawn yet',
    );

    final press = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.text(AppText.strings.noticeNoFrameHere),
      findsNothing,
      reason: 'there is a frame here: the one the app opened with',
    );
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    await press.moveBy(const Offset(30, 20));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();

    expect(
      session.renderCaches.layerContentBoundsAt(layer(), 0),
      isNotNull,
      reason: '「키자마자 그리는게 가능」 — the line is on the first frame',
    );
    expect(
      [for (final frame in layer().frames) frame.id],
      [for (final frame in opened.frames) frame.id],
      reason: 'it went into the cel the app opened with: no block was made',
    );

    session.playbackRig.prerenderScheduler.cancel();
  });
}
