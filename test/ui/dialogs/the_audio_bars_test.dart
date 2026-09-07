import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/dialogs/audio_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// The two bars in Preferences ▸ Audio — nothing named them
/// (2026-09-05), and they were the last raw Material Sliders in the app.
///
/// 🚨MIC GAIN IS SIGNED. The range is symmetric around 0, so `6` and `-6`
/// are different places and the boost side must SAY it is boosting: a
/// bare `6` reads as "the default, unchanged".
void main() {
  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  Future<EditorSessionManager> pumpSection(WidgetTester tester) async {
    final manager = session();
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AudioSettingsSection(session: manager),
          ),
        ),
      ),
    );
    return manager;
  }

  FieldSlider barAt(WidgetTester tester, String key) =>
      tester.widget<FieldSlider>(find.byKey(ValueKey<String>(key)));

  testWidgets('🚨mic gain reads SIGNED — +6 is a boost, 6 would read as the '
      'default', (tester) async {
    await pumpSection(tester);

    final gain = barAt(tester, 'settings-mic-gain-slider');
    expect(gain.valueText, '0', reason: 'no gain is plain zero');
    expect(gain.valueTextBuilder!(6), '+6');
    expect(gain.valueTextBuilder!(-6), '-6');
  });

  testWidgets('mic gain runs symmetrically around zero, one stop per dB', (
    tester,
  ) async {
    await pumpSection(tester);

    final gain = barAt(tester, 'settings-mic-gain-slider');
    expect(gain.min, -AudioSyncSettings.maxMicGainDb.toDouble());
    expect(gain.max, AudioSyncSettings.maxMicGainDb.toDouble());
    expect(gain.divisions, AudioSyncSettings.maxMicGainDb * 2);
  });

  testWidgets('🚨the bar WRITES the setting, clamped — a drag past the end '
      'lands on the end rather than on an unstorable number', (tester) async {
    final manager = await pumpSection(tester);

    barAt(tester, 'settings-mic-gain-slider').onChanged!(999);
    await tester.pump();

    expect(
      manager.appSettings.audioSyncSettings.value.micGainDb,
      AudioSyncSettings.maxMicGainDb,
    );
  });

  testWidgets('the count-in bar starts at NO count-in and steps in whole '
      'seconds', (tester) async {
    final manager = await pumpSection(tester);

    final countIn = barAt(tester, 'settings-count-in-slider');
    expect(countIn.min, 0, reason: 'no count-in is a legal setting');
    expect(countIn.max, AudioSyncSettings.maxCountInSeconds.toDouble());
    expect(countIn.divisions, AudioSyncSettings.maxCountInSeconds);

    countIn.onChanged!(3);
    await tester.pump();
    expect(manager.appSettings.audioSyncSettings.value.countInSeconds, 3);
    expect(barAt(tester, 'settings-count-in-slider').valueText, '3');
  });

  testWidgets('⛔no raw Material Slider is left in Preferences ▸ Audio — a '
      'bar here must obey the press-claim law inside the scroll view', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.byType(Slider), findsNothing);
    expect(find.byType(FieldSlider), findsNWidgets(2));
  });
}
