import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/app_gpu_engine.dart'
    show debugAppGpuVideoMemory;
import 'package:gpu_engine/gpu_engine.dart' show GpuVideoMemory;
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/dialogs/memory_settings_section.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cache_budgets.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/models/app_language.dart';

import '../../helpers/census_where_textures_are_ram.dart';
import '../../helpers/text_finders.dart';

/// Preferences ▸ Memory (유저 2026-08-28): 「이 앱이 쓰는 메모리의 총합.
/// 그리고 추가적으로 거기서 어떤항목이 얼만큼 차지하는지도 보여주고」.
///
/// The user's own question decided the shape: 「os합이랑 우리가 쓰는 합이랑
/// 다르다면 os합 보여주고 우리가쓰는 합 보여주고 그 합 안에서 항목 나눠서
/// 보여줌」. They differ by construction, so the panel shows both.
void main() {
  EditorSessionManager newSession() =>
      EditorSessionManager(initialProject: createDefaultProject());

  /// A GPU of its own, as the OS says it on Windows.
  const discrete = (
    integrated: false,
    used: 860 << 20,
    budget: 12800 << 20,
    inSystem: 93 << 20,
    total: 16376 << 20,
  );

  /// A GPU that shares the RAM, as the OS says it on Windows.
  const integrated = (
    integrated: true,
    used: 3000 << 20,
    budget: 16000 << 20,
    inSystem: 0,
    total: 128 << 20,
  );

  /// Where the OS says nothing of the GPU's memory (Android, Linux).
  const unsaid = (
    integrated: false,
    used: null,
    budget: null,
    inSystem: null,
    total: null,
  );

  /// The section on its own, in a dialog's width.
  Future<void> showTheSection(WidgetTester tester) async {
    final session = newSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 688,
              child: MemorySettingsSection(
                session: session,
                openSessions: [session],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cells of the column [column] names — `memory-ram`, `memory-vram`.
  Finder cellsOf(String column) => find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('$column-cell-');
  });

  /// The figure a row writes beside [label] — the last words on its line —
  /// in the column [column] names.
  String figureIn(WidgetTester tester, String column, String label) => tester
      .widgetList<Text>(
        find.descendant(
          of: find
              .ancestor(
                of: find.descendant(
                  of: cellsOf(column),
                  matching: find.text(label),
                ),
                matching: find.byType(Row),
              )
              .first,
          matching: find.anyText(),
        ),
      )
      .last
      .data!;

  void readsTheGpuAs(GpuVideoMemory gpu) {
    debugAppGpuVideoMemory = gpu;
    addTearDown(() => debugAppGpuVideoMemory = null);
  }

  test('the census reports the process, not just our caches', () {
    final session = newSession();
    addTearDown(session.dispose);
    final census = collectMemoryCensus([session]);

    // 🚨THE WHOLE POINT OF TWO TOTALS. A fresh session holds almost
    // nothing, but the PROCESS holds the Dart heap, Skia's arenas and the
    // engine's own allocations. If these were ever equal, the panel would
    // be lying about one of them.
    expect(
      census.footprintBytes,
      greaterThan(census.trackedBytes),
      reason:
          'the process is always larger than what we can enumerate — '
          'that gap is the engine and the framework, not a leak',
    );
    expect(
      census.untrackedBytes,
      census.footprintBytes - census.trackedBytes,
      reason: 'the gap is named rather than left as arithmetic',
    );
  });

  test('the process number is answered on THIS platform', () {
    final session = newSession();
    addTearDown(session.dispose);
    // ⛔THE BUG THIS REPLACED, TWICE. First the System row asked the engine
    // for `processFootprintBytes` when ABI v29 answered only on Apple, so
    // Windows and Linux printed "not measured here". The census then used
    // `ProcessInfo.currentRss`, which answers everywhere but counts pages
    // SHARED with other processes, so it never matched the task manager
    // the user was looking at. The engine answers on every platform now
    // and RSS is only the no-engine fallback — either way this is a real
    // number, which is what the row exists to show.
    expect(collectMemoryCensus([session]).footprintBytes, greaterThan(0));
  });

  test('🚨F-226-Q1: where the GPU keeps its own memory, its pictures are not '
      'RAM and the census leaves them out — 「GPU에 들어가는 메모리는 계산에서 '
      '싹 빼고 RAM만 집계」 — and lists them as the VRAM\'s (유저 2026-11-16, '
      'vram-in-use-shown-in-the-memory-tab-Q3: 「칸마다 내역」)', () {
    final session = newSession();
    addTearDown(session.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    readsTheGpuAs(discrete);

    final census = collectMemoryCensus([session]);

    expect(census.items.map((i) => i.id).toSet(), {
      'drawings',
      'sheetInk',
      'undo',
      'brushTips',
      'moviePictures',
      'engineScratch',
      'gpuInSystem',
    });
    expect(census.gpuMemoryIsRam, isFalse);
    expect(census.videoItems.map((i) => i.id).toSet(), {
      'framePictures',
      'tileImages',
      'imageCache',
      'panelRasters',
      'viewerPages',
      'storyboardThumbnails',
      'sheetImages',
      'textImages',
      'strokePreviews',
      'timelineTiles',
    });
    final bytes = census.videoItems.map((i) => i.bytes).toList();
    final largestFirst = [...bytes]..sort((a, b) => b.compareTo(a));
    expect(bytes, orderedEquals(largestFirst));
    expect(
      census.videoUntrackedBytes,
      (860 << 20) - census.videoTrackedBytes,
      reason: 'what the OS says this app uses there, less what rows name',
    );
  });

  test('🚨what the GPU holds in the RAM is RAM where its own memory is '
      'apart: the non-local use is a row of its own, its local use and '
      'budget the VRAM line, in no row (관제 2026-11-07, '
      'census-counts-integrated-gpu-textures-as-ram)', () {
    final session = newSession();
    addTearDown(session.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    readsTheGpuAs(discrete);

    final census = collectMemoryCensus([session]);

    expect(
      census.items.singleWhere((item) => item.id == 'gpuInSystem').bytes,
      93 << 20,
    );
    expect(census.videoMemory, (
      used: 860 << 20,
      budget: 12800 << 20,
      total: 16376 << 20,
    ));
  });

  test('🗣️census-counts-integrated-gpu-textures-as-ram-Q1 (유저 '
      '2026-11-07): a Windows GPU that shares the RAM keeps its pictures '
      'there — the census counts them, as it does on Apple', () {
    final session = newSession();
    addTearDown(session.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    readsTheGpuAs(integrated);

    final census = collectMemoryCensus([session]);

    expect(census.gpuMemoryIsRam, isTrue);
    expect(census.videoItems, isEmpty, reason: 'its pictures are the RAM\'s');
    expect(
      census.items.map((i) => i.id),
      isNot(contains('gpuInSystem')),
      reason:
          'a GPU that shares the RAM has no memory of its own for a part '
          'of it to lie in the RAM — its pictures are the rows',
    );
    expect(
      census.items.map((i) => i.id).toSet(),
      collectMemoryCensusWhereTexturesAreRam([
        session,
      ]).items.map((i) => i.id).toSet(),
    );
  });

  test('which GPU it is decides on Windows alone: Apple counts the '
      "pictures whatever it is, and Android and Linux, whose GPU's memory "
      'is billed apart from their number, count them for none', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final counted = <TargetPlatform, List<bool>>{};
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      counted[platform] = [
        for (final gpu in [discrete, integrated, unsaid, null])
          texturesAreInTheRamFigure(gpu),
      ];
    }

    expect(counted, {
      TargetPlatform.android: [false, false, false, false],
      TargetPlatform.fuchsia: [false, false, false, false],
      TargetPlatform.iOS: [true, true, true, true],
      TargetPlatform.linux: [false, false, false, false],
      TargetPlatform.macOS: [true, true, true, true],
      TargetPlatform.windows: [false, true, false, false],
    });
  });

  test('every item carries a label, and the ids are the census ids', () {
    final session = newSession();
    addTearDown(session.dispose);
    // Where the GPU shares the RAM every picture row is counted, and
    // where it has its own memory what of it lies in the RAM — the whole
    // list between them.
    final ids = collectMemoryCensusWhereTexturesAreRam([
      session,
    ]).items.map((i) => i.id).toSet();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    readsTheGpuAs(discrete);
    ids.addAll(collectMemoryCensus([session]).items.map((i) => i.id));
    // A new cache added to the census with no label would render its raw
    // id — `panelRasters` in front of an animator. This is the list the
    // section switches on; the two must not drift.
    expect(ids, {
      'drawings',
      'sheetInk',
      'undo',
      'framePictures',
      'brushTips',
      'panelRasters',
      'viewerPages',
      'imageCache',
      'storyboardThumbnails',
      'sheetImages',
      'textImages',
      'strokePreviews',
      'timelineTiles',
      'moviePictures',
      'tileImages',
      'engineScratch',
      'gpuInSystem',
    });
  });

  test('items come back largest first', () {
    final session = newSession();
    addTearDown(session.dispose);
    final bytes = collectMemoryCensus([session]).items.map((i) => i.bytes);
    expect(
      bytes.toList(),
      orderedEquals(bytes.toList()..sort((a, b) => b.compareTo(a))),
      reason:
          'the panel is read top-down; the biggest holding is the one '
          'somebody opened this to find',
    );
  });

  testWidgets('the section reserves its layout before a sample lands', (
    tester,
  ) async {
    // ⛔NO UI THAT POPS INTO EXISTENCE. The bar and the totals are mounted
    // from the first frame; only the numbers change when the timer fires.
    final session = newSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemorySettingsSection(
            session: session,
            openSessions: [session],
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('memory-settings-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('memory-live-bar')),
      findsOneWidget,
    );
    // The timer is periodic; let one tick land and confirm nothing throws
    // and the layout is unchanged in shape.
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byKey(const ValueKey<String>('memory-live-bar')),
      findsOneWidget,
    );
  });

  test('Memory is a preferences section', () {
    expect(PreferencesSection.values, contains(PreferencesSection.memory));
  });

  test('ONE census — the System row does not count for itself', () {
    // 🚨SOURCE SCAN, because behaviour cannot see this. Two counters that
    // agree today both pass; they part company the first time either one
    // learns about a cache. That is exactly how the conte and envelope ink
    // controllers drifted, and the fix there was the same: one
    // implementation, nothing to keep in sync.
    final system = File(
      'lib/src/ui/dialogs/system_status_section.dart',
    ).readAsStringSync();
    expect(
      system.contains('collectMemoryCensus'),
      isTrue,
      reason: 'the System row reads the shared census',
    );
    expect(
      system.contains('processFootprintBytes'),
      isFalse,
      reason:
          'that call returns 0 on Windows and Linux — the census owns '
          'the platform question now',
    );
  });

  test('🚨the storyboard thumbnails are a census row — pushed by the '
      'workspace, read here (2026-09-11)', () {
    final session = newSession();
    addTearDown(session.dispose);
    session.renderCaches.storyboardThumbnailBytes = 12345;
    final row = collectMemoryCensusWhereTexturesAreRam(
      [session],
    ).items.singleWhere((item) => item.id == 'storyboardThumbnails');
    expect(row.bytes, 12345);
  });

  test('the sheets\' media images are a census row — pushed by the '
      'workspace, read here (I-97)', () {
    final session = newSession();
    addTearDown(session.dispose);
    session.renderCaches.sheetImageBytes = 6789;
    final row = collectMemoryCensusWhereTexturesAreRam(
      [session],
    ).items.singleWhere((item) => item.id == 'sheetImages');
    expect(row.bytes, 6789);
  });
  group('🗣️RAM on the left, VRAM on the right, where the GPU has memory of '
      'its own — one column where it shares the RAM (유저 2026-11-16, '
      'vram-in-use-shown-in-the-memory-tab: 「외장gpu면 영역 제대로 나눠서 '
      '왼쪽에 RAM, 오른쪽에 VRAM」, Q3 C, Q4, Q5 C-1)', () {
    const ram = 'memory-ram';
    const vram = 'memory-vram';
    Finder headOf(String column) =>
        find.byKey(ValueKey<String>('$column-cell-0'));

    testWidgets('a GPU of its own: what this app uses of it, the budget the '
        'OS gives it and the whole of it, in a column of its own', (
      tester,
    ) async {
      readsTheGpuAs(discrete);
      await showTheSection(tester);
      final strings = AppText.strings;

      expect(
        find.descendant(
          of: headOf(ram),
          matching: find.text(strings.memoryRam),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: headOf(vram),
          matching: find.text(strings.memoryVram),
        ),
        findsOne,
      );
      expect(
        tester.getCenter(headOf(ram)).dx,
        lessThan(tester.getCenter(headOf(vram)).dx),
        reason: 'RAM on the left',
      );
      expect(figureIn(tester, vram, strings.memoryDeviceVram), '16376.0MB');
      expect(figureIn(tester, vram, strings.memoryGpuTotal), '860.0MB');
      expect(figureIn(tester, vram, strings.memoryAvailable), '11940.0MB');
      // 「기기 메모리는 그리고 RAM 설정이니까 제대로 RAM 항목안에」.
      expect(
        find.descendant(
          of: cellsOf(ram),
          matching: find.text(strings.memoryDeviceTotal),
        ),
        findsOneWidget,
      );
      final budget = tester.widget<FieldSlider>(
        find.byKey(const ValueKey<String>('memory-budget-bar')),
      );
      expect(budget.value, 12800, reason: 'the budget, outlined');
      expect(budget.max, 16376, reason: 'on the scale of the whole of it');
      expect(budget.onChanged, isNull, reason: 'the OS sets it, not a hand');
      expect(budget.setElsewhere, isTrue, reason: 'and it is not dimmed');
      await tester.pump(const Duration(milliseconds: 600));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('🗣️ONE SHAPE, ROW FOR ROW: the budget\'s bar stands where '
        'the allowance\'s does, as long, and the live bars alike — 「ram의 '
        '앱 허용치랑 vram의 os 예산 중 … 너무 다르잖아 … 최대한 통일감」', (
      tester,
    ) async {
      readsTheGpuAs(discrete);
      await showTheSection(tester);
      Rect rectOf(String key) =>
          tester.getRect(find.byKey(ValueKey<String>(key)));
      Rect inColumn(String key, String column) =>
          rectOf(key).shift(-tester.getRect(headOf(column)).topLeft);

      expect(
        inColumn('memory-budget-bar', vram),
        inColumn('memory-allowance-slider', ram),
      );
      expect(
        inColumn('memory-vram-live-bar', vram),
        inColumn('memory-live-bar', ram),
      );
      expect(
        rectOf('memory-budget-bar').right,
        rectOf('memory-vram-live-bar').right,
        reason: 'the bars end together, the button\'s slot kept on both',
      );
      await tester.pump(const Duration(milliseconds: 600));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    for (final (name, gpu, platform) in [
      ('a GPU that shares the RAM', integrated, TargetPlatform.windows),
      ('Apple, whatever the GPU', discrete, TargetPlatform.macOS),
    ]) {
      testWidgets('$name: one column, the RAM, the GPU\'s too', (
        tester,
      ) async {
        readsTheGpuAs(gpu);
        await showTheSection(tester);

        expect(cellsOf(vram), findsNothing);
        expect(find.text(AppText.strings.memoryVram), findsNothing);
        expect(
          find.text(AppText.strings.memoryRamSharedWithGpu),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 600));
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets('Q4 — where the OS says nothing of it: the VRAM column '
        'stands, its OS figures 「—」 and its rows what the app counts', (
      tester,
    ) async {
      readsTheGpuAs(unsaid);
      await showTheSection(tester);
      final strings = AppText.strings;

      for (final label in [
        strings.memoryDeviceVram,
        strings.memoryGpuTotal,
        strings.memoryVramUntracked,
        strings.memoryAvailable,
      ]) {
        expect(figureIn(tester, vram, label), '—', reason: label);
      }
      expect(
        tester
            .widget<FieldSlider>(
              find.byKey(const ValueKey<String>('memory-budget-bar')),
            )
            .restingText,
        '—',
      );
      expect(
        find.descendant(
          of: cellsOf(vram),
          matching: find.text(strings.memoryItemTileImages),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 600));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('three tiers (유저 2026-09-11)', () {
    tearDown(() => AppMemory.settings.value = const AppMemorySettings());

    testWidgets('the device, the allowance and the use are on screen from '
        'the first frame, each with its legend mark', (tester) async {
      final session = newSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemorySettingsSection(
              session: session,
              openSessions: [session],
            ),
          ),
        ),
      );
      for (final key in [
        'memory-allowance-slider',
        'memory-live-bar',
        'memory-legend-tracked',
        'memory-legend-untracked',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
      // ↩️The allowance wore a ring before its name, its outline's legend,
      // till the RAM's and the VRAM's columns were made one shape (유저
      // 2026-11-16: 「앱 허용치앞엔 동그라미있고」 — Q5 C-1 has none).
      expect(
        find.byKey(const ValueKey<String>('memory-legend-allowance')),
        findsNothing,
      );
      expect(find.text(AppText.strings.memoryDeviceTotal), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('🗣️F-480: ONE bar — the allowance is set on the device\'s '
        'own scale, outlined over what the process uses', (tester) async {
      // 「비율이 고정슬라이더가 아니라 변동슬라이더 … 고정값으로. 그렇게 하고
      // 밑, 두번째 슬라이더랑 내용적으로 같아지니 내용 서로 합쳐서 통합」.
      final session = newSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemorySettingsSection(
              session: session,
              openSessions: [session],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final bar = tester.widget<FieldSlider>(
        find.byKey(const ValueKey<String>('memory-allowance-slider')),
      );
      const mb = 1024 * 1024;
      // The figure a total row of the RAM's writes beside its label — the
      // same sample the bar was handed.
      String figureOf(String label) =>
          figureIn(tester, 'memory-ram', label);

      expect(bar.min, 0, reason: 'the bar is the device, from nothing');
      expect(bar.scale, FieldSliderScale.linear);
      expect(bar.floor, CacheBudgets.floors.total / mb);
      expect(
        [for (final level in bar.levels!) level.color],
        [AppColors.hairline, AppColors.accent],
        reason: 'the whole process, then the part we can name over it — the '
            'legend\'s marks',
      );
      expect(
        '${bar.levels!.first.value.toStringAsFixed(1)}MB',
        figureOf(AppText.strings.memoryProcessTotal),
      );
      expect(
        '${bar.levels!.last.value.toStringAsFixed(1)}MB',
        figureOf(AppText.strings.memoryTracked),
      );
      expect(bar.color, AppColors.textDim, reason: 'the outline');
    });

    // 유저 2026-09-16 (memory-allowance-Q2): 「셀 수 없는게 밖에 있으니 그
    // 부분을 문장으로 제대로 알기쉽게 간략하게 설명해두기」 — and (chat, the
    // same day) 「낡지않을구조로」: read off [CacheBudgetLine.covers], never
    // written by hand. ↩️A sentence till the holdings were grouped by it
    // (vram-in-use-shown-in-the-memory-tab-Q3, 2026-11-16: 「C · 칸마다
    // 내역, 허용치로 묶음」) — the names stand in the group they head.
    for (final (column, platform, gpu, under, outside) in [
      // Where the GPU shares the RAM, so the pictures are the RAM's
      // ([texturesAreInTheRamFigure], F-226-Q1).
      (
        'memory',
        TargetPlatform.macOS,
        discrete,
        // The tile pictures moved inside on 2026-09-16 (render round): a
        // ceiling the session sets ([CacheBudgetLine.tileImages]).
        ['캔버스 타일 이미지', '이미지 캐시', '그림'],
        [
          '그리기 엔진 작업 버퍼',
          '패널 래스터',
          '엔진·폰트·프레임워크',
          // Held by how many, not by bytes (card census-misses-bake-once-
          // images): counted, and no budget line is their ceiling.
          '글자 이미지',
          '스트로크 미리보기',
          '타임라인 타일 이미지',
        ],
      ),
      // Where it has memory of its own: the allowance ceilings its
      // pictures there as well.
      (
        'memory-vram',
        TargetPlatform.windows,
        discrete,
        ['캔버스 타일 이미지', '프레임 이미지', '이미지 캐시'],
        ['패널 래스터', '엔진·드라이버·프레임워크', '글자 이미지', '타임라인 타일 이미지'],
      ),
    ]) {
      testWidgets('the $column column groups its holdings by the allowance: '
          'what it ceilings, and what lies outside it', (tester) async {
        AppText.settings.value = const AppLanguageSettings(
          programLanguage: AppLanguage.ko,
        );
        addTearDown(
          () => AppText.settings.value = const AppLanguageSettings(),
        );
        readsTheGpuAs(gpu);
        await showTheSection(tester);
        Finder named(String group, String name) => find.descendant(
          of: find.byKey(ValueKey<String>('$column-$group-allowance')),
          matching: find.text(name),
        );

        expect(named('under', '앱 허용치가 천장을 거는 것'), findsOneWidget);
        expect(named('outside', '앱 허용치 밖'), findsOneWidget);
        for (final name in under) {
          expect(named('under', name), findsOneWidget, reason: name);
          expect(named('outside', name), findsNothing, reason: name);
        }
        for (final name in outside) {
          expect(named('outside', name), findsOneWidget, reason: name);
          expect(named('under', name), findsNothing, reason: name);
        }
        await tester.pump(const Duration(milliseconds: 600));
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets('the automatic button puts a chosen allowance back, and '
        'is inert when there is nothing to put back', (tester) async {
      final session = newSession();
      addTearDown(session.dispose);
      AppMemory.settings.value = AppMemorySettings(
        allowanceBytes: session.deviceCacheBudgets.total ~/ 2,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemorySettingsSection(
              session: session,
              openSessions: [session],
            ),
          ),
        ),
      );
      AppIconButton automatic() => tester.widget<AppIconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIconButton &&
              widget.keyValue == 'memory-allowance-automatic',
        ),
      );
      expect(automatic().onPressed, isNotNull, reason: 'fixture: chosen');

      automatic().onPressed!();
      await tester.pump();

      expect(AppMemory.settings.value.allowanceBytes, isNull);
      expect(automatic().onPressed, isNull, reason: 'nothing to put back');
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
