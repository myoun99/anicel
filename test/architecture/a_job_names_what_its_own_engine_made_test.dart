import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart';

/// 🚨A JOB NAMES WHAT ITS OWN ENGINE MADE: in the engine's package, no
/// object's pointer is read by another object's job but through the engine
/// the job is on (`GpuEngine._its`), which refuses another engine's by
/// name.
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — an app that opens a second
/// engine has two, and wgpu ends the process at a job that names a buffer
/// of the one to the other (🔬2026-11-13, `Cannot get BufferId(2,2), found
/// other resource BufferId(2,1)`: a picture of the engine let go, carried
/// by the next one's kernels) — or takes another buffer for it, with no
/// word at all.
///
/// ⛔SO THIS SCANS THE SOURCE: a read written past the way passes every
/// test that has one engine, which is every test but the way's own
/// (`test/native/what_one_engine_made_is_named_to_no_other_test.dart`),
/// and the app has one for all but a moment of its life.
void main() {
  final package = codeOfLines(
    File(
      'packages/gpu_engine/lib/gpu_engine.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n'),
  );

  test('no job reads the pointer of an object not its own past the engine '
      'it is on, outside the ledger — and every ledger entry is still '
      'read', () {
    final reads = _readsPastTheEngine(package);
    expect(
      _pointersOf(package),
      containsAll(['_pool', '_composite', '_picture', '_texture']),
      reason: '⛔premise: the scan finds the pointers the objects hold',
    );
    expectCountsMatchLedger(
      {for (final MapEntry(:key, :value) in reads.entries) key: value.length},
      {
        for (final MapEntry(:key, value: (count, _)) in _ofNoEngine.entries)
          key: count,
      },
      grew:
          'name what another object holds through the engine the job is '
          'on — `_engine._its(pool)._pool` — which refuses another '
          'engine\'s by name. What holds nothing a device made goes in '
          'the ledger, with why',
      paidOff: 'these are read so no more — take them off the list',
      hits: reads,
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy({
      for (final MapEntry(:key, value: (_, why)) in _ofNoEngine.entries)
        key: why,
    });
  });

  test('the scan sees a read past the engine, whichever way it is '
      'written, and none that is its object\'s own or goes through the '
      'engine', () {
    const planted = '''
class GpuThing {
  final Pointer<rust.Thing> _thing;
  Pointer<rust.Other> get _other;
  void run(GpuThing a, GpuThing? b) {
    rust.run(_thing, this._thing, _engine._its(a)._thing);
    rust.run(a._thing, b?._thing ?? nullptr, (a)._other);
  }
}
''';
    expect(_pointersOf(planted), {'_thing', '_other'});
    expect(_readsPastTheEngine(planted), {
      'a._thing': [6],
      'b?._thing': [6],
      ')._other': [6],
    });
  });
}

/// Reads of what holds NOTHING A DEVICE MADE — bytes in memory, made by no
/// engine and uploaded by whichever job names them — each with how many
/// there are.
const _ofNoEngine = <String, (int, String)>{
  'tip?._texture': (
    1,
    'a dab\'s tip is a bitmap in memory (`GpuDabTexture`, rust '
        'kernels/dab `Texture`: its words): made with no engine',
  ),
  'paper?._texture': (
    2,
    'a stroke\'s paper is the same bitmap in memory a tip is '
        '(`GpuDabTexture`): made with no engine',
  ),
  'made._made': (
    1,
    'what a plug-in made is bytes in memory (`GpuPutPicture`, rust '
        '`PutPicture`: an `Arc<[u8]>`), which the run that names it '
        'uploads',
  ),
  'faces._faces': (
    1,
    'the faces are font files in memory (`GpuFaces`, rust '
        'kernels/letters `Faces`): made with no engine',
  ),
};

/// The names of the pointers the package's objects hold: each field and
/// getter of a `Pointer<rust.…>` — but the engine's own, which are what a
/// job is ON, not what one names.
Set<String> _pointersOf(String code) => {
  for (final held in RegExp(
    r'Pointer<rust\.\w+>\??\s+(?:get\s+)?(_\w+)\s*(?:;|=>|=[^=])',
  ).allMatches(code))
    held[1]!,
}..removeAll(const {'_engine', '_fill', '_fillKernel'});

/// Each read in [code] of a pointer ([_pointersOf]) of an object not the
/// reader's own that does not go through the engine — as it is written,
/// receiver and all — with the lines it is on.
Map<String, List<int>> _readsPastTheEngine(String code) {
  final pointers = _pointersOf(code);
  final reads = <String, List<int>>{};
  for (final (index, line) in code.split('\n').indexed) {
    final past = line.replaceAll(RegExp(r'\b_its\(\w+\)\._\w+'), '');
    for (final read in RegExp(r'(\w+|\))(\??)\.(_\w+)').allMatches(past)) {
      final [receiver!, asked!, pointer!] = read.groups([1, 2, 3]);
      if (pointers.contains(pointer) &&
          receiver != 'this' &&
          receiver != 'super') {
        (reads['$receiver$asked.$pointer'] ??= []).add(index + 1);
      }
    }
  }
  return reads;
}
