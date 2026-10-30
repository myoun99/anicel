import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/comma_button.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/session/tab_rail_wiring.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart' show PillNameCell;

import '../helpers/home_page_probes.dart' show isActionButtonEnabled;
import '../helpers/pill_row_clipboard.dart';
import '../helpers/timeline_host.dart';

/// R13-2 playhead rebuild guards: committed seeks and cursor moves must
/// not rebuild what they don't change — measured on device as the
/// frame-flip hitch (the timesheet repainted the whole B4 sheet per
/// cursor move; the timeline rebuilt its whole transport + action toolbar
/// per seek).
///
/// ↩️The toolbar's half held the BAR's instance: it was cached on a token
/// of every gate it showed, so "a shown value moved" was "the bar was built
/// again". Each group on the bar hears its own gates now
/// (a-gate-rebuilds-the-whole-toolbar, 2026-10-24) and the bar stays the
/// same widget, so these hold its CONTROLS — a value that moved builds the
/// controls that show it again, and one that did not builds none.
void main() {
  /// Every control on the timeline's bar, as built.
  List<Widget> barControls(WidgetTester tester) => tester
      .widgetList(
        find.descendant(
          of: find.byType(TimelineActionToolbar),
          matching: find.byWidgetPredicate(
            (w) => w is AppIconButton || w is PillNameCell || w is CommaButton,
          ),
        ),
      )
      .toList();

  /// Whether any control in [before] was built again by now.
  bool builtAgain(WidgetTester tester, List<Widget> before) {
    final after = barControls(tester);
    return after.length != before.length ||
        [
          for (var i = 0; i < after.length; i++)
            !identical(after[i], before[i]),
        ].any((moved) => moved);
  }

  testWidgets('a committed seek inside the same enablement state does NOT '
      'rebuild the timeline toolbar', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await pumpTimelineHostOn(
      tester,
      session,
      surface: const Size(800, 600),
      pixelsPerFrame: 24,
    );

    final before = tester.widget(find.byType(TimelineActionToolbar));
    var controls = barControls(tester);

    // Frames 2 and 3 are both empty cells on the default project — every
    // gate on the bar answers alike, so the seek must be swallowed whole.
    session.selectFrameIndex(2);
    await tester.pump();
    session.selectFrameIndex(3);
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isTrue,
      reason: 'same-enablement seeks must not reconstruct the toolbar',
    );
    expect(
      builtAgain(tester, controls),
      isFalse,
      reason: '…nor any control on it',
    );

    // A seek that CHANGES what the buttons can do rebuilds them: landing
    // on a drawn cel flips the cell-sensitive enablements.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(3);
    await tester.pump();
    controls = barControls(tester);
    session.selectFrameIndex(0);
    await tester.pump();
    expect(
      builtAgain(tester, controls),
      isTrue,
      reason: 'enablement changes still refresh the controls that show them',
    );
    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isTrue,
      reason: 'and only those — the bar around them stays',
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a seek onto a block lights 자동 이름 지정, and one onto an empty '
      'cell dims it — its group hears the seek (I-18)', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await pumpTimelineHostOn(
      tester,
      session,
      surface: const Size(800, 600),
      pixelsPerFrame: 24,
    );
    const button = ValueKey<String>('shared-auto-name-button');

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(3);
    await tester.pump();
    expect(
      await isActionButtonEnabled(tester, button),
      isFalse,
      reason: 'an empty cell holds no block',
    );

    session.selectFrameIndex(0);
    await tester.pump();
    expect(
      await isActionButtonEnabled(tester, button),
      isTrue,
      reason: 'the seek landed on a block',
    );
    // ⚠️HONEST SCOPE: this seek flips the other cell gates with it (delete,
    // copy …), so it proves the BUTTON follows the seek — not that its own
    // token entry is what carried it there.

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  // --- Notify gate (scoped-notify round) ------------------------------------
  //
  // The seek gate above rides frameSeekCommitted; a SESSION notify instead
  // rebuilds the whole host (the app wraps it in PanelAwareListenableBuilder).
  // These pump the host under that wrapper so the notify path is real, then
  // assert the toolbar is reconstructed EXACTLY when a value it shows changes.

  Future<EditorSessionManager> pumpNotifyWrappedHost(WidgetTester tester) =>
      pumpTimelineHost(
        tester,
        createDefaultProject(),
        surface: const Size(800, 600),
        pixelsPerFrame: 24,
      );

  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('a session notify that changes nothing the toolbar shows does '
      'NOT reconstruct it (notify gate)', (tester) async {
    final session = await pumpNotifyWrappedHost(tester);
    final before = tester.widget(find.byType(TimelineActionToolbar));
    final controls = barControls(tester);

    // Toggling another layer's visibility fires a full session notify (the
    // host rebuilds) but changes no value the toolbar renders.
    final other = session.layers
        .firstWhere((layer) => layer.id != session.activeLayerId)
        .id;
    session.layerSwitches.toggleLayerVisibility(other);
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isTrue,
      reason: 'a notify that changes no toolbar value must reuse the toolbar',
    );
    expect(
      builtAgain(tester, controls),
      isFalse,
      reason: '…and every group on it, each hearing the notify itself',
    );
    await drainWarming(tester);
  });

  testWidgets('each shown value change rebuilds what shows it across a '
      'notify (completeness)', (tester) async {
    final session = await pumpNotifyWrappedHost(tester);

    // ⛔The TRANSPORT is not on this bar any more (2026-08-10) — it rides the
    // 문턱, mounted by the workspace — so the two-group half of this guard
    // went with it. What replaces it is the INVERSE guard: the three values
    // that left must no longer be able to reconstruct the toolbar.
    //
    // 1-3. fps, audio sample rate and the playback mode (the playback
    // quality, until 2026-10-08) are ENTRIES of the settings pill now, and a
    // flyout builds its entries at OPEN time — so none of them is a value
    // this bar renders. A token that still carried them would reconstruct
    // ~20 buttons for a menu nobody has open.
    var before = barControls(tester);
    final oldRate = session.projectSettings.projectFrameRate;
    session.projectSettings.setProjectFps(session.projectSettings.projectFps + 5);
    session.projectAudio.setProjectAudioSampleRate(
      session.projectAudio.projectAudioSampleRate == 48000 ? 44100 : 48000,
    );
    session.playbackRig.setPlaybackMode(
      session.playbackRig.playbackMode == PlaybackMode.skipFrames
          ? PlaybackMode.everyPicture
          : PlaybackMode.skipFrames,
    );
    await tester.pump();
    expect(session.projectSettings.projectFrameRate == oldRate, isFalse,
        reason: 'sanity: the fps mutation must actually change the rate');
    expect(builtAgain(tester, before), isFalse,
        reason: 'the toolbar prints no project axis and no playback mode '
            '— they moved to the settings pill and must not drag it along');

    // 4. Landing a drawing flips the cell-sensitive enablements (which the
    // comma buttons and the Add button read through their can* getters).
    // The frequent case, and the one the gate exists for.
    before = barControls(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pump();
    expect(builtAgain(tester, before), isTrue,
        reason: 'an enablement change must refresh the toolbar');

    // 5. Moving the active layer refreshes it. HONEST SCOPE: this does not
    // isolate `activeLayer.kind` — a layer switch moves the can* getters
    // with it, so the token would change even without the kind entry (a
    // mutation run proved exactly that). There is no API that changes a
    // layer's kind in place, so the kind entry stays unpinned by design.
    session.layerStack.addLayerOfKind(LayerKind.se);
    final seLayer = session.layers.firstWhere((l) => l.kind == LayerKind.se);
    session.selectLayer(seLayer.id);
    await tester.pump();
    expect(session.activeLayer?.kind, LayerKind.se,
        reason: 'sanity: the SE layer must be active');
    before = barControls(tester);
    final drawingLayer = session.layers.firstWhere(
      (l) => l.kind == LayerKind.animation,
    );
    session.selectLayer(drawingLayer.id);
    await tester.pump();
    expect(builtAgain(tester, before), isTrue,
        reason: 'an active-layer change must refresh the toolbar');

    // 6. Every pill's NAME CELL prints a word now (컷 · 레이어 · 프레임), and
    // a language switch fires no session notify at all — the groups have
    // to be listening to it directly, the frame pill's name included.
    final cells = tester.widgetList(find.byType(PillNameCell)).toList();
    // …and every button's tooltip, the push/pull pair's among them.
    final onTheBar = find.descendant(
      of: find.byType(TimelineActionToolbar),
      matching: find.byType(AppIconButton),
    );
    final buttons = tester.widgetList(onTheBar).toList();
    session.setLanguageSettings(
      AppLanguageSettings(
        programLanguage:
            session.languageSettings.value.programLanguage == AppLanguage.ko
            ? AppLanguage.en
            : AppLanguage.ko,
      ),
    );
    await tester.pump();
    final printed = tester.widgetList(find.byType(PillNameCell)).toList();
    expect(printed, hasLength(cells.length), reason: 'sanity');
    expect(
      [for (var i = 0; i < cells.length; i++) identical(printed[i], cells[i])],
      everyElement(isFalse),
      reason: 'a language change must reprint every name cell',
    );
    final reworded = tester.widgetList(onTheBar).toList();
    expect(reworded, hasLength(buttons.length), reason: 'sanity');
    expect(
      [
        for (var i = 0; i < buttons.length; i++)
          identical(reworded[i], buttons[i]),
      ],
      everyElement(isFalse),
      reason: 'and every tooltip',
    );

    // 7. The layer pill promoted DELETE out of its menu, so its enablement
    // is a value the bar renders — the completeness contract's newest entry.
    session.selectLayer(session.layers.first.id);
    await tester.pump();
    before = barControls(tester);
    while (session.layerVerbs.canDeleteActiveLayer) {
      session.layerVerbs.deleteActiveLayer();
      await tester.pump();
    }
    expect(builtAgain(tester, before), isTrue,
        reason: 'the delete button losing its enablement must refresh the bar');

    await drainWarming(tester);
  });

  testWidgets('drawing a BAND refreshes the toolbar — the active-row verbs '
      'read it, and it fires on its own notifier with no session notify', (
    tester,
  ) async {
    final session = await pumpNotifyWrappedHost(tester);

    // Two drawing rows: row A active with a block, the band swept over B.
    final rowA = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.layerStack.addLayerOfKind(LayerKind.animation);
    final rowB = session.activeLayer!.id;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    await tester.pump();

    expect(session.clipboard.canCutRunAtCurrentFrame, isTrue, reason: 'sanity');
    final beforeBand = barControls(tester);

    session.updateFrameRangeSelectionDrag(
      layerId: rowB,
      anchorIndex: 0,
      headIndex: 1,
    );
    await tester.pump();

    expect(
      session.clipboard.canCutRunAtCurrentFrame,
      isFalse,
      reason: 'sanity: the band names another row, so the verb stood down',
    );
    expect(
      builtAgain(tester, beforeBand),
      isTrue,
      reason: 'the gates went dark, so the BUTTONS must too — enforcing a '
          'standdown while the bar keeps its old enablement leaves exactly '
          'the dead lit control the standdown exists to remove',
    );

    await drainWarming(tester);
  });

  testWidgets('a band swept on the STORYBOARD refreshes it too — the same '
      'claim on the track\'s axis, on a notifier of its own (F-281)', (
    tester,
  ) async {
    final session = await pumpNotifyWrappedHost(tester);

    final row = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(row);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pump();
    expect(session.clipboard.canCutRunAtCurrentFrame, isTrue, reason: 'sanity');
    final beforeBand = barControls(tester);

    session.rangeSelections.updateTrackRowRangeSelectionByFrame(
      layerId: session.activeTrack.seLayers.first.id,
      anchorGlobalFrame: 0,
      headGlobalFrame: 1,
    );
    await tester.pump();

    expect(
      session.clipboard.canCutRunAtCurrentFrame,
      isFalse,
      reason: 'sanity: the band names an S row, which this press would miss',
    );
    expect(
      builtAgain(tester, beforeBand),
      isTrue,
      reason: 'the gates went dark with no seek, no stand and no notify — '
          'only the track band\'s own notifier says so',
    );

    await drainWarming(tester);
  });

  testWidgets('a section fold refreshes the toolbar (its flyout checkmarks '
      'read hiddenSections)', (tester) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(800, 600),
      pixelsPerFrame: 24,
    );

    final before = tester.widget(find.byType(TimelineActionToolbar));
    // The controls on every pill but the layer pill, whose menu checks read
    // the sections.
    List<Widget> notTheLayerPill() => [
      for (final element in find
          .descendant(
            of: find.byType(TimelineActionToolbar),
            matching: find.byWidgetPredicate(
              (w) => w is AppIconButton || w is CommaButton,
            ),
          )
          .evaluate())
        if (find
            .ancestor(
              of: find.byWidget(element.widget),
              matching: find.byKey(
                const ValueKey<String>('timeline-toolbar-layer-group'),
              ),
            )
            .evaluate()
            .isEmpty)
          element.widget,
    ];
    final others = notTheLayerPill();
    tester
        .widget<TimelineActionToolbar>(find.byType(TimelineActionToolbar))
        .onToggleSection!(TimelineSection.se);
    await tester.pump();

    expect(
      session.railView.hiddenSections.value,
      contains(TimelineSection.se),
      reason: 'sanity: it folded',
    );
    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isFalse,
      reason: 'a hiddenSections change must refresh the toolbar',
    );
    final after = notTheLayerPill();
    expect(after, hasLength(others.length), reason: 'sanity');
    expect(
      [for (var i = 0; i < after.length; i++) identical(after[i], others[i])],
      everyElement(isTrue),
      reason: 'the bar built again, and each group kept what it had built '
          'while its own gates held',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  /// The timeline tab over [session], zoomed by [zoom] — the zoom arrives
  /// through the listenable alone, with no host rebuild.
  Future<void> pumpZoomableTimeline(
    WidgetTester tester,
    EditorSessionManager session,
    ValueNotifier<double> zoom,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineTabHost(
            session: session,
            rail: TabRailWiring.of(session),
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: zoom.value,
            pixelsPerFrameListenable: zoom,
            onPixelsPerFrameChanged: (value) => zoom.value = value,
            rulerView: FrameRulerView.frames,
            onRulerViewChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a zoom step through the listenable reaches the panel but the '
      'toolbar instance SURVIVES it (UI-R6 #4 zoom scoping)', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);

    await pumpZoomableTimeline(tester, session, zoom);

    expect(
      tester.widget<TimelinePanel>(find.byType(TimelinePanel)).pixelsPerFrame,
      24,
    );
    final toolbarBefore = tester.widget(find.byType(TimelineActionToolbar));
    expect(
      find.byType(TimelineLayerControlsHeader),
      findsOneWidget,
      reason: 'premise: the legend stands',
    );
    final drawingRowBefore = tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .firstWhere((row) => row.layer.kind == LayerKind.animation);

    // A zoom step lands WITHOUT any host/workspace rebuild…
    final inLegend = <Type>[];
    debugOnRebuildDirtyWidget = (element, _) =>
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is! TimelineLayerControlsHeader) {
            return true;
          }
          inLegend.add(element.widget.runtimeType);
          return false;
        });
    zoom.value = 48;
    try {
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }

    expect(
      tester.widget<TimelinePanel>(find.byType(TimelinePanel)).pixelsPerFrame,
      48,
      reason: 'the panel follows the zoom listenable',
    );
    // …and the hoisted toolbar widget is the IDENTICAL instance, so its
    // transport + ~25 buttons skip rebuilding on every zoom step.
    expect(
      identical(
        tester.widget(find.byType(TimelineActionToolbar)),
        toolbarBefore,
      ),
      isTrue,
      reason: 'zoom steps must not reconstruct the toolbar',
    );
    // The rail's Material-heavy pieces are kept too (UI-R7 #1): nothing
    // of the legend header is built again across a zoom step — it keeps
    // what it built while what it shows is the same (I-57, 10-14) — and
    // the repository-identity control rows come back as the IDENTICAL
    // instances.
    expect(
      inLegend,
      isEmpty,
      reason: 'zoom steps must not build the legend header again',
    );
    final drawingRowAfter = tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .firstWhere((row) => row.layer.kind == LayerKind.animation);
    expect(
      identical(drawingRowAfter, drawingRowBefore),
      isTrue,
      reason: 'zoom steps must not reconstruct the drawing rail row',
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('…and a LINKED row survives it too: its partners are a fresh '
      'list every build, compared by what it holds', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    linkDuplicateActiveRow(session);
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);
    await pumpZoomableTimeline(tester, session, zoom);

    TimelineLayerControlsRow linkedRow() => tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .firstWhere((row) => row.linkPartners.isNotEmpty);
    final before = linkedRow();

    zoom.value = 48;
    await tester.pump();

    expect(
      identical(linkedRow(), before),
      isTrue,
      reason: 'a zoom step must not reconstruct a linked rail row',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a cursor move repaints only the timesheet playhead overlay '
      '— never the sheet painter', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimesheetTabHost(
            session: session,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paintFinder = find.byKey(
      const ValueKey<String>('timesheet-content-paint'),
    );
    expect(paintFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('timesheet-playhead-overlay')),
      findsOneWidget,
    );
    final before = tester.widget(paintFinder);

    // Cursor moves and committed seeks within the same page: the sheet
    // paint widget must remain the IDENTICAL instance (repaints happen
    // on the overlay's own layer).
    session.editingFrameCursor.value = 3;
    await tester.pump();
    session.selectFrameIndex(5);
    await tester.pump();

    expect(
      identical(tester.widget(paintFinder), before),
      isTrue,
      reason: 'playhead moves must not rebuild the sheet painter',
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
