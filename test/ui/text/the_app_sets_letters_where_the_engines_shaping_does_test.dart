import 'dart:convert';
import 'dart:io';

import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/canvas_letter_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// 🚨THE ENGINE SETS A CANVAS LETTER'S GLYPHS BY ITS OWN SHAPING, WHERE THE
/// APP'S LAYOUT PUT ITS CLUSTER (engine-canvas-letters). Both read
/// `test/fixtures/canvas_letter_clusters.json`: where the app's layout puts
/// each cluster of a line — read off the app on the device, Windows on GLES,
/// 2026-11-07 — and the GPU engine's test that harfrust's advances, run by
/// run, meet those lefts (`letters/glyphs_tests.rs`). Kerning and joined
/// letters ("fi", "fl" in BIZ UDPGothic) are the cases.
///
/// Here the app's half: its layout still puts every cluster there. ⛔A left
/// is never moved to make this pass — a layout that moves them moves what
/// the engine was pinned against, and both halves are read again.
void main() {
  setUpAll(loadTheAppFaces);

  final fixture =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
  final lines = fixture['lines'] as List<dynamic>;

  for (final line in lines.cast<Map<String, dynamic>>()) {
    final clusters = (line['clusters'] as List<dynamic>).cast<String>();
    test('${clusters.join()} — each cluster where the engine reads it', () {
      final painter = TextPainter(
        text: TextSpan(
          text: clusters.join(),
          style: canvasLetterTextStyle(
            TextLetterStyle(
              fontSize: (line['size'] as num).toDouble(),
              bold: line['bold'] as bool,
              italic: line['italic'] as bool,
            ),
            lineHeight: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      final lefts = <double>[];
      var at = 0;
      for (final cluster in clusters) {
        final box = painter
            .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + cluster.length),
            )
            .single;
        lefts.add(box.left);
        at += cluster.length;
      }
      final pinned = (line['lefts'] as List<dynamic>).cast<num>();
      for (var i = 0; i < clusters.length; i++) {
        expect(
          lefts[i],
          moreOrLessEquals(pinned[i].toDouble(), epsilon: 1e-3),
          reason: '"${clusters[i]}" (all: $lefts)',
        );
      }
    });
  }
}

const _fixture = 'test/fixtures/canvas_letter_clusters.json';
