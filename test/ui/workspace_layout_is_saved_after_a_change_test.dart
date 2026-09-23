import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import '../helpers/project_scratch_folder.dart';

/// THE WORKSPACE LAYOUT IS SAVED AFTER A CHANGE — MEASURED.
///
/// Every layout mutation schedules a debounced save to the layout store;
/// that is how an arrangement survives a restart. When the persistence was
/// carved out of the workspace State as `_WorkspaceLayoutPersistence`
/// (2026-09-02), the adversarial check made `scheduleLayoutSave` a no-op and
/// all 365 workspace tests stayed green — every one of them pumps HomePage,
/// and under FLUTTER_TEST the workspace runs with NO store, so the save path
/// was never on any test's road. This pumps the workspace with a real store
/// on a temp file, collapses the bottom dock, waits out the debounce and
/// reads the file back.
void main() {
  testWidgets('collapsing the bottom dock reaches the layout file', (
    tester,
  ) async {
    // Real file IO only inside runAsync — awaited on the fake clock a
    // testWidgets body runs on, createTemp never completes.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('layout_save'),
    ))!;
    deleteAfterSessionEnds(directory);
    final store = WorkspaceLayoutStore(
      filePath: '${directory.path}/workspace_layout.json',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Through HomePage, the way every workspace test pumps — with the one
    // seam HomePage grew for this: a store, where tests otherwise get none.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(layoutStore: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(await tester.runAsync(store.load), isNull, reason: 'premise');

    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    // The save is debounced 800 ms behind the last change.
    await tester.pump(const Duration(milliseconds: 900));

    // The write is real file IO started on the fake clock: each of its
    // steps completes in real time (a runAsync window) and its continuation
    // runs on the fake one (a pump). Alternate the two until the file reads.
    Map<String, Object?>? payload;
    for (var tries = 0; tries < 40 && payload == null; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      payload = await tester.runAsync<Map<String, Object?>?>(store.load);
    }
    expect(payload, isNotNull, reason: 'nothing was saved');
    expect(
      payload!['bottomCollapsed'],
      isTrue,
      reason: 'the collapse is the change that scheduled the save',
    );
  });
}
