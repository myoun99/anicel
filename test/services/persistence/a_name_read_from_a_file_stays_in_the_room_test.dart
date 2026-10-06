import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaCarry;
import 'package:anicel/src/services/media/media_byte_source.dart'
    show MediaFileBytes;
import 'package:anicel/src/services/persistence/media_blob_codec.dart'
    show mediaFramedEntrySuffix;
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A NAME READ FROM A PROJECT FILE DOES NOT LEAVE THE ROOM** (card
/// `a-name-read-from-a-file-becomes-a-path`, 유저 2026-10-06: 「그건만
/// 지금고치자」).
///
/// The room keeps bytes under NAMES, and the names come out of project
/// files — a carry's from its asset's `carriedAs`, an entry's from what the
/// document says it holds — and a project file comes from anywhere. Read
/// off the code that day: a name saying `../..` was looked for, written and
/// DELETED outside the room, by nothing more than opening that file and
/// saving it.
///
/// Every verb of the room that makes a path of a name is here, each handed
/// a name that points at a neighbour of the room: nothing out there is
/// read, written or removed.
void main() {
  late Directory root;
  late MediaStagingStore store;

  /// A folder beside the room's parent — two steps up from the room, as the
  /// names below say.
  late Directory outside;

  final secret = Uint8List.fromList(List<int>.generate(4096, (i) => i & 0xFF));

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_room_names_test');
    store = MediaStagingStore(directoryPath: '${root.path}/room/Staged');
    Directory(store.directoryPath).createSync(recursive: true);
    outside = Directory('${root.path}/outside')..createSync();
    MediaStagingStore.debugStageInline = true;
  });

  tearDown(() {
    MediaStagingStore.debugStageInline = false;
    deleteTempQuietly(root);
  });

  /// The name of [file] in [outside], as a project file would have to spell
  /// it to reach there from the room.
  String reaching(String file) => '../../outside/$file';

  /// A carry whose `carriedAs` is [name] — whole, since it holds a dash.
  MediaCarry carried(String name) =>
      (poolPath: '${root.path}/take.wav'.replaceAll(r'\', '/'), token: name);

  File neighbour(String file) => File('${outside.path}/$file');

  /// Everything in [outside], by name — what 「nothing was written there」
  /// is read off, whatever name a write would have chosen (a `.part`, a
  /// framed twin).
  List<String> outsideNow() => [
    for (final entity in outside.listSync())
      entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
  ]..sort();

  group('a carry named out of the room', () {
    setUp(() {
      neighbour('victim-1.bin').writeAsBytesSync(secret);
      neighbour('victim-1.bin$mediaFramedEntrySuffix').writeAsBytesSync(secret);
    });

    test('is not found: no file out there is the room\'s copy', () {
      expect(store.find(carried(reaching('victim-1.bin'))), isNull);
    });

    test('🚨and letting go of it removes nothing out there — neither '
        'spelling', () {
      store.retire(carried(reaching('victim-1.bin')));

      expect(outsideNow(), [
        'victim-1.bin',
        'victim-1.bin$mediaFramedEntrySuffix',
      ]);
      expect(neighbour('victim-1.bin').readAsBytesSync(), secret);
    });

    test('nor does a reader letting go of it after the save did', () {
      final carry = carried(reaching('victim-1.bin'));
      final letGo = store.hold(carry);
      store.retire(carry);
      letGo();

      expect(outsideNow(), [
        'victim-1.bin',
        'victim-1.bin$mediaFramedEntrySuffix',
      ]);
    });
  });

  group('bytes handed over under a name out of the room are not written',
      () {
    late String original;

    setUp(() {
      original = '${root.path}/take.wav'.replaceAll(r'\', '/');
      File(original).writeAsBytesSync(secret);
    });

    test('a file carried under it', () async {
      final staged = await store.stage(carried(reaching('planted-1')));

      expect(staged, isNull);
      expect(outsideNow(), isEmpty);
    });

    test('a take made under it', () async {
      final staged = await store.stageCarriedBytesInMemory(
        carried(reaching('planted-1')),
        secret,
      );

      expect(staged, isNull);
      expect(outsideNow(), isEmpty);
    });

    test('bytes another project holds, pasted under it', () async {
      final staged = await store.stageCarriedBytesFrom({
        carried(reaching('planted-1')): MediaFileBytes(original),
      });

      expect(staged, isEmpty);
      expect(outsideNow(), isEmpty);
    });

    test('🚨an entry a save leaves behind that says it is called so', () async {
      final archive = '${root.path}/scene.anicel';
      File(archive).writeAsBytesSync(secret);

      await store.keepLeftBehind(archive, [
        (name: reaching('planted-1.bin'), offset: 0, length: secret.length),
        (
          name: reaching('planted-2.bin$mediaFramedEntrySuffix'),
          offset: 0,
          length: secret.length,
        ),
      ]);

      expect(outsideNow(), isEmpty);
    });
  });

  test('⛔one line of the room joins its folder and a name — the one that '
      'asks whether it is a name', () {
    // A verb added later that wrote `'$directoryPath/$name'` for itself
    // would pass every test above: none of them knows it exists.
    final joins = [
      for (final line in File(
        'lib/src/services/persistence/media_staging_store.dart',
      ).readAsLinesSync())
        if (!line.trimLeft().startsWith('//') &&
            RegExp(r'\$\{?directory(Path)?\}?/').hasMatch(line))
          line.trim(),
    ];

    expect(joins, [
      r"isOneStoredName(name) ? '$directoryPath/$name' : null;",
    ]);
  });

  group('⚠️the same verbs keep working for a name that is one', () {
    late String original;

    /// The whole name a carry is minted — `<path hash>-<random>-<file>`.
    const minted = '1a2b3c4d-9f8e7d6c-take.wav';

    setUp(() {
      original = '${root.path}/take.wav'.replaceAll(r'\', '/');
      File(original).writeAsBytesSync(secret);
    });

    test('staged, found, and gone when the save lets go of it', () async {
      final carry = carried(minted);

      final staged = await store.stage(carry);
      expect(staged, isNotNull);
      expect(store.find(carry)?.path, staged!.path);
      expect(staged.path, startsWith('${store.directoryPath}/$minted'));

      store.retire(carry);
      expect(store.find(carry), isNull);
      expect(File(staged.path).existsSync(), isFalse);
    });

    test('and an entry left behind under it is kept in the room', () async {
      final archive = '${root.path}/scene.anicel';
      File(archive).writeAsBytesSync(secret);

      await store.keepLeftBehind(archive, [
        (name: minted, offset: 16, length: 1024),
      ]);

      expect(
        File('${store.directoryPath}/$minted').readAsBytesSync(),
        secret.sublist(16, 16 + 1024),
      );
      expect(store.find(carried(minted)), isNotNull);
    });
  });
}
