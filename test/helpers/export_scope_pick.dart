import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/app_strings.dart';

/// The export window's Scope module, as a test reaches it. The Cels tab
/// keeps the module folded until it is asked for, so its pills and its cut
/// grid are not in the tree to be tapped.
extension ExportScopePick on WidgetTester {
  /// Opens the Scope module of the tab that is up, where it stands folded.
  Future<void> openExportScope() async {
    final pill = find.byKey(const ValueKey<String>('export-scope-project'));
    if (pill.evaluate().isNotEmpty) {
      return;
    }
    // Folded, the module's head reads its title and what is picked.
    final folded = find.textContaining('${AppText.strings.exScope} — ');
    await ensureVisible(folded);
    await pump();
    await tap(folded);
    await pump();
  }

  /// Picks the project scope in the tab that is up.
  Future<void> pickExportProjectScope() async {
    await openExportScope();
    final pill = find.byKey(const ValueKey<String>('export-scope-project'));
    await ensureVisible(pill);
    await pump();
    await tap(pill);
    await pump();
  }
}
