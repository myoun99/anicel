import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// The V row's opacity bar previews per move, like a layer's (R4 #4): the
/// value rides a notifier and the canvas follows WITHOUT a session notify.
///
/// 🔬The canvas READ that preview — the editing fade is the track's static
/// opacity times the transition ramp, and the static half answers the live
/// drag value — but it never LISTENED to it: the layer preview was in the
/// canvas area's listenables and the track's was not. A V-row drag reached
/// the canvas only when something else happened to rebuild it (found while
/// moving both previews into `OpacityVerbs`, ARCH-session-state).
void main() {
  /// The editing canvas's fade wash, read off the painter it hands the
  /// frame — its alpha is `1 − fade`. Null while no wash is up.
  double? washAlpha(WidgetTester tester) {
    for (final paint in tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    )) {
      final painter = paint.painter;
      if (painter != null &&
          painter.runtimeType.toString() == '_CutFadeWashPainter') {
        return ((painter as dynamic).color as Color).a;
      }
    }
    return null;
  }

  testWidgets('🚨a V-row opacity drag fades the editing canvas as it moves, '
      'not when something else rebuilds it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(washAlpha(tester), isNull, reason: '⛔전제: a full track, no wash');

    final track = session.repository.requireProject().tracks.first.id;
    session.opacityVerbs.previewTrackOpacity(track, 0.4);
    await tester.pump();

    expect(
      washAlpha(tester),
      closeTo(0.6, 0.01),
      reason: 'the drag moved the fade — with no session notify, only the '
          'canvas listening to the V row\'s preview can show it',
    );

    session.opacityVerbs.commitTrackOpacity(track, 0.4);
    await tester.pumpAndSettle();
    expect(washAlpha(tester), closeTo(0.6, 0.01), reason: 'and it lands there');
  });
}
