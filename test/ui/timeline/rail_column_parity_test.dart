import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show seLayerIdForTrack;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// R9 #22 — the rail's column skeleton, measured on the REAL widget tree.
///
/// Four surfaces used to hand-list the same columns and had drifted: the
/// storyboard's V row by 44px (no sheet slot, no mark slot, an 18px icon in
/// the 22px type slot), its S row by 6px (kind icon inside the name area),
/// the legend header by 4px (an 18px kind cell). The user saw it as "V트랙
/// 열 정렬이 안 맞는다".
///
/// The assertions compare the surfaces to EACH OTHER, never to the
/// constant — a drift cannot be papered over by editing
/// `layerRailLeadingWidth`. Every offset is taken relative to its own row's
/// left edge, so the surfaces need not share a scroll origin.
void main() {
  /// Where a row's content begins, relative to that row's own left edge.
  double insetOf(WidgetTester tester, Finder content, Finder row) {
    final contentLeft = tester.getTopLeft(content).dx;
    final rowLeft = tester.getTopLeft(row).dx;
    return contentLeft - rowLeft;
  }

  testWidgets('the storyboard rail\'s V row, S row and legend header all '
      'start their name at the same inset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
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

    final trackId = session.selectedTrackId;

    final vRow = find.byKey(
      ValueKey<String>('storyboard-track-label-row-${trackId.value}'),
    );
    final vName = find.byKey(
      ValueKey<String>('storyboard-track-label-${trackId.value}'),
    );
    final sRow = find.byKey(
      ValueKey<String>('storyboard-se-label-${trackId.value}-1'),
    );
    final legendHeading = find.byKey(const ValueKey<String>('legend-layer'));
    // Measured from the header's OUTER edge, exactly like the rows: the
    // header sits directly above them and both open with a 1px border, so
    // this is what "lines up on screen" means.
    final legendRow = find.byType(TimelineLayerControlsHeader).first;

    expect(vRow, findsOneWidget);
    expect(sRow, findsOneWidget);
    expect(legendHeading, findsOneWidget);

    // The S row's name is its SE layer's stored name; address the Text by
    // walking the row rather than by key (the label carries none).
    final sName = find.descendant(
      of: sRow,
      matching: find.byType(Text),
    );
    expect(sName, findsWidgets);

    final vInset = insetOf(tester, vName, vRow);
    final sInset = insetOf(tester, sName.first, sRow);
    final legendInset = insetOf(tester, legendHeading, legendRow);

    expect(
      vInset,
      sInset,
      reason:
          'the V row hand-listed its leading slots and came out 44px short; '
          'both rows must build from the shared skeleton',
    );
    expect(
      legendInset,
      vInset,
      reason:
          'the legend header sits over the rows it labels — its kind cell '
          'was 18 against the rows\' 22',
    );
  });

  testWidgets('the timeline rail starts its name at the SAME inset as the '
      'storyboard rail — one column skeleton, two panels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(initialProject: createDefaultProject());
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

    final layerId = session.activeLayerId!;
    final timelineInset = insetOf(
      tester,
      find.byKey(ValueKey<String>('timeline-layer-name-$layerId')),
      find.byKey(ValueKey<String>('timeline-layer-row-$layerId')),
    );

    // Now the same session in the storyboard, measured the same way.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
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

    final trackId = session.selectedTrackId;
    final storyboardInset = insetOf(
      tester,
      find.byKey(ValueKey<String>('storyboard-track-label-${trackId.value}')),
      find.byKey(
        ValueKey<String>('storyboard-track-label-row-${trackId.value}'),
      ),
    );

    expect(
      storyboardInset,
      timelineInset,
      reason:
          'this is the 44px the user reported: the two panels\' rails are '
          'the same table and must measure identically',
    );
  });

  testWidgets('the x-sheet column header carries the TYPE BUTTON — a kind '
      'icon, and an attach column\'s placement arrow (R9 S3)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.vertical,
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

    final layerId = session.activeLayerId!;
    expect(
      find.byKey(ValueKey<String>('xsheet-layer-kind-icon-$layerId')),
      findsOneWidget,
      reason: 'the x-sheet had no kind icon anywhere before R9',
    );

    // An attach row's column shows the placement arrow instead.
    session.addAttachedLayer(AttachedPlacement.above);
    await tester.pumpAndSettle();
    final attachId = session.activeLayerId!;
    expect(attachId, isNot(layerId));

    expect(
      find.byKey(ValueKey<String>('xsheet-layer-attach-arrow-$attachId')),
      findsOneWidget,
      reason:
          'the attach relationship was invisible on the sheet the user reads '
          'most',
    );
    expect(
      find.byKey(ValueKey<String>('xsheet-layer-kind-icon-$attachId')),
      findsOneWidget,
      reason: 'R10 R3: the arrow rides the SHEET slot, so the type cell says '
          'the kind on every column',
    );
    expect(
      find.byKey(ValueKey<String>('xsheet-layer-timesheet-$attachId')),
      findsNothing,
      reason: 'the x-sheet gate had no attach check — an attach column could '
          'be put ON the sheet in a state the rail can never undo',
    );
  });

  testWidgets('every SE slot on the storyboard rail shows the SE kind icon '
      'in the shared type slot, not inside the name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
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

    final trackId = session.selectedTrackId;
    expect(seLayerIdForTrack(trackId, 1), isNotNull);
    expect(
      find.byKey(
        ValueKey<String>('storyboard-layer-kind-icon-${trackId.value}-s1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('storyboard-layer-kind-icon-v-${trackId.value}'),
      ),
      findsOneWidget,
    );
  });
}
