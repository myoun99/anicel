import 'package:flutter/foundation.dart';

/// Words that never change, as a listenable — so a place that hears its
/// words where they change (the cut stood in, I-154) has one shape where
/// they do not (a progress window's missing status line, the open
/// timeline's name).
///
/// Equal by its words: a host that builds one afresh each time shows the
/// same thing while they hold, as a kept piece compares it
/// (`TimelineLayerControlsHeader.facts`).
@immutable
class FixedLabel implements ValueListenable<String> {
  const FixedLabel(this.value);

  @override
  final String value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  bool operator ==(Object other) => other is FixedLabel && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
