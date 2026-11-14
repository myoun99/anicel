import 'dart:convert';

import 'package:flutter/foundation.dart' show LicenseEntry;

import 'licence_entry.dart';

/// The licence entries of the Rust crates' notices file — one a licence
/// text, naming each crate under it. tool/crate_notices.dart writes the file
/// from the GPU engine's lock; only its `notices` are read here.
Iterable<LicenseEntry> crateLicenceEntries(String file) sync* {
  final notices = (jsonDecode(file) as Map<String, dynamic>)['notices'];
  for (final notice in (notices as List).cast<Map<String, dynamic>>()) {
    yield licenceEntry(
      (notice['crates'] as List).cast<String>(),
      notice['text'] as String,
    );
  }
}
