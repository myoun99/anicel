import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';

import '../../helpers/timeline_host.dart';

/// 🚨유저 #8 (2026-08-14): 「타임라인 펼친상황의 버튼갱신, **1,2,3,4,n만
/// 천천히 페이드인**하면서 나타나거나 페이드아웃하면서 사라짐. **누가 이런
/// 차이 두라했지? 다 똑같이해. 페이드같은거 넣지마**」.
///
/// ⛔Nobody authored the fade. Material interpolated a TextButton's
/// foreground between its enabled and disabled colours over
/// `kThemeChangeDuration`, so the five comma buttons animated while the
/// icon buttons beside them did not — an icon button's colour is baked
/// into its `Icon` at build time. The fix was zero duration, not a
/// matching fade on nine other buttons: the ask was 「다 똑같이해」.
///
/// Since 2026-10-25 (card frame-panels-build-in-one-frame) they are faces
/// that read their colour at build, as the icon buttons do — so this asks
/// the screen, not a duration: the frame after the change is the end.
void main() {
  testWidgets('the comma buttons change state instantly, like every other '
      'button on the bar', (tester) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(800, 600),
      pixelsPerFrame: 24,
    );
    const ids = [
      'set-comma-1-button',
      'set-comma-2-button',
      'set-comma-3-button',
      'set-comma-4-button',
      'set-comma-n-button',
    ];
    Map<String, Color?> words() => {
      for (final id in ids)
        id: tester
            .widget<RichText>(
              find.descendant(
                of: find.byKey(ValueKey<String>(id)),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style
            ?.color,
    };

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final onACel = words();

    // Onto empty paper: the commas have nothing to set.
    session.selectFrameIndex(
      session.activeCutSpan.activeCutPlaybackFrameCount - 1,
    );
    await tester.pump();
    final theFrameAfter = words();
    await tester.pumpAndSettle();
    final settled = words();

    for (final id in ids) {
      expect(
        theFrameAfter[id],
        isNot(onACel[id]),
        reason: 'fixture: $id goes dead on empty paper',
      );
      expect(
        theFrameAfter[id],
        settled[id],
        reason: '$id is still on its way — that IS the fade',
      );
    }
  });
}
