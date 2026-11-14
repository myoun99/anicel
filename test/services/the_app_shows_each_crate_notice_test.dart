import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/crate_licences.dart';

import '../../tool/crate_notices.dart';

/// The app's About ▸ licenses reads the Rust crates' notices file the way
/// tool/crate_notices.dart writes it: one entry a notice, its crates as the
/// entry's packages, in the file's order — so every crate the list holds is
/// a crate the screen names.
void main() {
  test('each notice is an entry naming its crates', () {
    final text = File('assets/licenses/rust_crates.json').readAsStringSync();
    final file = jsonDecode(text) as Map<String, dynamic>;
    final entries = crateLicenceEntries(text).toList();
    expect(
      [for (final entry in entries) entry.packages.toList()],
      [
        for (final notice in (file['notices'] as List).cast<Map>())
          (notice['crates'] as List).cast<String>(),
      ],
    );
    expect(
      {for (final entry in entries) ...entry.packages}.toList()..sort(),
      noticedCrates(file).noticed,
    );
    expect(entries.every((entry) => entry.paragraphs.isNotEmpty), isTrue);
  });
}
