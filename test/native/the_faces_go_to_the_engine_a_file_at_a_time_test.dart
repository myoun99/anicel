import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:anicel/src/native/engine_faces.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

/// 🚨THE ENGINE'S FACES GO OVER A FILE AT A TIME (board
/// engine-faces-load-35-mb-on-the-ui-thread, 🔬저장 11-14: the 35 MB of
/// the bundled faces copied in one stop — 50–120 ms of the UI the first
/// time letters were set): each file is handed to the engine as soon as
/// the bundle has read it, before the next is asked for, so the one copy
/// each costs falls in the turn its own read ends.
///
/// 🚨AND WHERE THE BUNDLE IS FILES, THE ENGINE MAPS THEM AND NO ONE READS
/// THEM (engine-fonts-held-twice, 🗣️유저 「사본이나 ram에있는걸 최대한
/// 없애고싶어서」): the bundle is asked for none of them — nor where it
/// lies stored in the APK, as Android's AssetManager says
/// (engine-fonts-held-twice-Q1, 유저 11-22 「글꼴을 압축 없이 두고 둘 다
/// 비춰 쓴다」).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files = [
    for (final face in AppTypography.canvasLetterFaces) ...face.files,
  ];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The bundle's reads, each as the number of files handed when it was
  /// asked — answered with the repo's own files.
  Future<List<int>> readsWhileReading() async {
    final bytes = {
      for (final file in files)
        file: Uint8List.sublistView(await rootBundle.load(file)),
    };
    final handedAtEachRead = <int>[];
    final before = GpuFacesHanding.debugFilesHanded;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      handedAtEachRead.add(GpuFacesHanding.debugFilesHanded - before);
      final asked = Uri.decodeFull(
        String.fromCharCodes(message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        )),
      );
      return ByteData.sublistView(bytes[asked]!);
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final faces = await EngineFaces.read();
    faces.free();
    expect(GpuFacesHanding.debugFilesHanded - before, files.length);
    return handedAtEachRead;
  }

  void bundleIn(String? folder) {
    final was = EngineFaces.bundleFolder;
    EngineFaces.bundleFolder = folder;
    addTearDown(() => EngineFaces.bundleFolder = was);
  }

  test('each file is handed to the engine before the next is read', () async {
    bundleIn(null);

    expect(await readsWhileReading(), [
      for (var i = 0; i < files.length; i += 1) i,
    ]);
  });

  test('where the bundle is files, the engine maps each and the bundle reads '
      'none', () async {
    // The repo's root is a folder its keys are paths in.
    bundleIn(Directory.current.path);

    expect(await readsWhileReading(), isEmpty);
  });

  test('a file the engine cannot map is read through the bundle', () async {
    bundleIn('${Directory.current.path}/no-such-bundle');

    expect(await readsWhileReading(), [
      for (var i = 0; i < files.length; i += 1) i,
    ]);
  });

  /// The bundle lying in an APK: the six files one after another in one
  /// file, past a few bytes, as stored entries lie in it — and the OS
  /// asked where each lies answering [answer] of each one's span (null:
  /// held compressed). The keys it was asked of, in order.
  Future<List<List<String>>> inAnApk(
    Object? Function(int place, Map<String, Object> span) answer,
  ) async {
    final apk = File(
      '${Directory.systemTemp.createTempSync('anicel-apk-').path}/base.apk',
    );
    addTearDown(() => apk.parent.deleteSync(recursive: true));
    final spans = <Map<String, Object>>[];
    final holder = BytesBuilder(copy: false)..add([1, 2, 3]);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      spans.add({
        'path': apk.path,
        'offset': holder.length,
        'length': bytes.length,
      });
      holder.add(bytes);
    }
    apk.writeAsBytesSync(holder.takeBytes());

    final asked = <List<String>>[];
    messenger.setMockMethodCallHandler(AppStorage.channel, (call) async {
      expect(call.method, 'bundledFiles');
      final keys = (call.arguments as List).cast<String>();
      asked.add(keys);
      return [
        for (final (place, _) in keys.indexed) answer(place, spans[place]),
      ];
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(AppStorage.channel, null),
    );
    final was = EngineFaces.bundleInTheApk;
    EngineFaces.bundleInTheApk = true;
    addTearDown(() => EngineFaces.bundleInTheApk = was);
    bundleIn(null);
    return asked;
  }

  test('where the bundle lies stored in the APK, the engine maps each from '
      'where the OS says and the bundle reads none', () async {
    final asked = await inAnApk((_, span) => span);

    expect(await readsWhileReading(), isEmpty);
    expect(asked, [files]);
  });

  test('a file the APK holds compressed is read through the bundle', () async {
    // The OS has no span of the second: openFd refuses a compressed entry.
    await inAnApk((place, span) => place == 1 ? null : span);

    expect(await readsWhileReading(), [1]);
  });

  test('if the OS says nothing, every file is read through the bundle', () async {
    await inAnApk((_, _) => throw PlatformException(code: 'gone'));

    expect(await readsWhileReading(), [
      for (var i = 0; i < files.length; i += 1) i,
    ]);
  });

  test('a file in the folder is the whole of its file; one not there, or '
      'any where there is no folder, none', () {
    final folder = Directory.current.path;
    final file = files.first;

    expect(EngineFaces.spansInFolder(folder, [file, 'no-such.ttf']), [
      (
        path: '$folder/$file',
        offset: 0,
        length: File(file).lengthSync(),
      ),
      null,
    ]);
    expect(EngineFaces.spansInFolder(null, [file]), [null]);
  });

  test("the bundle's folder is where Flutter's embedder reads it", () {
    expect(
      EngineFaces.bundleFolderOf(
        r'C:\Program Files\Anicel\Anicel.exe',
        'windows',
      ),
      'C:/Program Files/Anicel/data/flutter_assets',
    );
    expect(
      EngineFaces.bundleFolderOf('/opt/anicel/anicel', 'linux'),
      '/opt/anicel/data/flutter_assets',
    );
    expect(
      EngineFaces.bundleFolderOf(
        '/Applications/Anicel.app/Contents/MacOS/Anicel',
        'macos',
      ),
      '/Applications/Anicel.app/Contents/MacOS/../Frameworks/App.framework/'
      'Resources/flutter_assets',
    );
    expect(
      EngineFaces.bundleFolderOf('/var/x/Runner.app/Runner', 'ios'),
      '/var/x/Runner.app/Frameworks/App.framework/flutter_assets',
    );
    expect(
      EngineFaces.bundleFolderOf('/system/bin/app_process64', 'android'),
      isNull,
    );
  });
}
