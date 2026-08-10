import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// UI-R9 #6, restated 2026-08-10: the counter reads the track-global frame
/// ABOVE the cut-local one — two lines, one number each, no `G`/`L` labels
/// (유저 확정: 위/아래가 곧 라벨). It used to be one line reading
/// `<global> · <cut-local>`; stacking costs no width and absorbs a digit's
/// growth into the line that grew.
///
/// The TIMELINE tab keeps the same two lines with the top one EMPTY — that
/// is what puts the local number at the same height in both panels — and
/// timeline_panel_test pins that half.
void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    manager.createCut();
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.frameSeekCommitted]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  String lineText(WidgetTester tester, String keyValue) =>
      tester.widget<Text>(find.byKey(ValueKey<String>(keyValue))).data!;

  String globalLine(WidgetTester tester) =>
      lineText(tester, 'timeline-global-frame-counter');
  String localLine(WidgetTester tester) =>
      lineText(tester, 'timeline-local-frame-counter');

  testWidgets('counter stacks global over cut-local', (tester) async {
    final manager = await pumpHost(tester);
    final cuts = manager.activeTrack.cuts;
    expect(cuts.length, 2);

    // First cut, frame 3: global == local.
    manager.selectCut(cuts[0].id);
    manager.selectFrameIndex(2);
    await tester.pumpAndSettle();
    expect(globalLine(tester), '3');
    expect(localLine(tester), '3');

    // Second cut, frame 5: the global index leads by cut 1's length.
    manager.selectCut(cuts[1].id);
    manager.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(globalLine(tester), '${cuts[0].duration + 4 + 1}');
    expect(localLine(tester), '5');
  });

  testWidgets('the global line sits ABOVE the local one, right-aligned', (
    tester,
  ) async {
    // Order is the whole label here — there is no `G`, so if the two ever
    // swapped, nothing on screen would say so.
    final manager = await pumpHost(tester);
    manager.selectCut(manager.activeTrack.cuts[1].id);
    manager.selectFrameIndex(4);
    await tester.pumpAndSettle();

    final global = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-global-frame-counter')),
    );
    final local = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-local-frame-counter')),
    );
    expect(global.top, lessThan(local.top));
    // Right edges agree, so the digits line up in a column.
    expect(global.right, moreOrLessEquals(local.right, epsilon: 0.5));
  });
}
