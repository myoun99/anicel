import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/settings_flyout.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🚨F-73 ① (유저 2026-09-11): 「브러시 탭 그룹 이름이나 스트로크 프리뷰 상태가
/// 저장안됨. 그룹 이름을 해제하거나 스트로크 이름이랑 프리뷰 해제하고 패널닫고
/// 다시열면 리셋되있음」.
///
/// Through HomePage, the way it was met: the library's own rail group closed
/// and opened again, the app started again on the same layout file, and the
/// workspace reset — each read off the panel's OWN menu, whose check mark is
/// the State that used to forget. ⚠️Not off the rows: in a widget test the
/// workspace's library opens with none, so a row count would pass either way.
void main() {
  final libraryGroup = find.byKey(
    const ValueKey<String>('rail-group-${EditorWorkspace.leftGroupId}'),
  );

  Future<void> tapKey(WidgetTester tester, String keyValue) async {
    final target = find.byKey(ValueKey<String>(keyValue));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Whether the panel's menu shows the stroke previews checked — opened,
  /// read, and closed again without picking anything.
  Future<bool> strokePreviewsChecked(WidgetTester tester) async {
    await tapKey(tester, 'brush-preset-menu-button');
    final checked = find
        .descendant(
          of: find.byKey(
            const ValueKey<String>('brush-preset-view-stroke-toggle'),
          ),
          matching: find.byIcon(Icons.check),
        )
        .evaluate()
        .isNotEmpty;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    return checked;
  }

  Future<void> hideStrokePreviews(WidgetTester tester) async {
    expect(
      await strokePreviewsChecked(tester),
      isTrue,
      reason: 'premise: on by default',
    );
    await tapKey(tester, 'brush-preset-menu-button');
    await tapKey(tester, 'brush-preset-view-stroke-toggle');
    expect(
      await strokePreviewsChecked(tester),
      isFalse,
      reason: 'premise: the toggle took',
    );
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    WorkspaceLayoutStore? store,
  }) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: HomePage(layoutStore: store)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a view toggle survives closing the panel and opening it '
      'again', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    await hideStrokePreviews(tester);
    await tester.tap(libraryGroup);
    await tester.pumpAndSettle();
    expect(
      find.byType(BrushPresetPanel),
      findsNothing,
      reason: 'premise: the panel really closed, so its State is gone',
    );
    await tester.tap(libraryGroup);
    await tester.pumpAndSettle();

    expect(find.byType(BrushPresetPanel), findsOneWidget);
    expect(
      await strokePreviewsChecked(tester),
      isFalse,
      reason: 'the panel opened again with the stroke previews it was told to '
          'hide back on',
    );
  });

  testWidgets('the layout file keeps them — a restart opens the panel as it '
      'was left, and a workspace reset brings the defaults back', (
    tester,
  ) async {
    // Real file IO only inside runAsync — awaited on the fake clock a
    // testWidgets body runs on, createTemp never completes.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('brush_view_toggles'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = WorkspaceLayoutStore(
      filePath: '${directory.path}/workspace_layout.json',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, store: store);

    await hideStrokePreviews(tester);
    // The save is debounced 800 ms behind the last change; the write is real
    // IO whose steps complete in real time and continue on the fake clock.
    await tester.pump(const Duration(milliseconds: 900));
    Object? saved;
    for (var tries = 0; tries < 40 && saved == null; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final payload = await tester.runAsync<Map<String, Object?>?>(store.load);
      saved = payload?['brushPresetView'];
    }
    expect(saved, isA<Map<String, Object?>>(), reason: 'nothing was saved');
    expect(
      (saved! as Map<String, Object?>)['strokePreview'],
      isFalse,
      reason: 'the toggle is the change that scheduled the save',
    );

    // A restart: the old workspace goes, a new one reads the same file — and
    // the panel is already up when the restore lands.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, store: store);
    bool restored() => !tester
        .widget<BrushPresetPanel>(find.byType(BrushPresetPanel))
        .viewOptions
        .showStrokePreview;
    for (var tries = 0; tries < 40 && !restored(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    expect(
      await strokePreviewsChecked(tester),
      isFalse,
      reason: 'the restored layout opened the panel with its stroke previews '
          'back on',
    );

    await tapPanelsDrawerRow(tester, 'menu-window-reset-layout');
    expect(
      await strokePreviewsChecked(tester),
      isTrue,
      reason: 'every field the save writes is reset — the view toggles too',
    );
  });
}
