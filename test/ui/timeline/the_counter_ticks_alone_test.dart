import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';

/// The frame counter ticks with every frame played, and its width moves the
/// row, so the bar it stands on is one tick layer ([TimelineCommandBar]).
/// What stands beside it there is moved, not painted, when it ticks
/// (playback-making-pictures-shakes-the-frames, 10-11): 🔬the bar was
/// painted again whole on every frame played — 72–78 render objects, the
/// zoom slider most of them.
void main() {
  testWidgets('🚨a counter tick paints the counter, and not the zoom beside '
      'it', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: TimelineCommandBar(
                cluster: TimelineViewCluster(
                  frameCursor: cursor,
                  projectFrameRate: ProjectFrameRate.fps24,
                  showSeconds: false,
                  pixelsPerFrame: 24,
                  onPixelsPerFrameChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final slider = tester.renderObject(
      find.byKey(const ValueKey<String>('timeline-zoom-slider')),
    );
    final counter = tester.renderObject(
      find.byKey(const ValueKey<String>('timeline-local-frame-counter')),
    );
    bool under(RenderObject painted, RenderObject root) {
      for (RenderObject? at = painted; at != null; at = at.parent) {
        if (identical(at, root)) {
          return true;
        }
      }
      return false;
    }

    var sliderPaints = 0;
    var counterPaints = 0;
    debugOnProfilePaint = (painted) {
      if (under(painted, slider)) {
        sliderPaints += 1;
      }
      if (under(painted, counter)) {
        counterPaints += 1;
      }
    };

    try {
      for (var frame = 1; frame <= 5; frame += 1) {
        cursor.value = frame;
        await tester.pump();
      }
    } finally {
      // Unset inside the body: the binding checks its debug switches before
      // a tear-down would run.
      debugOnProfilePaint = null;
    }

    expect(
      counterPaints,
      greaterThanOrEqualTo(5),
      reason: 'fixture: the counter was painted at every tick',
    );
    expect(
      sliderPaints,
      0,
      reason: '↩️the bar was painted again whole at every tick, the zoom '
          'slider with the counter',
    );
  });
}
