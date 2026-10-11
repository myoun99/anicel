import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/camera_path_settings.dart';
import '../text/app_strings.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';

/// How the canvas shows a camera's path (I-89 ④), as rows of the canvas's
/// ⚙ list: what it shows, how much of it, the frames apart its time crosses
/// stand and how far around the playhead it reaches — each written through
/// [onChanged].
///
/// Each row reads the live value ([CameraPathSettings.settings]) at its
/// press, so a list left open never writes back a value it opened on.
List<PanelFlyoutEntry> cameraPathSettingsRows(
  ValueChanged<CameraPathSettings> onChanged,
) {
  final strings = AppText.strings;
  return [
    PanelFlyoutHeader(strings.cameraPath),
    _choices<CameraPathShow>(
      'camera-path-show',
      {
        CameraPathShow.off: strings.cameraPathOff,
        CameraPathShow.space: strings.cameraPathSpace,
        CameraPathShow.spaceAndTime: strings.cameraPathSpaceTime,
      },
      (settings) => settings.show,
      (show) => onChanged(_now.copyWith(show: show)),
    ),
    _choices<CameraPathRange>(
      'camera-path-range',
      {
        CameraPathRange.allKeys: strings.cameraPathAllKeys,
        CameraPathRange.aroundPlayhead: strings.cameraPathAroundPlayhead,
      },
      (settings) => settings.range,
      (range) => onChanged(_now.copyWith(range: range)),
    ),
    _frames(
      'camera-path-tick-every',
      strings.cameraPathTickEvery,
      (settings) => settings.tickEvery,
      (frames) => onChanged(_now.copyWith(tickEvery: frames)),
    ),
    _frames(
      'camera-path-around',
      strings.cameraPathAround,
      (settings) => settings.around,
      (frames) => onChanged(_now.copyWith(around: frames)),
    ),
  ];
}

CameraPathSettings get _now => CameraPathSettings.settings.value;

/// One of [labels] to choose, the [chosen] one tinted.
PanelFlyoutRow _choices<T extends Enum>(
  String keyValue,
  Map<T, String> labels,
  T Function(CameraPathSettings settings) chosen,
  ValueChanged<T> choose,
) => PanelFlyoutRow(
  keyValue: keyValue,
  listenable: CameraPathSettings.settings,
  builder: (_) => PillStrip(
    items: [
      for (final MapEntry(key: value, value: label) in labels.entries)
        PillItem(
          keyValue: '$keyValue-${value.name}',
          label: label,
          selected: chosen(_now) == value,
          onTap: () => choose(value),
        ),
    ],
  ),
);

/// A count of frames, one at least, named [label]: what [read] says, turned
/// by a drag, its steps and its pencil into [write].
PanelFlyoutRow _frames(
  String keyValue,
  String label,
  int Function(CameraPathSettings settings) read,
  ValueChanged<int> write,
) => PanelFlyoutRow(
  keyValue: '$keyValue-row',
  label: label,
  listenable: CameraPathSettings.settings,
  builder: (_) => DragValueLabel(
    keyValue: keyValue,
    inputKeyValue: '$keyValue-input',
    text: '${read(_now)}f',
    unitsPerPixel: 1 / 8,
    width: 40,
    digitsOnly: true,
    steps: true,
    onDragDelta: (units) => write(math.max(1, read(_now) + units.round())),
    onEditSubmit: (text) {
      final typed = int.tryParse(text.trim());
      if (typed != null) {
        write(math.max(1, typed));
      }
    },
  ),
);
