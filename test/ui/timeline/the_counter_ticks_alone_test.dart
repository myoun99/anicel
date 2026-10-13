import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';

import '../../helpers/frame_census.dart';

/// The frame counter ticks with every frame played. A tick that keeps the
/// counter's width paints its line alone (I-57, 10-14 — [TickText]); one
/// that widens it moves the row, so the bar it stands on is one tick layer
/// ([TimelineCommandBar]) and what stands beside it there is moved, not
/// painted (playback-making-pictures-shakes-the-frames, 10-11).
void main() {
  RenderObject at(WidgetTester tester, String key) =>
      tester.renderObject(find.byKey(ValueKey<String>(key)));

  testWidgets('🚨a counter tick builds nothing and paints the counter\'s '
      'line alone', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(_bar(cursor));
    // The app's focus settles a frame after it is built.
    await tester.pumpAndSettle();
    final line = at(tester, 'timeline-local-frame-counter');

    for (var frame = 1; frame <= 5; frame += 1) {
      late bool linePainted;
      final ticked = await frameCensus(tester, () {
        cursor.value = frame;
        linePainted = line.debugNeedsPaint;
      });

      expect(linePainted, isTrue, reason: 'premise: the line heard it');
      expect(ticked.rebuilt, isEmpty);
      expect(
        ticked.painted,
        isEmpty,
        reason: '↩️the bar was painted again whole at every tick — 🔬72–78 '
            'render objects before the zoom stood on a layer of its own '
            '(10-11), 24 after it',
      );
    }
  });

  testWidgets('CONTROL: a tick that widens the counter paints the bar '
      'round it, and not the zoom', (tester) async {
    final cursor = ValueNotifier<int>(8);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(_bar(cursor));
    final line = at(tester, 'timeline-local-frame-counter');
    final slider = at(tester, 'timeline-zoom-slider');

    final frame = await frameCensus(tester, () => cursor.value = 9);

    expect(
      frame.painted.where((object) => !identical(object, line)),
      isNotEmpty,
      reason: '9 to 10 is a wider counter',
    );
    expect(
      frame.painted.any((object) => identical(object, slider)) ||
          paintedInside(frame.painted, slider),
      isFalse,
    );
  });

  testWidgets('🚨a counter tick re-describes its line alone, and a bar '
      'described again stops at the zoom beside it', (tester) async {
    final semantics = tester.ensureSemantics();
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(_bar(cursor));

    // A change marks the semantics of what changed, and the mark climbs to
    // the nearest boundary — whose share of the tree is walked again, down
    // to the boundaries under it.
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

    final line = at(tester, 'timeline-local-frame-counter');
    expect(
      boundaryOf(line),
      same(line),
      reason: '↩️a tick walked the bar\'s semantics, the cut\'s name and '
          'the counter\'s other line with it',
    );

    final bar = boundaryOf(at(tester, 'timeline-cut-name'));

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

    final zoom = underTheBar(at(tester, 'timeline-zoom-slider'));
    expect(
      underTheBar(at(tester, 'timeline-zoom-out-button')),
      same(zoom),
      reason: 'the slider and the buttons beside it are one boundary\'s',
    );
    expect(underTheBar(at(tester, 'timeline-zoom-in-button')), same(zoom));
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
