import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/dialogs/memory_settings_section.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Preferences ▸ Memory (유저 2026-08-28): 「이 앱이 쓰는 메모리의 총합.
/// 그리고 추가적으로 거기서 어떤항목이 얼만큼 차지하는지도 보여주고」.
///
/// The user's own question decided the shape: 「os합이랑 우리가 쓰는 합이랑
/// 다르다면 os합 보여주고 우리가쓰는 합 보여주고 그 합 안에서 항목 나눠서
/// 보여줌」. They differ by construction, so the panel shows both.
void main() {
  EditorSessionManager newSession() =>
      EditorSessionManager(initialProject: createDefaultProject());

  test('the census reports the process, not just our caches', () {
    final session = newSession();
    addTearDown(session.dispose);
    final census = collectMemoryCensus(session);

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
    expect(collectMemoryCensus(session).footprintBytes, greaterThan(0));
  });

  test('every item carries a label, and the ids are the census ids', () {
    final session = newSession();
    addTearDown(session.dispose);
    final ids = collectMemoryCensus(session).items.map((i) => i.id).toSet();
    // A new cache added to the census with no label would render its raw
    // id — `panelRasters` in front of an animator. This is the list the
    // section switches on; the two must not drift.
    expect(ids, {
      'drawings',
      'sheetInk',
      'undo',
      'playbackFrames',
      'layerImages',
      'brushTips',
      'panelRasters',
      'viewerPages',
      'imageCache',
      'storyboardThumbnails',
      'tileImages',
      'engineBuffers',
    });
  });

  test('items come back largest first', () {
    final session = newSession();
    addTearDown(session.dispose);
    final bytes = collectMemoryCensus(session).items.map((i) => i.bytes);
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
        home: Scaffold(body: MemorySettingsSection(session: session)),
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
    final row = collectMemoryCensus(
      session,
    ).items.singleWhere((item) => item.id == 'storyboardThumbnails');
    expect(row.bytes, 12345);
  });
}
