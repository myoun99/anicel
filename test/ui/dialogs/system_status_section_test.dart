import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/services/runtime_path_report.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/ui/dialogs/system_status_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// Preferences ▸ System (user rule 07-22): every runtime-selected
/// implementation path is REPORTED — the report's subsystem roster is a
/// contract (forgetting to list a new switchable path is the regression
/// this file exists to catch), and fallback states must render as
/// visible states, not vanish.
void main() {
  test('the report covers every switchable subsystem', () {
    final entries = collectRuntimePathReport();
    expect(entries.map((entry) => entry.subsystem), [
      'Audio import decoder',
      'Video export encoder',
      'PDF renderer',
      'Tile picture upload',
      'Pen tablet driver',
    ]);
    for (final entry in entries) {
      expect(entry.active, isNotEmpty, reason: entry.subsystem);
      expect(entry.detail, isNotEmpty, reason: entry.subsystem);
    }
  });

  test('an unloaded PDF renderer reports its absence honestly', () {
    // flutter_tester never loads PDFium (no Dart fallback exists for it),
    // so the report must show the disabled state, tinted as non-primary.
    final pdf = collectRuntimePathReport().singleWhere(
      (entry) => entry.subsystem == 'PDF renderer',
    );
    expect(pdf.isPrimary, isFalse);
    expect(pdf.active, contains('disabled'));
  });

  test('the tile picture upload follows the RENDERER, not the packaging', () {
    // The only row here whose non-primary state is normal rather than a
    // problem: `decodeImageFromPixelsSync` is Impeller-only, so on
    // `flutter_tester` (Skia) the door DRAWS the picture instead — the
    // same bytes, inside the same frame. The shipped app (Impeller
    // everywhere since 3.47) reports the upload row as primary; this test
    // pins the HARNESS's answer, and the detail still has to say why an
    // amber row is not a broken build.
    final upload = collectRuntimePathReport().singleWhere(
      (entry) => entry.subsystem == 'Tile picture upload',
    );
    expect(upload.isPrimary, pictureOfUploads);
    expect(upload.isPrimary, isFalse, reason: 'flutter_tester runs Skia');
    expect(upload.active, contains('Synchronous draw'));
    expect(upload.detail, contains('Impeller'));
  });

  testWidgets('the section renders one row per subsystem', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SystemStatusSection(
              openSessions: [session],
              appSettings: session.appSettings,
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('system-status-section')),
      findsOneWidget,
    );
    for (final entry in collectRuntimePathReport()) {
      expect(
        find.byKey(ValueKey<String>('system-status-${entry.subsystem}')),
        findsOneWidget,
      );
      expect(find.text(entry.subsystem), findsOneWidget);
    }
  });

  Future<void> pump(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SystemStatusSection(
              openSessions: [session],
              appSettings: session.appSettings,
            ),
          ),
        ),
      ),
    );
  }

  // 🗣️connection-round-checklist-Q4 (유저 2026-11-06): 「환경설정에 GPU 고르기를
  // 넣는다 — 자동 · 절전 · 고성능」 — where the platform's Flutter takes one.
  group('the GPU choice', () {
    final picker = find.byKey(
      const ValueKey<String>(GpuPreferenceRow.pickerKey),
    );
    String row(AppGpuPreference preference) =>
        '${GpuPreferenceRow.pickerKey}-${preference.name}';
    final warning = find.byKey(GpuPreferenceRow.nextLaunchKey);

    tearDown(AppGpu.debugReset);

    bool warns(WidgetTester tester) {
      final said = tester.widget<Text>(warning).data!;
      expect(said, anyOf('', AppText.strings.gpuPreferenceNextLaunch));
      return said.isNotEmpty;
    }

    Future<void> pick(WidgetTester tester, AppGpuPreference to) async {
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(row(to))));
      await tester.pumpAndSettle();
    }

    testWidgets('is auto, power saving and high performance; a pick is the '
        'setting, and one the run did not start with warns in a line kept '
        'for it', (tester) async {
      AppGpu.noteStartedWith(AppGpuPreference.auto);
      await pump(tester);
      expect(
        [
          for (final entry
              in tester.widget<PanelFlyoutButton>(picker).entriesBuilder())
            if (entry is PanelFlyoutItem) (entry.keyValue, entry.label),
        ],
        [
          (row(AppGpuPreference.auto), AppText.strings.gpuPreferenceAuto),
          (
            row(AppGpuPreference.lowPower),
            AppText.strings.gpuPreferenceLowPower,
          ),
          (
            row(AppGpuPreference.highPerformance),
            AppText.strings.gpuPreferenceHighPerformance,
          ),
        ],
      );
      expect(warns(tester), isFalse);
      final kept = tester.getSize(find.byType(GpuPreferenceRow));

      await pick(tester, AppGpuPreference.highPerformance);
      expect(
        AppGpu.settings.value,
        const AppGpuSettings(preference: AppGpuPreference.highPerformance),
      );
      expect(warns(tester), isTrue);
      expect(tester.getSize(find.byType(GpuPreferenceRow)), kept);

      await pick(tester, AppGpuPreference.auto);
      expect(AppGpu.settings.value, const AppGpuSettings());
      expect(warns(tester), isFalse, reason: 'back to what the run has');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    String tooltipOf(WidgetTester tester) => tester
        .widget<AppTooltip>(
          find.ancestor(of: picker, matching: find.byType(AppTooltip)),
        )
        .message;

    testWidgets('where it can be made, its tooltip says what it is', (
      tester,
    ) async {
      await pump(tester);
      expect(tester.widget<PanelFlyoutButton>(picker).enabled, isTrue);
      expect(tooltipOf(tester), AppText.strings.gpuPreferenceHelp);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    // 🗣️gpu-choice-in-preferences-Q1 (유저 2026-11-06): 「맥 · 리눅스에도
    // 줄은 두되 흐리게(고를 수 없음)」 · 「호버 툴팁으로 이유 표시」.
    final whyNot = <TargetPlatform, String Function()>{
      TargetPlatform.macOS: () => AppText.strings.gpuPreferenceNotOnMacOS,
      TargetPlatform.linux: () => AppText.strings.gpuPreferenceDriverPicks,
      TargetPlatform.iOS: () => AppText.strings.gpuPreferenceOneGpu,
      TargetPlatform.android: () => AppText.strings.gpuPreferenceOneGpu,
    };
    final elsewhere = TargetPlatformVariant(whyNot.keys.toSet());
    testWidgets('where the platform\'s Flutter takes none, the row stands '
        'in its place, dimmed, its tooltip saying why', (tester) async {
      await pump(tester);
      expect(find.byType(GpuPreferenceRow), findsOneWidget);
      expect(tester.widget<PanelFlyoutButton>(picker).enabled, isFalse);
      expect(tooltipOf(tester), whyNot[defaultTargetPlatform]!());

      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey<String>(row(AppGpuPreference.highPerformance))),
        findsNothing,
        reason: 'no list to pick from',
      );
      expect(AppGpu.settings.value, const AppGpuSettings());
    }, variant: elsewhere);
  });

  // 🗣️an-endless-plugin-stalls-the-app-Q13 「열 배씩 … 고른다」 · -Q19 「화소
  // 하나의 몫으로 고정」 · -Q18 「끊지 않음」.
  testWidgets('what each pixel of a GPU fx plugin may spend is picked from '
      'its five shares and never cutting, the GPU choice kept', (
    tester,
  ) async {
    addTearDown(AppGpu.debugReset);
    AppGpu.settings.value = const AppGpuSettings(
      preference: AppGpuPreference.lowPower,
    );
    final picker = find.byKey(
      const ValueKey<String>(FxPluginShareRow.pickerKey),
    );
    String row(FxPluginShare share) =>
        '${FxPluginShareRow.pickerKey}-${share.name}';
    final strings = AppText.strings;
    final labels = {
      FxPluginShare.tenThousand: strings.fxPluginShareTenThousand,
      FxPluginShare.hundredThousand: strings.fxPluginShareHundredThousand,
      FxPluginShare.million: strings.fxPluginShareMillion,
      FxPluginShare.tenMillion: strings.fxPluginShareTenMillion,
      FxPluginShare.hundredMillion: strings.fxPluginShareHundredMillion,
      FxPluginShare.uncut: strings.fxPluginShareUncut,
    };
    await pump(tester);
    expect(
      [
        for (final entry
            in tester.widget<PanelFlyoutButton>(picker).entriesBuilder())
          if (entry is PanelFlyoutItem) (entry.keyValue, entry.label),
      ],
      [for (final MapEntry(:key, :value) in labels.entries) (row(key), value)],
    );

    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>(row(FxPluginShare.tenThousand))),
    );
    await tester.pumpAndSettle();
    expect(
      AppGpu.settings.value,
      const AppGpuSettings(
        preference: AppGpuPreference.lowPower,
        pluginShare: FxPluginShare.tenThousand,
      ),
    );
  });
}
