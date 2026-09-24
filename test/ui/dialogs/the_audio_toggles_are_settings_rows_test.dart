import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/boolean_dot_probe.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/dialogs/audio_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

/// 🚨★★★**THE SETTINGS WINDOW IS ONE SHAPE** — 유저 answered board
/// `press-law-switches-Q2` on 2026-09-17: 「**공용 행으로 모은다 — 설정 창이
/// 한 모양이 된다**」, over the two options that kept the audio section's own
/// 12px row (one of which changed not a single pixel).
///
/// The four toggles in Preferences ▸ Audio — noise suppression, clipping
/// warnings, cue beeps, streamer — were four hand-written copies of
/// `Row(Expanded(Text), Switch)`, the same algorithm four times over,
/// differing in a key, a field and one `copyWith` line. They are
/// [SettingsSwitchRow] now, which is what every other settings row in the
/// app already was.
///
/// 🧪**What that answer IS, measured — two things, and neither is a
/// spelling.** ⛔This file must not check which widget class sits there:
/// the ledger in `every_button_claims_its_press_test` already fails if a
/// bare `Switch` comes back, and a type assertion here would only pin the
/// name.
/// ① **One size.** The four labels draw at the height the shared row draws
///    at — read off a reference [SettingsSwitchRow] mounted in the same
///    tree, so the number comes from the app's own theme and not from a
///    literal this test invented.
/// ② **The whole row is the control.** A press on the LABEL turns that
///    toggle, and only that one. A label beside a bare `Switch` never did
///    anything at all, which is what 「한 모양」 costs and buys.
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

  final strings = AppStrings.of(AppLanguage.en);

  /// The shared row as the rest of the window mounts it, standing in the
  /// same tree as the section so it is read through the same theme.
  const referenceLabel = 'A settings row as the rest of the window has it';

  final rows =
      <({String label, String key, bool Function(AudioSyncSettings) read})>[
        (
          label: strings.audioDenoiseLabel,
          key: 'settings-denoise-voice',
          read: (settings) => settings.denoiseVoice,
        ),
        (
          label: strings.audioClippingNoticeLabel,
          key: 'settings-clipping-notice',
          read: (settings) => settings.clippingNotice,
        ),
        (
          label: strings.audioCueBeepsLabel,
          key: 'settings-cue-beeps',
          read: (settings) => settings.cueBeeps,
        ),
        (
          label: strings.audioStreamerLabel,
          key: 'settings-streamer',
          read: (settings) => settings.streamerEnabled,
        ),
      ];

  Future<EditorSessionManager> pumpAudioSection(WidgetTester tester) async {
    // Wide enough that every label is ONE line on either size — a wrapped
    // label would differ in height for a reason that is not the font.
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = session();
    addTearDown(manager.dispose);
    manager.setLanguageSettings(
      const AppLanguageSettings(programLanguage: AppLanguage.en),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SettingsSwitchRow(
                  label: referenceLabel,
                  value: false,
                  onChanged: (_) {},
                ),
                AudioSettingsSection(session: manager),
              ],
            ),
          ),
        ),
      ),
    );
    return manager;
  }

  testWidgets(
    'the four audio toggles read at the size the settings window reads at, '
    'not at one of their own',
    (tester) async {
      await pumpAudioSection(tester);
      final shared = tester.getSize(find.text(referenceLabel)).height;
      for (final row in rows) {
        expect(
          tester.getSize(find.text(row.label)).height,
          shared,
          reason: '「${row.label}」 draws at the shared row\'s size',
        );
      }
    },
  );

  testWidgets(
    'a press on the LABEL turns that row and no other — the whole row is '
    'the control',
    (tester) async {
      final manager = await pumpAudioSection(tester);
      final live = manager.appSettings.audioSyncSettings;
      Map<String, bool> reading() => <String, bool>{
        for (final row in rows) row.key: row.read(live.value),
      };

      for (final row in rows) {
        final before = reading();
        final label = find.text(row.label);
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        await tester.tap(label);
        await tester.pumpAndSettle();
        final after = reading();
        expect(
          after[row.key],
          !before[row.key]!,
          reason: 'a press on 「${row.label}」 turns its own toggle',
        );
        for (final other in rows) {
          if (other.key == row.key) {
            continue;
          }
          expect(
            after[other.key],
            before[other.key],
            reason: '…and leaves ${other.key} exactly as it was',
          );
        }
        expect(
          tester.booleanDotIn(find.byKey(ValueKey<String>(row.key))).value,
          after[row.key],
          reason: '…and ${row.key} shows what it just wrote',
        );
      }
    },
  );
}
