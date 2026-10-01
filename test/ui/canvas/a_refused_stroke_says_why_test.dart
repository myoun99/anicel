import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

/// 🗣️F-242 (유저 2026-09-29): 「그림 못그리는 이유 명확화. 지금 비지블off인
/// 프레임에서 그리려해도 프레임이 존재안한다고 뜨는데 그런부분 원인 제대로
/// 메시지 띄워주기」.
///
/// A refused press says the reason the stroke target itself refused for —
/// a hidden row is hidden, not missing a frame.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<EditorSessionManager> openApp(
    WidgetTester tester, {
    bool autoFrame = false,
  }) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
      autoCreateFrameOnDraw: autoFrame,
    );
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// A pen press and a short drag, and what the cursor said on the way.
  Future<({bool hidden, bool noFrame})> pressAndSay(WidgetTester tester) async {
    final press = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    // ⚠️By hand, not settled: the notice is transient.
    await tester.pump(const Duration(milliseconds: 120));
    final said = (
      hidden: find.text(AppText.strings.noticeLayerHidden).evaluate().isNotEmpty,
      noFrame: find.text(AppText.strings.noticeNoFrameHere).evaluate().isNotEmpty,
    );
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();
    return said;
  }

  testWidgets('a press on a hidden row\'s cel says the row is hidden, not '
      'that the frame is missing', (tester) async {
    final session = await openApp(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    session.layerSwitches.toggleLayerVisibility(session.activeLayerId!);
    await tester.pumpAndSettle();

    final said = await pressAndSay(tester);

    expect(said.hidden, isTrue, reason: '「원인 제대로 메시지 띄워주기」');
    expect(said.noFrame, isFalse, reason: 'the frame is there — only hidden');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a row inside a hidden folder is hidden too', (tester) async {
    // 유저 2026-08-13: 「숨긴 폴더는 안에 있는 레이어들도 숨김상태인거일거잖아」.
    final session = await openApp(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    session.folders.groupActiveLayerIntoFolder();
    await tester.pumpAndSettle();
    final folderId = session.activeCutOrNull!.layers.folderLayers.single.id;
    session.layerSwitches.toggleLayerVisibility(folderId);
    session.selectLayer(layerId);
    await tester.pumpAndSettle();
    expect(
      session.activeLayer!.isVisible,
      isTrue,
      reason: 'the premise: the row\'s OWN eye is on',
    );

    final said = await pressAndSay(tester);

    expect(said.hidden, isTrue);
    expect(said.noFrame, isFalse);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a hidden row\'s empty frame makes no block with the auto-frame '
      'on', (tester) async {
    final session = await openApp(tester, autoFrame: true);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    Layer row() =>
        session.activeCutOrNull!.layers.firstWhere((l) => l.id == layerId);
    session.layerSwitches.toggleLayerVisibility(layerId);
    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    final blocksBefore = row().timeline.length;

    final said = await pressAndSay(tester);

    expect(
      row().timeline.length,
      blocksBefore,
      reason: 'no stroke can land on a hidden row, so no block is made for one',
    );
    expect(said.hidden, isTrue);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
