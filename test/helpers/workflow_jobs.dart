/// Each job of a workflow's [lines], by its id: the lines from its
/// `  <id>:` under `jobs:` to the next job's — for the scans that hold a
/// law to every job of a kind.
Map<String, String> jobsOf(List<String> lines) {
  final jobs = <String, String>{};
  final start = lines.indexOf('jobs:');
  if (start == -1) return jobs;
  String? id;
  final body = StringBuffer();
  for (final line in [...lines.skip(start + 1), '  end-of-jobs:']) {
    final head = RegExp(r'^  ([\w-]+):\s*$').firstMatch(line);
    if (head == null) {
      body.writeln(line);
      continue;
    }
    if (id != null) jobs[id] = body.toString();
    body.clear();
    id = head[1];
  }
  return jobs;
}
