import 'package:flutter/material.dart';

/// The flip's glyph: left and right when [horizontal], up and down when not
/// — the view pill's, which every flip button wears.
///
/// ★THE THIRD MADE IT ONE (I-165, 2026-11-05): the view pill and the tool
/// settings' flip (`ToolSettingAction.flip`, F-527) each spelled it out,
/// and the transform box's pill wears it too.
Widget flipGlyph({required bool horizontal}) => horizontal
    ? const Icon(Icons.flip)
    : const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip));
