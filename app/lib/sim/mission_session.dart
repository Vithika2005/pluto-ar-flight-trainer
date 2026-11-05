import 'package:vector_math/vector_math_64.dart';
import 'flight_model.dart';
import 'training_session.dart';

class _Objective {
  _Objective(this.text, this.check, this.hint);
  final String text;
  final bool Function(FlightModel f, double dt) check;
  final String Function(FlightModel f) hint;
}

/// The three training missions.
///  1 = Takeoff and Landing, 2 = Hovering and Directional Control, 3 = AR Navigation Challenge.
class MissionSession implements TrainingSession {
  MissionSession(this.number) {
    switch (number) {
      case 1:
        _build1();
        break;
      case 2:
        _build2();
        break;
      default:
        _build3();
    }
  }

  final int number;
  late final String _title;
  late final double _par;
  late final double _limit;
  late final List<_Objective> _objectives;
  late final double _wind;
  final List<Vector3> _cps = [];
  final List<Obstacle> _obstacles = [];
  final List<SessionEvent> _events = [];

  int _index = 0;
  int _cpDone = 0;
  double _time = 0;
  double _timer = 0;
  double _violation = 0;
  bool _padTouch = false;
  bool _finished = false;
  bool _failed = false;
  String _hint = '';

  @override
  String get id => 'mission$number';
  @override
  String get title => _title;
  @override
  String get stageLabel => _finished
      ? 'Mission complete'
      : (_failed ? 'Mission failed' : 'Objective ${_index + 1}/${_objectives.length}');
  @override
  String get instruction => _finished
      ? 'Mission accomplished!'
      : (_failed ? 'Mission failed.' : _objectives[_index].text);
  @override
  String get hint => _hint;
  @override
  double get progress => _finished ? 1 : _index / _objectives.length;
  @override
  bool get finished => _finished;
  @override
  bool get failed => _failed;
  @override
  double get windDrift => _wind;
  @override
  List<Obstacle> get obstacles => _obstacles;
  @override
  bool allows(String cmd) => true;
  @override
  List<ChecklistItem> get checklist =>
      [for (var i = 0; i < _objectives.length; i++) ChecklistItem(_objectives[i].text, i < _index)];
  @override
  SceneSnapshot get scene =>
      SceneSnapshot(checkpoints: _cps, activeCheckpoint: _cpDone, obstacles: _obstacles, version: _index + 1);

  @override
  List<SessionEvent> drainEvents() {
    final out = List<SessionEvent>.from(_events);
    _events.clear();
    return out;
  }

  @override
  SessionResult result(FlightModel f) => SessionResult(
        score: _failed ? 0 : computeScore(f, violationSec: _violation, overTimeSec: _time > _par ? _time - _par : 0),
        durationSec: _time,
        collisions: f.collisions,
        stability: f.stability,
        success: _finished,
      );

  // ---- shared hints ------------------------------------------------------
  static String _armHint(FlightModel f) => 'Tap ARM at the bottom centre.';
  static String _takeoffHint(FlightModel f) {
    if (f.state == FlightState.disarmed) return 'Disarmed - tap ARM first.';
    if (f.state == FlightState.armed || f.state == FlightState.landed) return 'Tap TAKE OFF.';
    return 'Push the LEFT stick up to climb.';
  }

  void _addFlightObjectives(List<_Objective> list) {
    list.add(_Objective('Arm the drone', (f, dt) => f.state != FlightState.disarmed, _armHint));
  }

  void _addLanding(List<_Objective> list) {
    list.add(_Objective('Land on the orange pad, then disarm', (f, dt) => f.state == FlightState.disarmed && _padTouch, (f) {
      switch (f.state) {
        case FlightState.flying:
          return 'Fly over the pad and tap LAND.';
        case FlightState.landing:
          return 'Steer onto the pad: ${directionHint(f, Vector3(0, f.altitude, 0))}';
        case FlightState.landed:
          return _padTouch ? 'Tap DISARM.' : 'Missed the pad - take off and retry.';
        default:
          return 'Fly back to the pad.';
      }
    }));
  }

  // ---- Mission 1: take-off and landing -------------------------------------
  void _build1() {
    _title = 'Mission 1 - Takeoff and Landing';
    _par = 45;
    _limit = 150;
    _wind = 0;
    final l = <_Objective>[];
    _addFlightObjectives(l);
    l.add(_Objective('Take off and climb above 0.8 m', (f, dt) => f.isAirborne && f.altitude >= 0.8, _takeoffHint));
    l.add(_Objective('Hold between 0.8 m and 1.4 m for 3 seconds', (f, dt) {
      if (f.state == FlightState.flying && f.altitude >= 0.8 && f.altitude <= 1.4) {
        _timer += dt;
      } else {
        _timer = 0;
      }
      return _timer >= 3;
    }, (f) => f.altitude < 0.8 ? 'Too low - push the LEFT stick up.' : (f.altitude > 1.4 ? 'Too high - pull the LEFT stick down.' : 'Steady... ${(3 - _timer).toStringAsFixed(1)} s')));
    _addLanding(l);
    _objectives = l;
  }

  // ---- Mission 2: hovering and directional control --------------------------
  void _build2() {
    _title = 'Mission 2 - Hover and Directional Control';
    _par = 70;
    _limit = 200;
    _wind = 0.08;
    final names = ['forward 0.8 m', 'right 0.8 m', 'back 0.8 m', 'left 0.8 m'];
    _cps.addAll([Vector3(0, 1, -0.8), Vector3(0.8, 1, -0.8), Vector3(0.8, 1, 0), Vector3(0, 1, 0)]);
    final l = <_Objective>[];
    _addFlightObjectives(l);
    l.add(_Objective('Take off and hold 1.0 m (0.8 - 1.2 m) for 1 second', (f, dt) {
      if (f.state == FlightState.flying && (f.altitude - 1.0).abs() <= 0.2) {
        _timer += dt;
      } else {
        _timer = 0;
      }
      return _timer >= 1;
    }, _takeoffHint));
    for (var i = 0; i < _cps.length; i++) {
      final w = _cps[i];
      l.add(_Objective('Fly ${names[i]} and keep altitude near 1.0 m', (f, dt) {
        return f.state == FlightState.flying && hdist(f.position, w) <= 0.2 && (f.altitude - 1.0).abs() <= 0.25;
      }, (f) {
        if (f.state != FlightState.flying) return 'Keep the drone flying - tap TAKE OFF.';
        if ((f.altitude - 1.0).abs() > 0.3) return 'Keep altitude near 1.0 m (LEFT stick).';
        return 'Move ${directionHint(f, w)} to the marker.';
      }));
    }
    _addLanding(l);
    _objectives = l;
  }

  // ---- Mission 3: AR navigation challenge -----------------------------------
  void _build3() {
    _title = 'Mission 3 - AR Navigation Challenge';
    _par = 100;
    _limit = 260;
    _wind = 0.05;
    _cps.addAll([
      Vector3(0, 1.0, -1.0),
      Vector3(1.0, 1.0, -1.0),
      Vector3(1.0, 1.1, 0.2),
      Vector3(0.1, 1.0, 0.8),
      Vector3(-0.8, 1.0, 0.0),
    ]);
    _obstacles.addAll(const [
      Obstacle(0.0, -0.55),
      Obstacle(0.5, -1.0),
      Obstacle(1.0, -0.4),
      Obstacle(0.55, 0.5),
      Obstacle(-0.4, 0.4),
    ]);
    final l = <_Objective>[];
    _addFlightObjectives(l);
    l.add(_Objective('Take off and climb above 0.8 m', (f, dt) => f.isAirborne && f.altitude >= 0.8, _takeoffHint));
    for (var i = 0; i < _cps.length; i++) {
      final p = _cps[i];
      l.add(_Objective('Fly through gate ${i + 1} of ${_cps.length} (avoid the red pillars)', (f, dt) {
        return f.isAirborne && (f.position - p).length <= 0.3;
      }, (f) => f.isAirborne ? 'Gate ${i + 1}: ${directionHint(f, p)}' : 'Take off first.'));
    }
    _addLanding(l);
    _objectives = l;
  }

  // ---- update ------------------------------------------------------------
  @override
  void update(double dt, FlightModel f) {
    if (_finished || _failed) return;
    _time += dt;
    if (f.state == FlightState.landed && f.distanceFromPad <= kPadRadius) _padTouch = true;
    if (f.isAirborne) _padTouch = false;
    if (number == 2 && _index >= 2 && _index <= 5 && f.isAirborne && (f.altitude < 0.7 || f.altitude > 1.3)) {
      _violation += dt;
    }

    final obj = _objectives[_index];
    if (obj.check(f, dt)) {
      _events.add(SessionEvent(SessionEventType.stageComplete, 'Done: ${obj.text}', stage: _index + 1));
      if (number != 1 && _objectives[_index].text.startsWith(number == 2 ? 'Fly ' : 'Fly through')) _cpDone++;
      _index++;
      _timer = 0;
      _hint = '';
      if (_index >= _objectives.length) {
        _finished = true;
        _events.add(const SessionEvent(SessionEventType.finished, 'Mission accomplished!'));
        return;
      }
    }
    _hint = _objectives[_index].hint(f);

    if (f.collisions >= 5) {
      _failed = true;
      _events.add(const SessionEvent(SessionEventType.failed, 'Too many collisions.'));
    } else if (_time > _limit) {
      _failed = true;
      _events.add(const SessionEvent(SessionEventType.failed, 'Time limit reached.'));
    }
  }
}
