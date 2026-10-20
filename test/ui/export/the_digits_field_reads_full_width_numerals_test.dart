import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';

import '../../helpers/ime_draft.dart';

/// 🐛F-355 (유저 2026-10-13): a 全角 IME's draft is not changed under it, so
/// the digits of a sequence's names read its numerals half-width — the
/// window may be left before the IME commits.
void main() {
  testWidgets('the digits typed as a 全角 draft are the names\' digits', (
    tester,
  ) async {
    final names = <ExportSequenceNaming>[];
    final baseName = TextEditingController();
    addTearDown(baseName.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportSequenceNamingModule(
            naming: const ExportSequenceNaming(),
            ghost: 'C001',
            enabled: true,
            onChanged: names.add,
            baseNameController: baseName,
          ),
        ),
      ),
    );

    await composeDraft(
      tester,
      find.byKey(const ValueKey<String>('export-naming-digits-field')),
      '６',
    );

    expect(names.map((naming) => naming.digits), [6]);
  });
}
