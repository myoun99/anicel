enum TimelineOrientation {
  horizontal,
  vertical;

  /// What the timeline's ⇄ turns this into — its button's press and its
  /// key's (I-40).
  TimelineOrientation get toggled => this == horizontal ? vertical : horizontal;
}
