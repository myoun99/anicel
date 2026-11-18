import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

import '../../helpers/home_page_probes.dart';

/// 🗣️the-screen-shows-a-frame-the-green-band-leaves-empty (유저
/// 2026-11-15): a frame a canvas made was on the screen, and the green band
/// filled there only once the walk moved on. The band reads where each
/// frame stands, and heard the walk's progress — a picture the walk laid,
/// and no other. What moves where a frame stands is told in one place
/// (`FramePictures.standingMoved`, frame_pictures_test.dart): each panel's
/// band hears that.
void main() {
  testWidgets('the timeline\'s band and the conte\'s hear where a frame '
      'stands', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final standing = session.playbackRig.framePictures.standingMoved;
    Listenable? bandOf(Type panel) => tester
        .widget<TimelineRulerCursorOverlay>(
          find.descendant(
            of: find.byType(panel),
            matching: find.byType(TimelineRulerCursorOverlay),
          ),
        )
        .repaintSignal;

    expect(bandOf(TimelinePanel), same(standing));
    await showStoryboardPanel(tester);
    await tester.pumpAndSettle();
    expect(bandOf(StoryboardPanel), same(standing));
  });
}
