import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨유저 #8 (2026-08-14): 「타임라인 펼친상황의 버튼갱신, **1,2,3,4,n만
/// 천천히 페이드인**하면서 나타나거나 페이드아웃하면서 사라짐. **누가 이런
/// 차이 두라했지? 다 똑같이해. 페이드같은거 넣지마**」.
///
/// ⛔Nobody authored the fade. Material interpolates a button's foreground
/// between its enabled and disabled colours over `kThemeChangeDuration`,
/// and a TEXT button's colour comes from that state — so the five comma
/// buttons animated while the icon buttons beside them did not, because an
/// icon button's colour is baked into its `Icon` at build time and leaves
/// the button nothing to interpolate.
///
/// ★So the fix is zero duration, not a matching fade on nine other
/// buttons: the ask was 「다 똑같이해」.
void main() {
  testWidgets('the comma buttons change state instantly, like every other '
      'button on the bar', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final id in const [
      'set-comma-1-button',
      'set-comma-2-button',
      'set-comma-3-button',
      'set-comma-4-button',
      'set-comma-n-button',
    ]) {
      final button = tester.widget<TextButton>(
        find.byKey(ValueKey<String>(id)),
      );
      expect(
        button.style?.animationDuration,
        Duration.zero,
        reason: '$id still interpolates its colour — that IS the fade',
      );
    }
  });
}
