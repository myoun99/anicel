import 'string_id.dart';

/// Which of a project's timelines ([ProjectTimeline]) — I-150.
final class TimelineId extends StringId {
  const TimelineId(super.value);

  factory TimelineId.fromJson(Map<String, dynamic> json) =>
      TimelineId(json['value'] as String);
}
