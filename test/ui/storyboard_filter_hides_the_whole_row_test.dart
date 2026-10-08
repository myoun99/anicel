import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show seLayerIdForTrack;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowDragTarget;
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

/// 🚨storyboard-filter-leaves-the-strips (found 2026-09-25, measured): the
/// legend's filter hid a storyboard row on the RAIL only. Its strip stayed,
/// so every row under it parted from its label by one row — S1's name at 94
/// over S1's strip at 124, the V row's at 124 over its strip at 154.
///
/// A filter hides the ROW, as the timeline's does: the rail's label, the
/// strip beside it, and the one table the bands, the sheet, the
/// select-drag, the standing ring and the swipe read. So the oracle is the
/// same sentence for every row left: its label and its strip are one row.
void main() {
  Future<({EditorSessionManager session, String track})> pumpFiltered(
    WidgetTester tester, {
    required TimelineRowFilter rowFilter,
    void Function(EditorSessionManager session)? arrange,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final track = session.selectedTrackId.value;
    // Stand on S1: a filter never hides the row you stand on, so S1 stays
    // and S2 — which fails the mark chip below — is the row that goes.
    session.selectRow(
      LayerRowAddress(seLayerIdForTrack(session.selectedTrackId, 1)),
    );
    arrange?.call(session);
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
              thumbnails: null,
              rowFilter: rowFilter,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (session: session, track: track);
  }

  Finder keyed(String key) => find.byKey(ValueKey<String>(key));

  void expectOneRow(WidgetTester tester, String label, String strip) {
    // SHOWN, said as an expectation: measuring a row that is not there
    // throws out of the finder, which reads as a broken test rather than as
    // the row having been hidden.
    expect(keyed(label), findsOneWidget, reason: 'the row\'s label is shown');
    expect(keyed(strip), findsOneWidget, reason: 'and its strip beside it');
    final labelRect = tester.getRect(keyed(label));
    final stripRect = tester.getRect(keyed(strip));
    expect(stripRect.top, closeTo(labelRect.top, 0.5), reason: label);
    expect(stripRect.height, closeTo(labelRect.height, 0.5), reason: label);
  }

  final markFilter = TimelineRowFilter(
    markColors: {const LayerMark(process: LayerProcess.layout)},
  );

  testWidgets('a row the mark chip hides leaves its strip too — every row '
      'left is one row', (tester) async {
    final shown = await pumpFiltered(tester, rowFilter: markFilter);
    final track = shown.track;

    expect(keyed('storyboard-se-label-$track-2'), findsNothing);
    expect(
      keyed('storyboard-se-row-0-2'),
      findsNothing,
      reason: 'the filter hides the ROW, its strip with it',
    );
    expectOneRow(
      tester,
      'storyboard-transition-label-$track',
      'storyboard-transition-row-$track',
    );
    expectOneRow(tester, 'storyboard-se-label-$track-1', 'storyboard-se-row-0-1');
    expectOneRow(
      tester,
      'storyboard-track-label-row-$track',
      'storyboard-track-row-$track',
    );
  });

  testWidgets('the V row the fx chip hides leaves its strip too', (
    tester,
  ) async {
    final shown = await pumpFiltered(
      tester,
      rowFilter: const TimelineRowFilter(fxOnly: true),
      arrange: (session) =>
          session.effectsAndFx.toggleTrackFx(session.selectedTrackId),
    );
    final track = shown.track;

    expect(keyed('storyboard-track-label-row-$track'), findsNothing);
    expect(
      keyed('storyboard-track-row-$track'),
      findsNothing,
      reason: 'the filter hides the ROW, its strip with it',
    );
    expectOneRow(tester, 'storyboard-se-label-$track-1', 'storyboard-se-row-0-1');
  });

  testWidgets('a swipe down past the last row shown paints nothing it '
      'cannot see — the hidden V row is not in the walk', (tester) async {
    // ↩️The stroke ran down the EYE column and the pin was the hidden V
    // row's cut eye, until that eye left the head (I-73, 2026-10-08). The
    // fx column is the one a V row still answers on, so the stroke runs
    // down that — and it has to be an ON stroke, the one that would light
    // the very switch that hid the row: S1 starts with its fx off.
    final shown = await pumpFiltered(
      tester,
      rowFilter: const TimelineRowFilter(fxOnly: true),
      arrange: (session) {
        session.effectsAndFx.toggleTrackFx(session.selectedTrackId);
        session.effectsAndFx.toggleLayerFx(
          seLayerIdForTrack(session.selectedTrackId, 1),
        );
      },
    );
    final session = shown.session;
    final layerId = seLayerIdForTrack(session.selectedTrackId, 1);
    LayerFxState s1Fx() => session.effectsAndFx.layerFxState(layerId);
    LayerFxState trackFx() =>
        session.effectsAndFx.trackFxState(session.selectedTrackId);
    expect(
      [s1Fx(), trackFx()],
      [LayerFxState.off, LayerFxState.off],
      reason: 'the premise: both switches down, the V row hidden for it',
    );
    expect(keyed('storyboard-track-label-row-${shown.track}'), findsNothing);

    // From S1's fx switch — the last row with a switch the rail shows —
    // down through where the hidden V row would have stood.
    final from = tester.getCenter(keyed('storyboard-layer-fx-$layerId'));
    final gesture = await tester.startGesture(from);
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(from + Offset(0, step * 12.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      s1Fx(),
      LayerFxState.on,
      reason: 'LIVENESS — the press lit the row it started on',
    );
    expect(
      trackFx(),
      LayerFxState.off,
      reason: 'the V row is hidden, so no stroke reaches its fx switch',
    );
  });

  testWidgets('the row-order drag counts the rows the rail SHOWS — a hidden '
      'row is not a seat', (tester) async {
    // The timeline's display rows leave a filtered row out, and the model
    // insertion is inferred from the two lists; the storyboard's S drag
    // handed in the track's whole list, so S1 stood one seat below a row
    // nobody could see.
    Finder dragOf(String track) => find.ancestor(
      of: keyed('storyboard-se-label-$track-1'),
      matching: find.byType(LayerRowDragTarget),
    );

    final plain = await pumpFiltered(tester, rowFilter: TimelineRowFilter.none);
    final unfiltered = tester.widget<LayerRowDragTarget>(
      dragOf(plain.track).first,
    );
    expect(
      unfiltered.slotBefore,
      1,
      reason: 'control: with S2 shown above it, S1 is the second seat',
    );

    final shown = await pumpFiltered(tester, rowFilter: markFilter);
    final filtered = tester.widget<LayerRowDragTarget>(
      dragOf(shown.track).first,
    );
    expect(filtered.slotBefore, 0, reason: 'S2 is hidden; S1 is the first');
    expect(filtered.isLastRow, isTrue);
  });

  testWidgets('the ring stands on the row the rail draws, with a row hidden '
      'above it', (tester) async {
    final shown = await pumpFiltered(tester, rowFilter: markFilter);

    final ring = tester.getRect(keyed('storyboard-standing-cell'));
    final row = tester.getRect(keyed('storyboard-se-row-0-1'));
    expect(ring.top, closeTo(row.top, 0.5));
    expect(ring.height, closeTo(row.height, 0.5));
    expect(
      tester.getRect(keyed('storyboard-se-label-${shown.track}-1')).top,
      closeTo(row.top, 0.5),
      reason: 'and the label it belongs to stands beside it',
    );
  });

  // I-73: the conte row is a row of this rail, and the filter judges it as
  // it judges every row — on the facets it carries here: its kind, and the
  // colour label its blocks wear.
  group('the conte row', () {
    const kindFilter = TimelineRowFilter(kinds: {LayerKind.animation});

    void expectConteRowHidden(String track) {
      expect(keyed('storyboard-conte-label-$track'), findsNothing);
      expect(
        keyed('storyboard-conte-row-$track'),
        findsNothing,
        reason: 'the filter hides the ROW, its strip with it',
      );
    }

    void expectConteRowShown(WidgetTester tester, String track) => expectOneRow(
      tester,
      'storyboard-conte-label-$track',
      'storyboard-conte-row-$track',
    );

    testWidgets('⛔전제: unfiltered, it is one row under the V row', (
      tester,
    ) async {
      final shown = await pumpFiltered(
        tester,
        rowFilter: TimelineRowFilter.none,
      );
      expectConteRowShown(tester, shown.track);
      expect(
        tester.getRect(keyed('storyboard-conte-row-${shown.track}')).top,
        closeTo(
          tester.getRect(keyed('storyboard-track-row-${shown.track}')).bottom,
          0.5,
        ),
      );
    });

    testWidgets('the kind chip hides it, strip and all', (tester) async {
      final shown = await pumpFiltered(tester, rowFilter: kindFilter);

      expectConteRowHidden(shown.track);
      expectOneRow(
        tester,
        'storyboard-track-label-row-${shown.track}',
        'storyboard-track-row-${shown.track}',
      );
    });

    testWidgets('…and it stays while it is the row you stand on', (
      tester,
    ) async {
      final shown = await pumpFiltered(
        tester,
        rowFilter: kindFilter,
        arrange: (session) => session.selectRow(
          LayerRowAddress(trackConteRowId(session.selectedTrackId)),
        ),
      );
      expectConteRowShown(tester, shown.track);
    });

    testWidgets('the mark chip finds no label on a row no conte layer has '
        'coloured, and leaves it', (tester) async {
      final shown = await pumpFiltered(tester, rowFilter: markFilter);
      expectConteRowShown(tester, shown.track);
    });

    testWidgets('…and hides it by the label its blocks wear', (tester) async {
      final shown = await pumpFiltered(
        tester,
        rowFilter: markFilter,
        arrange: (session) =>
            session.layerStack.addLayerOfKind(LayerKind.storyboard),
      );
      expectConteRowHidden(shown.track);
    });

    testWidgets('with the V row hidden above it, it is still one row', (
      tester,
    ) async {
      final shown = await pumpFiltered(
        tester,
        rowFilter: const TimelineRowFilter(fxOnly: true),
        arrange: (session) =>
            session.effectsAndFx.toggleTrackFx(session.selectedTrackId),
      );
      expect(
        keyed('storyboard-track-row-${shown.track}'),
        findsNothing,
        reason: '⛔전제: the fx chip hid the V row',
      );
      expectConteRowShown(tester, shown.track);
    });
  });
}
