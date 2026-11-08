import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The grid's tile pass and the pass that lays its tiles on a screen.
const _tile = 'packages/gpu_engine/rust/src/kernels/timeline/grid/mod.rs';
const _lay = 'packages/gpu_engine/rust/src/kernels/timeline/grid/lay.rs';

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
/// come before their lay on the same queue, and the lay waits for the GPU
/// before the screen is shown: one wait a frame, the lay's.
void main() {
  test('the tile pass submits and does not wait', () {
    final run = bodyOf(_tile, 'pub(crate) fn run(');
    expect(run, contains('queue.submit('));
    expect(run, isNot(contains('wait(')));
  });

  test('the lay waits for the GPU before its screen is shown', () {
    final lay = bodyOf(_lay, 'pub(crate) fn lay(');
    expect(lay, contains('queue.submit('));
    expect(lay, contains('engine.wait()'));
  });
}
