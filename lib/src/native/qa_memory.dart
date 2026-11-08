// The engine's Rust library carries the memory questions (rust/src/lib.rs),
// and its names are found in that code asset — no library opened, no path
// named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'gpu_engine_asset.dart';

@Native<Int64 Function()>(symbol: 'qa_physical_memory_bytes')
external int _physical();

@Native<Int64 Function()>(symbol: 'qa_process_footprint_bytes')
external int _footprint();

@Native<Int64 Function()>(symbol: 'qa_available_memory_bytes')
external int _available();

@Native<Int64 Function()>(symbol: 'qa_app_memory_limit_bytes')
external int _appLimit();

/// What the OS says of memory, in the engine (native/memory). Each answer
/// is null where the platform will not say — the engine answers 0 there.
/// ↩️Until the connection round (connection-round-checklist H, 2026-11-08)
/// these were the C engine's, null as well wherever it did not load.
abstract final class QaMemory {
  /// The device's physical RAM — callers keep their desktop-class default
  /// where it is null. This is what lets the hot cel budget scale to the
  /// machine.
  static int? get physicalMemoryBytes {
    final said = debugPhysicalMemoryBytes;
    return said != null ? said() : _said(_physical());
  }

  /// Test seam: the RAM a test says this machine has, or null — the
  /// machine's own.
  ///
  /// 🚨A TEST RUNS ON NO MACHINE UNDER 6GB, and that is where the device
  /// laws stop scaling: a quarter of the RAM clamps to 1536MB, the same as
  /// no RAM at all, so a budget that read none passed every pin there.
  /// Four lived through the move to the engine — the session's laws and the
  /// viewers' (관제 2026-11-08 16:21, connection-round-checklist: 「넣을
  /// 자리가 없으면 QaMemory 의 답을 시험에서 바꿔 끼울 한 자리」 — a 4GB
  /// tablet's 1024MB against the 1536MB). Only the RAM: no other answer
  /// feeds a law a test can only reach on a smaller machine.
  @visibleForTesting
  static int? Function()? debugPhysicalMemoryBytes;

  /// What THIS PROCESS is holding.
  ///
  /// The number a jetsam report calls `rpages × pageSize` — the one that
  /// decides whether the app is about to be killed. [physicalMemoryBytes]
  /// answers a different question and has been standing in for it.
  static int? get processFootprintBytes => _said(_footprint());

  /// How much more this process may take before the OS stops it.
  ///
  /// 🚨On iOS this is the REAL ceiling — an app's allowance is neither the
  /// device's free RAM nor a fraction of its total, so a budget scaled
  /// from the machine can be double what the process is allowed to have.
  static int? get availableMemoryBytes => _said(_available());

  /// What the OS lets THIS APP hold all in — held plus still available —
  /// or null where the OS gives an app no limit of its own.
  ///
  /// ⛔Not [availableMemoryBytes] doubled up: on a desktop that one is the
  /// MACHINE's free memory, which is not a limit on this app at all. Only
  /// iOS answers here, and there it is the ceiling a jetsam decision is
  /// made against — the number the automatic allowance halves.
  static int? get appMemoryLimitBytes => _said(_appLimit());

  static int? _said(int bytes) => bytes <= 0 ? null : bytes;
}
