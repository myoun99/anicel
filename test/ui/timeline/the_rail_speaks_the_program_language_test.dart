import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🚨rail-subject-tooltips (found building F-124, 2026-09-17): the rail's
/// shared controls carried their row as an English WORD and assembled their
/// tooltips from it — `'$subject blend mode'`, `'Hide $subject'`, `'Bypass
/// $subject FX'` — and F-37's scan skips every literal with a `$` in it, so
/// no count ever saw them. The rail row beside them hardcoded four more
/// pairs (timesheet, lanes, onion, fill reference) as ternaries, which the
/// scan reads one arm of at most.
///
/// 🧪**THE TEST DOES NOT NAME THE TRANSLATIONS** (F-124's shape): the same
/// control in the same arm must say two different things in two languages,
/// and neither may be the English that used to be nailed to the widget.
/// ⛔EVERY ARM: a ternary shows one of its two words at a time, and the
/// subject family's `mixed` arm is on screen only while a layer's effects
/// disagree.
void main() {
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  /// The shared controls in every arm, mounted bare — the words live in
  /// these widgets and nowhere else.
  Future<Map<String, String>> sharedControls(
    WidgetTester tester,
    AppLanguage language,
  ) async {
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
    Widget eye(String key, RailSubject subject, bool visible) =>
        LayerVisibilityToggleButton(
          keyValue: key,
          subject: subject,
          isVisible: visible,
          onToggle: () {},
        );
    Widget fx(String key, RailSubject subject, LayerFxState state) =>
        FxToggleButton(
          keyValue: key,
          subject: subject,
          state: state,
          onToggle: () {},
        );
    Widget blend(String key, {required bool isGroup}) => LayerBlendModeChip(
      keyValue: key,
      optionKeyPrefix: '$key-option-',
      blendMode: LayerBlendMode.normal,
      isGroup: isGroup,
      onBlendModeSelected: (_) {},
    );
    Widget sheet(String key, bool on) => LayerTimesheetToggleButton(
      keyPrefix: 'probe',
      layerId: LayerId(key),
      onTimesheet: on,
      onToggle: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        // A fresh element per language: the words are read at BUILD.
        key: ValueKey<AppLanguage>(language),
        home: Scaffold(
          body: Wrap(
            children: [
              eye('eye-layer-shown', RailSubject.layer, true),
              eye('eye-layer-hidden', RailSubject.layer, false),
              eye('eye-track-shown', RailSubject.track, true),
              eye('eye-track-hidden', RailSubject.track, false),
              fx('fx-layer-on', RailSubject.layer, LayerFxState.on),
              fx('fx-layer-off', RailSubject.layer, LayerFxState.off),
              fx('fx-layer-mixed', RailSubject.layer, LayerFxState.mixed),
              fx('fx-track-on', RailSubject.track, LayerFxState.on),
              fx('fx-track-off', RailSubject.track, LayerFxState.off),
              blend('blend-layer', isGroup: false),
              blend('blend-folder', isGroup: true),
              sheet('on', true),
              sheet('off', false),
            ],
          ),
        ),
      ),
    );
    String face(String key) => tester
        .widget<AppIconButtonFace>(find.byKey(ValueKey<String>(key)))
        .tooltip;
    String chip(String key) => tester
        .widget<PanelFlyoutButton>(find.byKey(ValueKey<String>(key)))
        .tooltip!;
    return {
      for (final key in [
        'eye-layer-shown',
        'eye-layer-hidden',
        'eye-track-shown',
        'eye-track-hidden',
        'fx-layer-on',
        'fx-layer-off',
        'fx-layer-mixed',
        'fx-track-on',
        'fx-track-off',
      ])
        key: face(key),
      'blend-layer': chip('blend-layer'),
      'blend-folder': chip('blend-folder'),
      'sheet-on': face('probe-layer-timesheet-on'),
      'sheet-off': face('probe-layer-timesheet-off'),
    };
  }

  /// The words that were nailed to the widgets, by arm.
  const wasEnglish = <String, String>{
    'eye-layer-shown': 'Hide layer',
    'eye-layer-hidden': 'Show layer',
    'eye-track-shown': 'Hide cut picture',
    'eye-track-hidden': 'Show cut picture',
    'fx-layer-on': 'Bypass layer FX',
    'fx-layer-off': 'Apply layer FX',
    'fx-layer-mixed': 'Bypass all layer FX (some are off)',
    'fx-track-on': 'Bypass track FX',
    'fx-track-off': 'Apply track FX',
    'blend-layer': 'Layer blend mode',
    'blend-folder': 'Folder blend mode',
    'sheet-on': 'Remove from timesheet',
    'sheet-off': 'Add to timesheet',
    'lanes-open': 'Collapse lanes',
    'lanes-shut': 'Expand lanes',
    'onion-on': 'Onion skin (on)',
    'onion-off': 'Onion skin',
    'fill-on': 'Fill reference layer (on)',
    'fill-off': 'Fill reference layer',
  };

  /// The KEY each arm reads — not its words. ⚠️Without it a swap passes:
  /// the folder arm reading the layer sentence is translated, differs by
  /// language and is not the old English.
  final keyOf = <String, String Function(AppStrings)>{
    'eye-layer-shown': (s) => s.railHideLayer,
    'eye-layer-hidden': (s) => s.railShowLayer,
    'eye-track-shown': (s) => s.railHideCutPicture,
    'eye-track-hidden': (s) => s.railShowCutPicture,
    'fx-layer-on': (s) => s.railBypassLayerFx,
    'fx-layer-off': (s) => s.railApplyLayerFx,
    'fx-layer-mixed': (s) => s.railBypassMixedLayerFx,
    'fx-track-on': (s) => s.railBypassTrackFx,
    'fx-track-off': (s) => s.railApplyTrackFx,
    'blend-layer': (s) => s.railLayerBlendMode,
    'blend-folder': (s) => s.railFolderBlendMode,
    'sheet-on': (s) => s.railRemoveFromTimesheet,
    'sheet-off': (s) => s.railAddToTimesheet,
    'lanes-open': (s) => s.railCollapseLanes,
    'lanes-shut': (s) => s.railExpandLanes,
    'onion-on': (s) => s.railOnionSkinOn,
    'onion-off': (s) => s.railOnionSkin,
    'fill-on': (s) => s.railFillReferenceOn,
    'fill-off': (s) => s.railFillReference,
  };

  void expectTranslated(
    Map<String, String> ja,
    Map<String, String> ko,
  ) {
    expect(ja.keys, unorderedEquals(ko.keys));
    for (final arm in ja.keys) {
      expect(ja[arm], isNot(ko[arm]), reason: '$arm: the table, not a literal');
      expect(ja[arm], isNot(wasEnglish[arm]), reason: '$arm (ja)');
      expect(ko[arm], isNot(wasEnglish[arm]), reason: '$arm (ko)');
      expect(ja[arm], keyOf[arm]!(AppStrings.of(AppLanguage.ja)), reason: arm);
      expect(ko[arm], keyOf[arm]!(AppStrings.of(AppLanguage.ko)), reason: arm);
    }
  }

  testWidgets('the shared rail controls read every arm from the table', (
    tester,
  ) async {
    final ja = await sharedControls(tester, AppLanguage.ja);
    final ko = await sharedControls(tester, AppLanguage.ko);
    expect(ja, hasLength(13), reason: 'LIVENESS: every arm was read');
    expectTranslated(ja, ko);
  });

  /// The rail row's own toggles — lanes, onion, fill reference — in both
  /// arms, on the real timeline over a real session.
  Future<Map<String, String>> rowToggles(
    WidgetTester tester,
    AppLanguage language,
  ) async {
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
    final words = <String, String>{};
    for (final on in [false, true]) {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final layer = session.activeLayer!;
      if (on) {
        session.onionSkin.toggleLayerOnionSkin(layer.id);
        session.layerSwitches.toggleLayerFillReference(layer.id);
      }
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey<(AppLanguage, bool)>((language, on)),
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
                expandedLaneLayerIds: on ? {layer.id} : const {},
                onToggleLayerLanes: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      String face(String key) => tester
          .widget<AppIconButtonFace>(find.byKey(ValueKey<String>(key)))
          .tooltip;
      final id = layer.id;
      words[on ? 'lanes-open' : 'lanes-shut'] = face(
        'timeline-lane-toggle-$id',
      );
      words[on ? 'onion-on' : 'onion-off'] = face('timeline-layer-onion-$id');
      words[on ? 'fill-on' : 'fill-off'] = face(
        'timeline-layer-fill-reference-$id',
      );
    }
    return words;
  }

  testWidgets('the rail row\'s own toggles read both arms from the table', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ja = await rowToggles(tester, AppLanguage.ja);
    final ko = await rowToggles(tester, AppLanguage.ko);
    expect(ja, hasLength(6), reason: 'LIVENESS: both arms of all three');
    expectTranslated(ja, ko);
  });

  testWidgets('the storyboard\'s track row names the track and its cut '
      'pictures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    expectTranslated(
      await _trackRow(tester, AppLanguage.ja),
      await _trackRow(tester, AppLanguage.ko),
    );
  });
}

/// The storyboard's TRACK row names itself — its switch is the track's FX
/// and its eye the cut pictures — on the real storyboard, so the call sites
/// that used to pass `'track'` and `'cut picture'` are held too.
Future<Map<String, String>> _trackRow(
  WidgetTester tester,
  AppLanguage language,
) async {
  AppText.settings.value = AppLanguageSettings(programLanguage: language);
  final session = EditorSessionManager(initialProject: createDefaultProject());
  addTearDown(session.dispose);
  final track = session.repository.requireProject().tracks.first;
  final cut = track.cuts.first;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey<AppLanguage>(language),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: session,
          builder: (context, _) => StoryboardTabHost(
            session: session,
            pixelsPerFrame: 24,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
            thumbnails: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  String face(String key) => tester
      .widget<AppIconButtonFace>(find.byKey(ValueKey<String>(key)))
      .tooltip;
  return {
    'fx-track-on': face('storyboard-track-fx-${track.id.value}'),
    'eye-track-shown': face('storyboard-cut-visibility-${cut.id.value}'),
  };
}
