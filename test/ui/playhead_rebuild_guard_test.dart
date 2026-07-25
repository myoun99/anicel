import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/app_language.dart';
import 'package:quick_animaker_v2/src/models/playback_quality.dart';
import 'package:quick_animaker_v2/src/ui/playback/playback_transport_controls.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_section_policy.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_orientation.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_panel.dart';
import 'package:quick_animaker_v2/src/ui/timeline_tab_host.dart';
import 'package:quick_animaker_v2/src/ui/timesheet_tab_host.dart';

/// R13-2 playhead rebuild guards: committed seeks and cursor moves must
/// not rebuild what they don't change — measured on device as the
/// frame-flip hitch (the timesheet repainted the whole B4 sheet per
/// cursor move; the timeline rebuilt its whole transport + action toolbar
/// per seek).
void main() {
  testWidgets('a committed seek inside the same enablement state does NOT '
      'rebuild the timeline toolbar', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineTabHost(
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
    );
    await tester.pumpAndSettle();

    final before = tester.widget(find.byType(TimelineActionToolbar));

    // Frames 2 and 3 are both empty cells on the default project — the
    // toolbar's enablement token is identical, so the seek must be
    // swallowed whole.
    session.selectFrameIndex(2);
    await tester.pump();
    session.selectFrameIndex(3);
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isTrue,
      reason: 'same-enablement seeks must not reconstruct the toolbar',
    );

    // A seek that CHANGES what the buttons can do rebuilds once: landing
    // on a drawn cel flips the cell-sensitive enablements.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(3);
    await tester.pump();
    session.selectFrameIndex(0);
    await tester.pump();
    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isFalse,
      reason: 'enablement changes still refresh the toolbar',
    );

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

  Future<EditorSessionManager> pumpNotifyWrappedHost(WidgetTester tester) async {
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
    return session;
  }

  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('a session notify that changes nothing the toolbar shows does '
      'NOT reconstruct it (notify gate)', (tester) async {
    final session = await pumpNotifyWrappedHost(tester);
    final before = tester.widget(find.byType(TimelineActionToolbar));

    // Toggling another layer's visibility fires a full session notify (the
    // host rebuilds) but changes no value the toolbar renders.
    final other = session.layers
        .firstWhere((layer) => layer.id != session.activeLayerId)
        .id;
    session.toggleLayerVisibility(other);
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isTrue,
      reason: 'a notify that changes no toolbar value must reuse the toolbar',
    );
    await drainWarming(tester);
  });

  testWidgets('each shown value change reconstructs the toolbar across a '
      'notify (completeness)', (tester) async {
    final session = await pumpNotifyWrappedHost(tester);

    Object toolbar() => tester.widget(find.byType(TimelineActionToolbar));
    Object transport() => tester.widget(find.byType(PlaybackTransportControls));

    // 1. The project frame-rate dropdown prints its label.
    var before = toolbar();
    final oldRate = session.projectFrameRate;
    session.setProjectFps(session.projectFps + 5);
    await tester.pump();
    expect(session.projectFrameRate == oldRate, isFalse,
        reason: 'sanity: the fps mutation must actually change the rate');
    expect(identical(toolbar(), before), isFalse,
        reason: 'the fps label change must refresh the toolbar');

    // 2. The audio sample-rate dropdown prints its label.
    before = toolbar();
    session.setProjectAudioSampleRate(
      session.projectAudioSampleRate == 48000 ? 44100 : 48000,
    );
    await tester.pump();
    expect(identical(toolbar(), before), isFalse,
        reason: 'the sample-rate label change must refresh the toolbar');

    // 3. Playback quality is a transport value-prop (its clock is live via
    // AnimatedBuilder, but this is read as a plain value). It belongs to the
    // TRANSPORT group alone — the action toolbar must ride through it.
    before = transport();
    var actionsBefore = toolbar();
    session.setPlaybackQuality(
      session.playbackQuality == PlaybackQuality.full
          ? PlaybackQuality.half
          : PlaybackQuality.full,
    );
    await tester.pump();
    expect(identical(transport(), before), isFalse,
        reason: 'a playback-quality change must refresh the transport');
    expect(identical(toolbar(), actionsBefore), isTrue,
        reason: 'the action toolbar shows no playback quality — it must not '
            'be dragged along by the transport group');

    // 4. Landing a drawing flips the cell-sensitive enablements (which the
    // comma buttons and the Add button read through their can* getters).
    // The frequent case, and the reason the groups are split: the transport
    // shows none of it and must survive.
    before = toolbar();
    final transportBefore = transport();
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pump();
    expect(identical(toolbar(), before), isFalse,
        reason: 'an enablement change must refresh the toolbar');
    expect(identical(transport(), transportBefore), isTrue,
        reason: 'an enablement change must NOT rebuild the transport');

    // 5. Moving the active layer refreshes it. HONEST SCOPE: this does not
    // isolate `activeLayer.kind` — a layer switch moves the can* getters
    // with it, so the token would change even without the kind entry (a
    // mutation run proved exactly that). There is no API that changes a
    // layer's kind in place, so the kind entry stays unpinned by design.
    session.addLayerOfKind(LayerKind.se);
    final seLayer = session.layers.firstWhere((l) => l.kind == LayerKind.se);
    session.selectLayer(seLayer.id);
    await tester.pump();
    expect(session.activeLayer?.kind, LayerKind.se,
        reason: 'sanity: the SE layer must be active');
    before = toolbar();
    final drawingLayer = session.layers.firstWhere(
      (l) => l.kind == LayerKind.animation,
    );
    session.selectLayer(drawingLayer.id);
    await tester.pump();
    expect(identical(toolbar(), before), isFalse,
        reason: 'an active-layer change must refresh the toolbar');

    // 6. The transport prints its mic tooltips in the PROGRAM language, and
    // a language switch fires no session notify at all — the gate has to be
    // listening to it directly. Both groups print language, so both refresh.
    before = toolbar();
    final transportBeforeLanguage = transport();
    session.setLanguageSettings(
      AppLanguageSettings(
        programLanguage:
            session.languageSettings.value.programLanguage == AppLanguage.ko
            ? AppLanguage.en
            : AppLanguage.ko,
      ),
    );
    await tester.pump();
    expect(identical(toolbar(), before), isFalse,
        reason: 'a language change must refresh the toolbar');
    expect(identical(transport(), transportBeforeLanguage), isFalse,
        reason: 'a language change must refresh the transport too');

    await drainWarming(tester);
  });

  testWidgets('a section fold refreshes the toolbar (its flyout checkmarks '
      'read hiddenSections)', (tester) async {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    var hidden = <TimelineSection>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListenableBuilder(
              listenable: session,
              builder: (context, _) => TimelineTabHost(
                session: session,
                orientation: TimelineOrientation.horizontal,
                onOrientationChanged: (_) {},
                pixelsPerFrame: 24,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
                hiddenSections: hidden,
                onToggleSection: (section) => setState(() {
                  hidden = hidden.contains(section)
                      ? (hidden.toSet()..remove(section))
                      : (hidden.toSet()..add(section));
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.widget(find.byType(TimelineActionToolbar));
    tester
        .widget<TimelineActionToolbar>(find.byType(TimelineActionToolbar))
        .onToggleSection!(TimelineSection.se);
    await tester.pump();

    expect(hidden, contains(TimelineSection.se), reason: 'sanity: it folded');
    expect(
      identical(tester.widget(find.byType(TimelineActionToolbar)), before),
      isFalse,
      reason: 'a hiddenSections change must refresh the toolbar',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a zoom step through the listenable reaches the panel but the '
      'toolbar instance SURVIVES it (UI-R6 #4 zoom scoping)', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineTabHost(
            session: session,
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: zoom.value,
            pixelsPerFrameListenable: zoom,
            onPixelsPerFrameChanged: (value) => zoom.value = value,
            showSeconds: false,
            onShowSecondsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TimelinePanel>(find.byType(TimelinePanel)).pixelsPerFrame,
      24,
    );
    final toolbarBefore = tester.widget(find.byType(TimelineActionToolbar));
    final legendBefore = tester.widget(
      find.byType(TimelineLayerControlsHeader),
    );
    final drawingRowBefore = tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .firstWhere((row) => row.layer.kind == LayerKind.animation);

    // A zoom step lands WITHOUT any host/workspace rebuild…
    zoom.value = 48;
    await tester.pump();

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
    // The rail's Material-heavy pieces are memo-gated too (UI-R7 #1):
    // the legend header and the repository-identity control rows come
    // back as the IDENTICAL instances across a zoom step.
    expect(
      identical(
        tester.widget(find.byType(TimelineLayerControlsHeader)),
        legendBefore,
      ),
      isTrue,
      reason: 'zoom steps must not reconstruct the legend header',
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
            continuous: false,
            onContinuousChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paintFinder = find.byKey(
      const ValueKey<String>('timesheet-document-paint'),
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
