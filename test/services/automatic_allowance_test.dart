import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/memory_allowance.dart';

/// The automatic allowance is the DEVICE's, not the sum of the cache laws.
///
/// 유저 2026-09-14 (C-ipad-crash ③): 「메모리 상한 초기값 하드코딩하지 말 것.
/// 기기 RAM 용량 따라 설정」 — a 48GB PC and a 12GB iPhone both showed
/// 5,560MB, because the laws' fixed lines (playback 600, uploads 640, …)
/// stop scaling at 6GB. 유저 2026-09-16 (memory-allowance-Q1): half of what
/// the OS gives this app where the OS says so, half the RAM where it does
/// not; and (Q2's note) never under what the app needs to run.
void main() {
  const mb = 1024 * 1024;
  const floors = 512 * mb;
  const laws = 5560 * mb;

  int auto({int? ram, int? limit}) => automaticAllowanceBytes(
    physicalMemoryBytes: ram,
    appMemoryLimitBytes: limit,
    floorBytes: floors,
    lawsTotalBytes: laws,
  );

  test('where the OS gives this app a limit of its own, half of it — the '
      'iPhone', () {
    // iPhone 17 Pro Max reads 11,694MB of RAM, but iOS lets the app hold
    // less than that; the number that matters is the app's own limit.
    expect(auto(ram: 11694 * mb, limit: 6000 * mb), 3000 * mb);
  });

  test('where it does not, half the RAM — the desktops', () {
    expect(auto(ram: 48 * 1024 * mb), 24 * 1024 * mb);
    expect(auto(ram: 4096 * mb), 2048 * mb);
    // A limit of 0 is 「none」, not a tiny limit.
    expect(auto(ram: 4096 * mb, limit: 0), 2048 * mb);
  });

  test('never under the floors — the least the app runs on', () {
    expect(auto(ram: 512 * mb), floors);
    expect(auto(ram: 3000 * mb, limit: 900 * mb), floors);
  });

  test('no engine, no RAM known: the laws as they are, byte for byte', () {
    expect(auto(), laws);
    expect(auto(limit: 6000 * mb), laws, reason: 'a limit without a RAM figure is not a device');
  });
}
