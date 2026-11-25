import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_door.dart';
import '../../tool/board_server.dart';
import '../helpers/real_sockets.dart';
import '../helpers/temp_dir.dart';

/// AN ISOLATE SERVES THE BOARD IT WAS LAST GIVEN ([boardIs]; census 11-22,
/// card the-wide-check-takes-five-hours). In a bundle three test files
/// share one isolate and each makes it the server of a board of its own.
void main() {
  talkOverRealSockets();

  late Directory dir;
  late HttpServer server;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('board-given-twice');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(answerAll(server));
  });

  tearDownAll(() async {
    await server.close(force: true);
    deleteTempQuietly(dir);
  });

  Future<String> recordsOf(String id) async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/api/records?id=$id'),
    )).close();
    return response.transform(utf8.decoder).join();
  }

  test('a second board handed to the isolate is the one it serves', () async {
    for (final name in ['first', 'second']) {
      final records = File('${dir.path}/$name/board.jsonl')
        ..createSync(recursive: true)
        ..writeAsStringSync('${jsonEncode({
          'kind': 'item',
          'id': 'T-$name',
          'ts': '2026-11-22T23:00:00.000000',
        })}\n');
      boardIs(
        records: records.path,
        gh: '${dir.path}/no-gh-here',
        gitRoot: dir.path,
        door: const LoopbackDoor(),
      );
    }

    expect(await recordsOf('T-second'), contains('"T-second"'));
    expect(await recordsOf('T-first'), isNot(contains('"T-first"')));
  });
}
