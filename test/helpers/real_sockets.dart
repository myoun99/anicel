import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// THIS FILE'S TESTS TALK TO SERVERS ON REAL SOCKETS — not to the HTTP that
/// `TestWidgetsFlutterBinding` answers every request with, a 400 and an
/// empty body (flutter_test's `_binding_io.dart` sets [HttpOverrides.global]
/// when the binding starts). Call it first in `main`.
///
/// 🎯A FILE ALONE NEVER STARTED THE BINDING; A BUNDLE DOES (card
/// the-wide-check-takes-five-hours, 보드/인프라 2026-11-22). In a bundle
/// (tool/test_bundles.dart) the first file that declares a `testWidgets`
/// starts it for the whole isolate before any test runs. The census saw
/// every file that opened a socket red there — a 400 for a 200, a server
/// that heard nothing — and green alone.
void talkOverRealSockets() {
  HttpOverrides? before;
  setUpAll(() {
    before = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = before);
}
