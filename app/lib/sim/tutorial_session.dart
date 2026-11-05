import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import 'flight_model.dart';
import 'training_session.dart';

/// Seven-stage guided tutorial. A stage only advances when the user's real
/// inputs / the simulated drone satisfy that stage's validation rule.
class TutorialSession implements TrainingSession {
  static const int stageCount = 7;
  static const double hoverAltitude = 1.0;
  static const List<String> _titles = [
    'Controller familiarisation',
    'Arming',
    'Take-off',
    'Hovering',
    'Directional movement',
    'Navigation',
    'Landing and disarming',
  ];
  static const List<String> _instructions = [
    'Move each joystick fully in every direction. The drone stays on the ground for now.',
    'Tap ARM to power up the motors. The drone cannot fly until it is armed.',
    'Tap TAKE OFF, then push the LEFT stick up until the drone is inside the green ring (1.0 m).',
    'Hold the drone inside the green zone for 5 seconds. Wind pushes it away - correct with the RIGHT stick.',
    'Fly 0.5 m forward, back, left and right using the RIGHT stick.',
    'Fly through the glowing spheres in order. Use both sticks.',
    'Fly over the orange pad, tap LAND, steer onto the pad, then tap DISARM.',
  ];
  static final Vector3 hoverPoint = Vector3(0, hoverAltitude, 0);
  static final List<Vector3> navPoints = [
    Vector3(0.7, 1.0, -0.7),
    Vector3(-0.7, 1.2, -1.0),
    Vector3(-0.7, 1.0, 0.5),
    Vector3(0.0, 0.9, 0.9),
  ];
  static const List<String> _stickKeys = [
    'throttle up',
    'throttle down',
    'yaw left',
    'yaw right',
    'pitch forward',
    'pitch back',
    'roll left',
    'roll right',
  ];

  int stage = 1;
  bool _finished = false;
  double _stageTime = 0;
  double _totalTime = 0;
  double _hold = 0;
  double _hoverIn = 0;
  double _hoverTotal = 0;
  int _cp = 0;
  bool _landedOnPad = false;
  String _hint = '';
  bool _zoneActive = false;
  final Set<String> _touched = {};
  final Map<String, double> _moved = {'forward': 0, 'back': 0, 'left': 0, 'right': 0};
  final List<SessionEvent> _events = [];

  @override
  String get id => 'tutorial';
  @override
  String get title => 'Guided Flight Tutorial';
  @override
  String get stageLabel =>
      _finished ? 'Tutorial complete' : 'Stage $stage/$stageCount - ${_titles[stage - 1]}';
  @override
  String get instruction => _finished ? 'Well done - you completed every stage!' : _instructions[stage - 1];
  @override
  String get hint => _hint;
  @override
  double get progress => _finished ? 1 : (stage - 1) / stageCount;
  @override
  bool get finished => _finished;
  @override
  bool get failed => false;
  @override
  double get windDrift => stage == 4 ? 0.12 : 0;
  @override
  List<Obstacle> get obstacles => const [];

  @override
  bool allows(String cmd) {
    if (stage == 1) return false;
    if (stage == 2) return cmd == 'arm' || cmd == 'disarm';
    return true;
  }

  @override
  SceneSnapshot get scene {
    switch (stage) {
      case 3:
        return SceneSnapshot(
          zoneCenter: hoverPoint,
          zoneRadius: 0.25,
          zoneHalfHeight: 0.12,
          zoneActive: _zoneActive,
          version: 3000 + (_zoneActive ? 1 : 0),
        );
      case 4:
        return SceneSnapshot(
          zoneCenter: hoverPoint,
          zoneRadius: 0.25,
          zoneHalfHeight: 0.2,
          zoneActive: _zoneActive,
          version: 4000 + (_zoneActive ? 1 : 0),
        );
      case 6:
        return SceneSnapshot(checkpoints: navPoints, activeCheckpoint: _cp, version: 6000 + _cp);
      default:
        return SceneSnapshot(version: stage * 1000);
    }
  }

  @override
  List<ChecklistItem> get checklist {
    switch (stage) {
      case 1:
        return [for (final k in _stickKeys) ChecklistItem(k, _touched.contains(k))];
      case 5:
        return [for (final e in _moved.entries) ChecklistItem('${e.key} ${e.value.toStringAsFixed(1)}/0.5 m', e.value >= 0.5)];
      case 6:
        return [for (var i = 0; i < navPoints.length; i++) ChecklistItem('checkpoint ${i + 1}', i < _cp)];
      default:
        return const [];
    }
  }

  @override
  List<SessionEvent> drainEvents() {
    final out = List<SessionEvent>.from(_events);
    _events.clear();
    return out;
  }

  /// Hovering stability (% of stage-4 time spent inside the zone).
  double get hoverStability => _hoverTotal <= 0 ? 0 : _hoverIn / _hoverTotal * 100;

  @override
  SessionResult result(FlightModel f) => SessionResult(
        score: computeScore(f),
        durationSec: _totalTime,
        collisions: f.collisions,
        stability: _hoverTotal > 0 ? hoverStability : f.stability,
        success: _finished,
      );

  void _advance(String msg) {
    _events.add(SessionEvent(SessionEventType.stageComplete, msg, stage: stage));
    if (stage == stageCount) {
      _finished = true;
      _hint = '';
      _events.add(const SessionEvent(SessionEventType.finished, 'Tutorial complete!'));
      return;
    }
    stage++;
    _stageTime = 0;
    _hold = 0;
    _hint = '';
    _zoneActive = false;
  }

  @override
  void update(double dt, FlightModel f) {
    if (_finished) return;
    _stageTime += dt;
    _totalTime += dt;
    switch (stage) {
      case 1:
        _stage1(f);
        break;
      case 2:
        _stage2(f);
        break;
      case 3:
        _stage3(f, dt);
        break;
      case 4:
        _stage4(f, dt);
        break;
      case 5:
        _stage5(f, dt);
        break;
      case 6:
        _stage6(f);
        break;
      case 7:
        _stage7(f);
        break;
    }
  }

  void _stage1(FlightModel f) {
    final s = f.stick;
    void t(bool cond, String key) {
      if (cond) _touched.add(key);
    }

    t(s.throttle > 0.6, 'throttle up');
    t(s.throttle < -0.6, 'throttle down');
    t(s.yaw < -0.6, 'yaw left');
    t(s.yaw > 0.6, 'yaw right');
    t(s.pitch > 0.6, 'pitch forward');
    t(s.pitch < -0.6, 'pitch back');
    t(s.roll < -0.6, 'roll left');
    t(s.roll > 0.6, 'roll right');
    if (_touched.length == _stickKeys.length) {
      _advance('Stage 1 complete: controller familiarisation');
    } else {
      final missing = _stickKeys.where((k) => !_touched.contains(k)).toList();
      _hint = 'Still to try: ${missing.join(', ')}';
    }
  }

  void _stage2(FlightModel f) {
    if (f.state != FlightState.disarmed) {
      _advance('Stage 2 complete: motors armed');
    } else {
      _hint = _stageTime > 8 ? 'Tap the ARM button at the bottom centre.' : '';
    }
  }

  void _stage3(FlightModel f, double dt) {
    const tol = 0.12;
    final alt = f.altitude;
    final inBand = f.state == FlightState.flying && (alt - hoverAltitude).abs() <= tol;
    _zoneActive = inBand;
    if (inBand) {
      _hold += dt;
      _hint = 'Hold it steady... ${math.max(0, 1.5 - _hold).toStringAsFixed(1)} s';
      if (_hold >= 1.5) _advance('Stage 3 complete: target altitude reached');
      return;
    }
    _hold = 0;
    switch (f.state) {
      case FlightState.disarmed:
        _hint = 'The drone is disarmed - tap ARM, then TAKE OFF.';
        break;
      case FlightState.armed:
      case FlightState.landed:
        _hint = 'Tap TAKE OFF - the drone will rise to about 0.6 m.';
        break;
      case FlightState.takingOff:
        _hint = 'Lifting off...';
        break;
      case FlightState.landing:
        _hint = 'You are landing. Push the left stick up to climb again.';
        break;
      case FlightState.flying:
        _hint = alt < hoverAltitude - tol
            ? 'Push the LEFT stick UP to climb to the green ring.'
            : 'Too high - pull the LEFT stick DOWN.';
        break;
    }
  }

  void _stage4(FlightModel f, double dt) {
    final c = Vector3(hoverPoint.x, hoverPoint.y, hoverPoint.z);
    final inZone = f.state == FlightState.flying &&
        hdist(f.position, c) <= 0.25 &&
        (f.altitude - hoverAltitude).abs() <= 0.2;
    _zoneActive = inZone;
    if (f.state == FlightState.flying) {
      _hoverTotal += dt;
      if (inZone) _hoverIn += dt;
    }
    if (inZone) {
      _hold += dt;
      _hint = 'Stable - ${math.max(0, 5 - _hold).toStringAsFixed(1)} s to go';
      if (_hold >= 5) _advance('Stage 4 complete: stable hover (${hoverStability.toStringAsFixed(0)}% in zone)');
      return;
    }
    _hold = 0;
    if (f.state != FlightState.flying) {
      _hint = 'The drone is not flying - tap TAKE OFF and climb to 1.0 m.';
      return;
    }
    final d = c - f.position;
    if ((f.altitude - hoverAltitude).abs() > 0.2) {
      _hint = f.altitude < hoverAltitude ? 'Drifting low - push the LEFT stick up.' : 'Drifting high - pull the LEFT stick down.';
    } else {
      final fo = d.dot(f.forward);
      final ro = d.dot(f.right);
      _hint = fo.abs() > ro.abs()
          ? (fo > 0 ? 'Drifting back - push the RIGHT stick UP.' : 'Drifting forward - pull the RIGHT stick DOWN.')
          : (ro > 0 ? 'Drifting left - push the RIGHT stick RIGHT.' : 'Drifting right - push the RIGHT stick LEFT.');
    }
  }

  void _stage5(FlightModel f, double dt) {
    if (f.state != FlightState.flying) {
      _hint = 'Keep the drone flying (tap TAKE OFF if it landed).';
      return;
    }
    final bf = f.velocity.dot(f.forward);
    final br = f.velocity.dot(f.right);
    if (bf > 0) {
      _moved['forward'] = _moved['forward']! + bf * dt;
    } else {
      _moved['back'] = _moved['back']! - bf * dt;
    }
    if (br > 0) {
      _moved['right'] = _moved['right']! + br * dt;
    } else {
      _moved['left'] = _moved['left']! - br * dt;
    }
    final todo = _moved.entries.where((e) => e.value < 0.5).map((e) => e.key).toList();
    if (todo.isEmpty) {
      _advance('Stage 5 complete: all four directions flown');
    } else {
      _hint = 'Still to fly: ${todo.join(', ')}. The nose points at the red marker.';
    }
  }

  void _stage6(FlightModel f) {
    if (f.state != FlightState.flying) {
      _hint = 'Keep the drone flying (tap TAKE OFF if it landed).';
      return;
    }
    final target = navPoints[_cp];
    final dx = f.position.x - target.x;
    final dy = f.position.y - target.y;
    final dz = f.position.z - target.z;
    if (math.sqrt(dx * dx + dy * dy + dz * dz) <= 0.3) {
      _cp++;
      if (_cp >= navPoints.length) {
        _advance('Stage 6 complete: course finished');
      } else {
        _events.add(SessionEvent(SessionEventType.stageComplete, 'Checkpoint $_cp reached', stage: 0));
      }
    } else {
      _hint = 'Next checkpoint: ${directionHint(f, target)}';
    }
  }

  void _stage7(FlightModel f) {
    if (f.isAirborne) _landedOnPad = false;
    final d = f.distanceFromPad;
    if (f.state == FlightState.landed) {
      if (d <= kPadRadius) {
        _landedOnPad = true;
      } else {
        _landedOnPad = false;
      }
    }
    if (f.state == FlightState.disarmed && _landedOnPad) {
      _advance('Stage 7 complete: landed on the pad and disarmed');
      return;
    }
    switch (f.state) {
      case FlightState.flying:
        _hint = d > 0.3 ? 'Fly over the orange pad (${directionHint(f, Vector3(0, f.altitude, 0))}), then tap LAND.' : 'Above the pad - tap LAND.';
        break;
      case FlightState.takingOff:
        _hint = 'Lifting off...';
        break;
      case FlightState.landing:
        _hint = d > 0.3 ? 'Steer onto the pad while descending: ${directionHint(f, Vector3(0, f.altitude, 0))}.' : 'Descending - stay centred.';
        break;
      case FlightState.landed:
        _hint = _landedOnPad ? 'Touchdown! Tap DISARM to finish.' : 'You missed the pad. Tap TAKE OFF and try again.';
        break;
      case FlightState.armed:
        _hint = 'Tap TAKE OFF, then fly over the pad and land.';
        break;
      case FlightState.disarmed:
        _hint = 'Arm, take off, fly over the pad and land on it.';
        break;
    }
  }
}
