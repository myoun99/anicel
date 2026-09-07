// What the brush importers still DROP, measured against real brush files.
//
// 🚨WHY A TOOL AND NOT A PARAGRAPH. The 2026-07-26 audit wrote its numbers
// into a memory file ("CSP Variant has 187 columns and the decoder reads
// 14-18"). Six rounds later those numbers were wrong in both directions and
// nobody could tell without re-reading every file by hand — a card was opened
// on the stale list and closed with 0 lines of code. A measurement that
// cannot be re-run goes stale silently; this one re-runs.
//
// ⚠️IT READS THE DECODER, NOT A LIST. The set of columns/keys we consume is
// scraped out of `sut_decoder.dart` and `abr_decoder.dart` themselves, so the
// coverage number cannot drift away from the code the way a hand list does.
//
// 🔑AND IT SPLITS "PRESENT" FROM "LIVE". The discipline this whole program ran
// on is 「값이 있다 ≠ 켜져 있다」 — every brush parks BrushRotationRandomScale
// at 100, and reading it without its gate turned every tip in the library.
// So an unread column that holds THE SAME VALUE in every brush of every file
// is reported apart from one that VARIES: only the second is a candidate.
//
// Read-only: never modifies the input files.
//
// Usage: dart run tool/brush_import_coverage.dart <file.sut|file.abr ...>
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:anicel/src/services/abr/photoshop_descriptor.dart';
import 'package:anicel/src/services/photoshop/photoshop_byte_reader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'brush_import_coverage: 인자는 .sut/.sutg/.abr 파일 경로들입니다.',
    );
    exitCode = 2;
    return;
  }
  final sutFiles = <String>[];
  final abrFiles = <String>[];
  for (final path in args) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.abr')) {
      abrFiles.add(path);
    } else {
      sutFiles.add(path);
    }
  }
  if (sutFiles.isNotEmpty) _reportSut(sutFiles);
  if (abrFiles.isNotEmpty) _reportAbr(abrFiles);
}

// ---------------------------------------------------------------- CSP .sut

/// The `Variant` columns `sut_decoder.dart` actually consumes, scraped from
/// its `variant['…']` sites. A hand-kept list would be the defect this file
/// exists to remove.
Set<String> _sutColumnsRead() {
  final source = File(
    'lib/src/services/sut/sut_decoder.dart',
  ).readAsStringSync();
  return RegExp(r"variant\['([A-Za-z0-9_]+)'\]")
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toSet();
}

void _reportSut(List<String> paths) {
  final read = _sutColumnsRead();
  // column -> every value it held, across every brush of every file.
  final seen = <String, Set<String>>{};
  final columns = <String>{};
  var brushes = 0;

  for (final path in paths) {
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final hasVariant = database
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .any((row) => row['name'] == 'Variant');
      if (!hasVariant) {
        stdout.writeln('!! ${_base(path)}: Variant 테이블이 없습니다');
        continue;
      }
      final rows = database.select('SELECT * FROM "Variant"');
      for (final row in rows) {
        brushes += 1;
        for (final column in row.keys) {
          columns.add(column);
          (seen[column] ??= <String>{}).add(_valueKey(row[column]));
        }
      }
    } finally {
      database.close();
    }
  }

  final unread = columns.difference(read).toList()..sort();
  final empty = <String>[];
  final parked = <String>[];
  final varying = <String>[];
  for (final column in unread) {
    _classify(column, seen[column], empty, parked, varying);
  }

  stdout.writeln('=' * 72);
  stdout.writeln('CSP .sut — Variant 커버리지');
  stdout.writeln('파일 ${paths.length}개 · 브러시 $brushes개');
  stdout.writeln('열 총수: ${columns.length}');
  stdout.writeln(
    '우리가 읽는 열: ${read.intersection(columns).length}'
    ' (디코더가 이름을 대는 열 ${read.length}개 중)',
  );
  stdout.writeln('안 읽는 열: ${unread.length}');
  stdout.writeln('  ├ 늘 비어 있음(전 브러시 null): ${empty.length}');
  stdout.writeln('  ├ 주차된 기본값(값 한 종류뿐): ${parked.length}');
  stdout.writeln('  └ 브러시마다 다름(진짜 후보): ${varying.length}');
  stdout.writeln('');
  stdout.writeln('--- 후보 ${varying.length}개 (값 예시) ---');
  for (final column in varying) {
    stdout.writeln('  $column = ${_values(seen[column], 6)}');
  }
  stdout.writeln('');
  stdout.writeln('--- 주차된 기본값 ${parked.length}개 ---');
  for (final column in parked) {
    stdout.writeln('  $column = ${_values(seen[column], 2)}');
  }
  stdout.writeln('');
  stdout.writeln('--- 늘 비어 있는 열 ${empty.length}개 ---');
  stdout.writeln('  ${empty.join(' ')}');
}

// ------------------------------------------------------------------- .abr

/// The descriptor keys `abr_decoder.dart` names. ABR keys are 4 characters
/// (a few are shorter), so the scrape is anchored on the accessor call rather
/// than on any 4-letter string in the file.
Set<String> _abrKeysRead() {
  final source = File(
    'lib/src/services/abr/abr_decoder.dart',
  ).readAsStringSync();
  return RegExp(
    r"(?:numberValue|textValue|childDescriptor|items\[|\['|\bvalueOf)"
    r"\(?'([A-Za-z0-9 ]{1,6})'",
  ).allMatches(source).map((m) => m.group(1)!).toSet();
}

void _reportAbr(List<String> paths) {
  final read = _abrKeysRead();
  final seen = <String, Set<String>>{};
  final keys = <String>{};
  var brushes = 0;

  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    final reader = PhotoshopByteReader(bytes);
    reader.readInt16();
    reader.readInt16();
    while (reader.remaining >= 12) {
      final start = reader.offset;
      if (reader.readAscii(4) != '8BIM') {
        reader.offset = start + 1;
        continue;
      }
      final tag = reader.readAscii(4);
      final length = reader.readInt32();
      final end = reader.offset + length;
      if (tag == 'desc') {
        final descriptor = readVersionedDescriptor(
          PhotoshopByteReader(reader.readBytes(length)),
        );
        final list = descriptor['Brsh'];
        if (list is List) {
          for (final entry in list) {
            if (entry is PsDescriptor) {
              brushes += 1;
              _walk(entry, keys, seen);
            }
          }
        }
      }
      reader.offset = end;
    }
  }

  // ⚠️Keys are PATHS now but the decoder names bare keys, so a path counts as
  // read when its LAST segment is one the decoder asks for. That over-credits
  // us (we may read `Hrdn` under one parent and not another) — the direction
  // of the error is deliberate: it never invents work that is already done.
  bool isRead(String path) => read.contains(path.split('.').last);
  final readPaths = keys.where(isRead).toList();
  final unread = keys.where((k) => !isRead(k)).toList()..sort();
  final empty = <String>[];
  final parked = <String>[];
  final varying = <String>[];
  for (final key in unread) {
    _classify(key, seen[key], empty, parked, varying);
  }

  stdout.writeln('');
  stdout.writeln('=' * 72);
  stdout.writeln('Photoshop .abr — 디스크립터 키 커버리지');
  stdout.writeln('파일 ${paths.length}개 · 브러시 $brushes개');
  stdout.writeln('키 총수(경로 기준): ${keys.length}');
  stdout.writeln('우리가 읽는 키: ${readPaths.length}');
  stdout.writeln('안 읽는 키: ${unread.length}');
  stdout.writeln('  ├ 늘 비어 있음: ${empty.length}');
  stdout.writeln('  ├ 주차된 기본값(값 한 종류뿐): ${parked.length}');
  stdout.writeln('  └ 브러시마다 다름(진짜 후보): ${varying.length}');
  stdout.writeln('');
  stdout.writeln('--- 후보 ${varying.length}개 (값 예시) ---');
  for (final key in varying) {
    stdout.writeln('  $key = ${_values(seen[key], 5)}');
  }
  stdout.writeln('');
  stdout.writeln('--- 주차된 기본값 ${parked.length}개 ---');
  for (final key in parked) {
    stdout.writeln('  $key = ${_values(seen[key], 2)}');
  }
}

/// Sorts one unread column/key into the three buckets by its NON-NULL values.
///
/// 🚨`null` is not a value. Counting it as one made the first run report 146
/// CSP candidates where there are far fewer: CSP versions write different
/// column sets, so a column that is `100` in one file and NULL in another
/// looked like it "varied" while carrying one value everywhere it exists.
void _classify(
  String name,
  Set<String>? values,
  List<String> empty,
  List<String> parked,
  List<String> varying,
) {
  final real = (values ?? const <String>{}).where((v) => v != 'null').toSet();
  if (real.isEmpty) {
    empty.add(name);
  } else if (real.length == 1) {
    parked.add(name);
  } else {
    varying.add(name);
  }
}

/// Up to [limit] of the non-null values, sorted, with a count when clipped.
String _values(Set<String>? values, int limit) {
  final real = (values ?? const <String>{}).where((v) => v != 'null').toList()
    ..sort();
  final shown = real.take(limit).join(' · ');
  return real.length > limit ? '$shown … (${real.length}종)' : shown;
}

/// Records every key under [descriptor], QUALIFIED BY ITS PARENT PATH.
///
/// 🚨A flat key set cannot answer the question this tool exists for. Photoshop
/// writes the same `bVTy` (dynamics control) inside szVr, opVr, angleDynamics,
/// roundnessDynamics and more; flattened, it showed 8 distinct values and said
/// nothing about WHICH dynamic is live — and the 2026-07-26 judgment being
/// re-measured ("ABR roundness pressure is inert because
/// `roundnessDynamics.bVTy=0`") is exactly a per-parent claim. The first run
/// of this tool flattened, and the report could neither confirm nor refute it.
///
/// ⚠️A nested descriptor's own entry stays in the set (as `<classId>`) so the
/// key count still covers the container itself.
void _walk(
  PsDescriptor descriptor,
  Set<String> keys,
  Map<String, Set<String>> seen, {
  String prefix = '',
}) {
  descriptor.items.forEach((key, value) {
    final path = '$prefix$key';
    keys.add(path);
    (seen[path] ??= <String>{}).add(_valueKey(value));
    if (value is PsDescriptor) {
      _walk(value, keys, seen, prefix: '$path.');
    } else if (value is List) {
      for (final item in value) {
        if (item is PsDescriptor) {
          _walk(item, keys, seen, prefix: '$path[].');
        }
      }
    }
  });
}

// ------------------------------------------------------------------ shared

/// A value as one comparable string. ⚠️Blobs collapse to their LENGTH, not
/// their bytes — an effector blob differs in every brush, and printing the
/// bytes would drown the report while saying nothing a reader can act on.
String _valueKey(Object? value) {
  if (value == null) return 'null';
  if (value is Uint8List) return 'blob(${value.length})';
  if (value is List<int> && value is! String) return 'blob(${value.length})';
  if (value is PsUnitFloat) return '${value.value}${value.unit}';
  if (value is PsEnum) return '${value.type}.${value.value}';
  if (value is PsDescriptor) return '<${value.classId}>';
  if (value is List) return 'list(${value.length})';
  final text = '$value';
  return text.length > 40 ? '${text.substring(0, 40)}…' : text;
}

String _base(String path) => path.split(RegExp(r'[\\/]')).last;
