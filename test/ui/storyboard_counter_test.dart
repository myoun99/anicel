import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// UI-R9 #6: the storyboard toolbar counter reads `<global> · <cut-local>`
/// — the track-global frame LEFT of the cut-local one. (The timeline tab's
/// counter stays plain cut-local; pinned in timeline_panel_test.)
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

  String counterText(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.byKey(const ValueKey<String>('timeline-current-frame-counter')),
    );
    return text.data!;
  }

  testWidgets('counter shows global · cut-local, global first', (tester) async {
    final manager = await pumpHost(tester);
    final cuts = manager.activeTrack.cuts;
    expect(cuts.length, 2);

    // First cut, frame 3: global == local.
    manager.selectCut(cuts[0].id);
    manager.selectFrameIndex(2);
    await tester.pumpAndSettle();
    expect(counterText(tester), '3 · 3');

    // Second cut, frame 5: the global index leads by cut 1's length.
    manager.selectCut(cuts[1].id);
    manager.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(counterText(tester), '${cuts[0].duration + 4 + 1} · 5');
  });
}
