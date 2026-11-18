import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/encoded_movie.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨A TEST'S MOVIE THAT FAILS PART WAY LETS THE ENGINE'S JOB GO
/// ([writeEncodedMovie]) — the engine writes one movie at a time, and a job
/// left open answers every later open 「bad open parameters」: on the Mac
/// runner one refused frame failed three more tests that way
/// (round-1091-builds-all-stop-at-their-checks, 2026-11-16).
void main() {
  test('a movie whose writing throws leaves the next one free to open', () {
    final directory = Directory.systemTemp.createTempSync('qa_let_go');
    deleteAfterSessionEnds(directory);
    String path(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';

    final failed = StateError('frame 2 would not draw');
    Object? thrown;
    try {
      writeEncodedMovie(
        path('broken.mp4'),
        frames: 4,
        picture: (frame, _) =>
            frame == 2 ? throw failed : (red: 200, green: 40, blue: 40),
      );
    } on Object catch (error) {
      thrown = error;
    }
    if (thrown == null) {
      // No encoder on this run: the helper skipped before it opened one.
      return;
    }
    expect(thrown, same(failed), reason: 'fixture: frame 2 threw');

    expect(
      writeEncodedMovie(path('next.mp4'), frames: 4),
      isTrue,
      reason: 'the job the throw left was let go',
    );
  });
}
