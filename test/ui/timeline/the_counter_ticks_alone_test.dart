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
    await tester.pumpWidget(_bar(cursor));
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

  testWidgets('🚨a counter tick re-walks the semantics up to the bar, and '
      'the walk stops at the zoom beside it', (tester) async {
    final semantics = tester.ensureSemantics();
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(_bar(cursor));

    // A layout marks the semantics of what it laid out, and the mark climbs
    // to the nearest boundary — whose share of the tree is walked again,
    // down to the boundaries under it.
    bool isBoundary(RenderObject node) {
      final config = SemanticsConfiguration();
      // ignore: invalid_use_of_protected_member
      node.describeSemanticsConfiguration(config);
      return config.isSemanticBoundary;
    }

    RenderObject boundaryOf(RenderObject node) {
      var at = node;
      while (at.parent != null && !isBoundary(at)) {
        at = at.parent!;
      }
      return at;
    }

    RenderObject at(String key) =>
        tester.renderObject(find.byKey(ValueKey<String>(key)));

    final bar = boundaryOf(at('timeline-local-frame-counter'));

    /// The boundary [node] stands under right inside the bar's.
    RenderObject underTheBar(RenderObject node) {
      var under = boundaryOf(node);
      expect(
        under,
        isNot(same(bar)),
        reason: '↩️the zoom, its buttons and the orientation toggle were '
            'walked with the counter at every frame played — 50 render '
            'objects',
      );
      while (!identical(boundaryOf(under.parent!), bar)) {
        under = boundaryOf(under.parent!);
      }
      return under;
    }

    final zoom = underTheBar(at('timeline-zoom-slider'));
    expect(
      underTheBar(at('timeline-zoom-out-button')),
      same(zoom),
      reason: 'the slider and the buttons beside it are one boundary\'s',
    );
    expect(underTheBar(at('timeline-zoom-in-button')), same(zoom));
    // Inside the body: the binding checks its handles before a tear-down
    // would run.
    semantics.dispose();
  });
}

Widget _bar(ValueNotifier<int> cursor) => MaterialApp(
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
);
