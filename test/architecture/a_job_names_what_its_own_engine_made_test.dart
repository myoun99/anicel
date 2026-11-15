import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/engine_verbs.dart';
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
///
/// 🚨THE LEDGER IS OF BYTES ON BOTH SIDES (🗣️관제 2026-11-14 05:16,
/// the-ui-thread-never-enters-the-driver 1b: 「그 문을 지나는 타입 집합 =
/// 다트 장부 `_ofNoEngine` 의 타입 … 제3의 명단을 만들지 않는다」): what a
/// read of the ledger names, the engine hands out by its door for what
/// holds nothing of a device (rust `device::hands_bytes`) — bound to no
/// engine, let go of where its free is called. A ledgered read of what
/// an engine hands out as its own is red here; what a thing of that door
/// may hold is the crate's own scan (`kernels/shared/one_handing_out.rs`).
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

  test('what the ledger reads past the engine, the engine hands out bound '
      'to no engine: a thing of bytes on both sides', () {
    final ofBytes = _typesHandedOutAsBytes(
      File(
        'packages/gpu_engine/lib/src/engine_ffi.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
      engineVerbBodies(),
    );
    expect(
      ofBytes,
      contains('DabTexture'),
      reason: '⛔premise: the scan finds what the bytes\' door hands out',
    );
    final named = {
      for (final read in _ofNoEngine.keys) read: _typeRead(package, read),
    };
    expect(
      {
        for (final MapEntry(key: read, value: type) in named.entries)
          if (!ofBytes.contains(type)) read: type,
      },
      isEmpty,
      reason:
          'the ledger takes these reads for bytes in memory, and the '
          'engine hands what they name out as an engine\'s own — or the '
          'scan cannot tell its type (null). Name it through the engine '
          'the job is on and take it off the ledger; or, where it holds '
          'nothing of a device, hand it out with `device::hands_bytes`',
    );
  });

  test('the scan reads the type a read names, and the door its maker '
      'hands it out by', () {
    const held = '''
final class GpuKept implements Finalizable {
  final Pointer<rust.Kept> _thing;
}

class GpuShown {
  Pointer<rust.Shown> get _thing => rust.shownThing(_shown);
}

void run(GpuKept? kept, GpuShown shown, GpuKept either) {}
void show(GpuShown either) {}
''';
    expect(_typeRead(held, 'kept?._thing'), 'Kept');
    expect(_typeRead(held, 'shown._thing'), 'Shown');
    expect(_typeRead(held, 'either._thing'), isNull, reason: 'two types');
    expect(_typeRead(held, 'kept._other'), isNull, reason: 'not held');
    const bound = '''
@Native<Pointer<Kept> Function(Pointer<Uint8>, Size)>(
  symbol: 'gpu_engine_kept_new',
)
external Pointer<Kept> keptNew(Pointer<Uint8> bytes, int length);

@Native<
  Pointer<Shown> Function(
    Pointer<Engine>,
  )
>(symbol: 'gpu_engine_shown_new')
external Pointer<Shown> shownNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Kept>)>(symbol: 'gpu_engine_kept_free')
external void keptFree(Pointer<Kept> kept);

@Native<Pointer<Both> Function()>(symbol: 'gpu_engine_both_new')
external Pointer<Both> bothNew();

@Native<Pointer<Both> Function(Pointer<Engine>)>(symbol: 'gpu_engine_both_on')
external Pointer<Both> bothOn(Pointer<Engine> engine);
''';
    const verbs = {
      'gpu_engine_kept_new':
          '    Kept::new(bytes).map_or(std::ptr::null_mut(), hands_bytes)',
      'gpu_engine_shown_new': '    engine.hands(Shown::default())',
      'gpu_engine_kept_free': '    unsafe { let_go_bytes(kept) };',
      'gpu_engine_both_new': '    hands_bytes(Both::default())',
      'gpu_engine_both_on': '    engine.hands(Both::default())',
    };
    expect(_typesHandedOutAsBytes(bound, verbs), {'Kept'});
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
  'faces._faces': (
    1,
    'the faces are font files in memory (`GpuFaces`, rust '
        'kernels/letters `Faces`): made with no engine',
  ),
};

/// The type — as the engine's bindings name it — of the pointer [read]
/// names in [code], as the ledger writes a read (`tip?._texture`): what
/// the class of its receiver holds under that name. Null where [code]
/// declares the receiver as no one `Gpu…` class, or that class holds no
/// such pointer.
String? _typeRead(String code, String read) {
  final [receiver, pointer] = read.replaceAll('?', '').split('.');
  final declared = {
    for (final typed in RegExp(
      '\\b(Gpu\\w+)\\??\\s+$receiver\\b',
    ).allMatches(code))
      typed[1]!,
  };
  if (declared.length != 1) {
    return null;
  }
  final body = RegExp(
    'class ${declared.single}\\b[^{]*\\{\\n([\\s\\S]*?)\\n\\}',
  ).firstMatch(code)?[1];
  return body == null
      ? null
      : RegExp(
          'Pointer<rust\\.(\\w+)>\\??\\s+(?:get\\s+)?$pointer\\b',
        ).firstMatch(body)?[1];
}

/// The types — as the bindings of [ffi] name them — the engine hands out
/// bound to no engine: each one a verb of [verbs] makes through the
/// bytes' door (`device::hands_bytes`, called or handed on as the
/// function it is), and none through the engine's (`Engine::hands`).
Set<String> _typesHandedOutAsBytes(String ffi, Map<String, String> verbs) {
  final made = <String, Set<bool>>{};
  for (final bound in RegExp(
    r'@Native<\s*Pointer<(\w+)>\s+Function\((?:(?!@Native)[\s\S])*?'
    r"symbol:\s*'(gpu_engine_\w+)'",
  ).allMatches(ffi)) {
    final body = verbs[bound[2]!] ?? '';
    (made[bound[1]!] ??= {}).addAll([
      if (body.contains('hands_bytes')) true,
      if (body.contains('.hands(')) false,
    ]);
  }
  return {
    for (final MapEntry(key: type, value: doors) in made.entries)
      if (doors.length == 1 && doors.single) type,
  };
}

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
