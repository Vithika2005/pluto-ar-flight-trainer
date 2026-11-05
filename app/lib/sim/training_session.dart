import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import 'flight_model.dart';

/// Radius (m) of the orange landing pad at the origin.
const double kPadRadius = 0.35;

/// What the AR layer should draw besides the drone and the pad.
class SceneSnapshot {
  const SceneSnapshot({
    this.checkpoints = const [],
    this.activeCheckpoint = 0,
    this.zoneCenter,
    this.zoneRadius = 0.25,
    this.zoneHalfHeight = 0.2,
    this.zoneActive = false,
    this.obstacles = const [],
    this.version = 0,
  });
  final List<Vector3> checkpoints;
  final int activeCheckpoint;
  final Vector3? zoneCenter;
  final double zoneRadius, zoneHalfHeight;
  final bool zoneActive;
  final List<Obstacle> obstacles;

  /// Changes whenever the 3D markers have to be rebuilt.
  final int version;
}

enum SessionEventType { stageComplete, finished, failed }

class SessionEvent {
  const SessionEvent(this.type, this.message, {this.stage = 0});
  final SessionEventType type;
  final String message;
  final int stage;
}

class ChecklistItem {
  const ChecklistItem(this.text, this.done);
  final String text;
  final bool done;
}

class SessionResult {
  const SessionResult({
    required this.score,
    required this.durationSec,
    required this.collisions,
    required this.stability,
    required this.success,
  });
  final int score;
  final double durationSec;
  final int collisions;
  final double stability;
  final bool success;
  int get stars => !success ? 0 : (score >= 85 ? 3 : (score >= 65 ? 2 : 1));
}

/// Common interface of the guided tutorial and the three missions.
abstract class TrainingSession {
  /// Backend mode id: tutorial, mission1, mission2, mission3.
  String get id;
  String get title;
  String get stageLabel;
  String get instruction;
  String get hint;
  double get progress;
  bool get finished;
  bool get failed;
  SceneSnapshot get scene;
  List<ChecklistItem> get checklist;
  double get windDrift;
  List<Obstacle> get obstacles;

  /// cmd is one of: arm, disarm, takeoff, land.
  bool allows(String cmd);
  void update(double dt, FlightModel f);
  List<SessionEvent> drainEvents();
  SessionResult result(FlightModel f);
}

double hdist(Vector3 a, Vector3 b) {
  final dx = a.x - b.x;
  final dz = a.z - b.z;
  return math.sqrt(dx * dx + dz * dz);
}

/// Plain-language direction (relative to the drone's nose) towards a target.
String directionHint(FlightModel f, Vector3 target) {
  final d = target - f.position;
  final fwd = d.dot(f.forward);
  final rgt = d.dot(f.right);
  final parts = <String>[];
  if (fwd.abs() > 0.15) parts.add(fwd > 0 ? 'forward' : 'back');
  if (rgt.abs() > 0.15) parts.add(rgt > 0 ? 'right' : 'left');
  if (d.y.abs() > 0.15) parts.add(d.y > 0 ? 'up' : 'down');
  return parts.isEmpty ? 'hold position' : parts.join(' + ');
}

int computeScore(FlightModel f, {double violationSec = 0, double overTimeSec = 0}) {
  final s = 100.0 -
      f.collisions * 10 -
      math.min(10, f.invalidActions * 2) -
      math.min(30, violationSec * 3) -
      math.min(30, overTimeSec * 0.3);
  return s.clamp(0, 100).round();
}
