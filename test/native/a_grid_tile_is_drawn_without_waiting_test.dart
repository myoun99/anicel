import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The grid's tile pass.
const _tile = 'packages/gpu_engine/rust/src/kernels/timeline/grid/mod.rs';

/// The body of the method that [signature] opens in [file]: to the brace
/// that closes it, at the indent it opens at — whichever line ends the
/// checkout gave the file.
String bodyOf(String file, String signature) {
  final source = File(file).readAsStringSync().replaceAll('\r\n', '\n');
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature is not in the source');
  final close = source.indexOf('\n    }\n', start);
  expect(close, isNot(-1), reason: '$signature has no close at its indent');
  return source.substring(start, close);
}

/// 🚨A GRID TILE IS DRAWN WITHOUT WAITING FOR THE GPU; ITS SCREEN WAITS ONCE.
///
/// The store draws a row's tiles in its paint — 🔬some 16 a frame through a
/// zoom across S5_BA's cut 352 — and each waited for the GPU, so the UI
/// thread's build stood at a median of 11.6 ms a frame against 3.1 with the
/// rows drawing their own cells (main PC, profile, 2026-11-09). The tiles
/// come before their lay on the same queue, and the screen is put up once
/// the GPU has finished all of it: one wait a frame, the screen's, on the
/// engine's thread (`ScreenTexture.present`, `Engine::done_then`).
///
/// ↩️That one wait was the lay's, on the UI thread, until the lay submitted
/// and returned as the canvas's screen does (the-grid-lay-waits-on-the-ui-
/// thread, 2026-11-12): the lay's own pin is in Rust,
/// `a_lay_waits_here_for_nothing_and_is_told_done`.
void main() {
  test('the tile pass submits and does not wait', () {
    final run = bodyOf(_tile, 'pub(crate) fn run(');
    expect(run, contains('queue.submit('));
    expect(run, isNot(contains('wait(')));
  });
}
