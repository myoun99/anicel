import 'package:anicel/src/native/engine_faces.dart';
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each file is handed to the engine before the next is read', () async {
    final files = [
      for (final face in AppTypography.canvasLetterFaces) ...face.files,
    ];
    final bytes = {
      for (final file in files)
        file: Uint8List.sublistView(await rootBundle.load(file)),
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

    expect(handedAtEachRead, [for (var i = 0; i < files.length; i += 1) i]);
    expect(GpuFacesHanding.debugFilesHanded - before, files.length);
  });
}
