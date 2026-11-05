import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';

/// Flight workflow: Disarmed -> Armed -> Taking Off -> Flying/Hovering -> Landing -> Landed.
enum FlightState { disarmed, armed, takingOff, flying, landing, landed }

extension FlightStateLabel on FlightState {
  String get label {
    switch (this) {
      case FlightState.disarmed:
        return 'DISARMED';
      case FlightState.armed:
        return 'ARMED';
      case FlightState.takingOff:
        return 'TAKING OFF';
      case FlightState.flying:
        return 'FLYING';
      case FlightState.landing:
        return 'LANDING';
      case FlightState.landed:
        return 'LANDED';
    }
  }
}

/// Virtual joystick values, each in -1..1 (Mode-2 layout like the Pluto Controller app).
class StickInput {
  double throttle = 0; // + = climb
  double yaw = 0; // + = rotate right (clockwise from above)
  double pitch = 0; // + = forward
  double roll = 0; // + = sideways right
  void clear() => throttle = yaw = pitch = roll = 0;
}

enum FlightEventType { invalidAction, collision, touchdown, fence, ceiling }

class FlightEvent {
  const FlightEvent(this.type, this.message);
  final FlightEventType type;
  final String message;
}

class Obstacle {
  const Obstacle(this.x, this.z, {this.radius = 0.12, this.height = 1.4});
  final double x, z, radius, height;
}

class FlightConfig {
  const FlightConfig({
    this.maxHSpeed = 1.0, // m/s
    this.maxVSpeed = 0.7, // m/s
    this.maxYawRate = 1.75, // rad/s (~100 deg/s)
    this.responsiveness = 4.0, // 1/s, how fast velocity follows the sticks
    this.takeoffAltitude = 0.6, // m, auto take-off height
    this.takeoffClimbSpeed = 0.5, // m/s
    this.landingSpeed = 0.35, // m/s
    this.maxAltitude = 2.0, // m
    this.fence = 2.0, // m, half-size of the square flight area
    this.droneRadius = 0.15, // m
    this.hardLandingSpeed = 0.5, // m/s
    this.deadzone = 0.08,
  });
  final double maxHSpeed,
      maxVSpeed,
      maxYawRate,
      responsiveness,
      takeoffAltitude,
      takeoffClimbSpeed,
      landingSpeed,
      maxAltitude,
      fence,
      droneRadius,
      hardLandingSpeed,
      deadzone;
}

/// Simplified, deterministic flight model + state machine.
/// Coordinates: x right, y up, z towards the pilot, so forward at yaw 0 is -z.
/// The pad (take-off / landing zone) is at the origin.
class FlightModel {
  FlightModel({this.config = const FlightConfig(), int seed = 7}) : _rng = math.Random(seed);

  final FlightConfig config;
  final math.Random _rng;
  final StickInput stick = StickInput();

  List<Obstacle> obstacles = const [];
  double windDrift = 0; // m/s of random drift while airborne (makes hovering a skill)

  FlightState state = FlightState.disarmed;
  Vector3 position = Vector3.zero();
  Vector3 velocity = Vector3.zero();
  double yaw = 0; // rad, clockwise positive
  double _yawRate = 0;
  double tiltPitch = 0; // visual only
  double tiltRoll = 0; // visual only

  int collisions = 0;
  int invalidActions = 0;
  double airborneTime = 0;
  double _stableTime = 0;
  double _time = 0;

  final Vector3 _wind = Vector3.zero();
  final Map<String, double> _cooldown = {};
  final List<FlightEvent> _events = [];

  // ---- read-only helpers -------------------------------------------------
  Vector3 get forward => Vector3(math.sin(yaw), 0, -math.cos(yaw));
  Vector3 get right => Vector3(math.cos(yaw), 0, math.sin(yaw));
  double get altitude => position.y;
  bool get isAirborne =>
      state == FlightState.takingOff || state == FlightState.flying || state == FlightState.landing;
  double get horizontalSpeed => math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
  double get distanceFromPad => math.sqrt(position.x * position.x + position.z * position.z);
  double get headingDegrees {
    var d = yaw * 180 / math.pi % 360;
    if (d < 0) d += 360;
    return d;
  }

  /// Percentage of airborne time spent steady (slow horizontal and vertical speed).
  double get stability => airborneTime <= 0 ? 0 : (_stableTime / airborneTime * 100).clamp(0, 100).toDouble();

  List<FlightEvent> drainEvents() {
    final out = List<FlightEvent>.from(_events);
    _events.clear();
    return out;
  }

  // ---- commands (the buttons of the Pluto Controller) ---------------------
  bool arm() {
    if (state != FlightState.disarmed) return _invalid('Drone is already armed.');
    _setState(FlightState.armed);
    return true;
  }

  bool disarm() {
    if (state == FlightState.disarmed) return _invalid('Drone is already disarmed.');
    if (state == FlightState.armed || state == FlightState.landed) {
      _setState(FlightState.disarmed);
      return true;
    }
    return _invalid('Land the drone before disarming.');
  }

  bool takeOff() {
    if (state == FlightState.disarmed) return _invalid('Arm the drone before taking off.');
    if (state == FlightState.armed || state == FlightState.landed) {
      _setState(FlightState.takingOff);
      return true;
    }
    return _invalid('The drone is already in the air.');
  }

  bool land() {
    if (state == FlightState.flying || state == FlightState.takingOff) {
      _setState(FlightState.landing);
      return true;
    }
    if (state == FlightState.disarmed) return _invalid('Arm and take off before landing.');
    if (state == FlightState.landing) return _invalid('Already landing.');
    return _invalid('The drone is already on the ground.');
  }

  void reset() {
    state = FlightState.disarmed;
    position = Vector3.zero();
    velocity = Vector3.zero();
    yaw = 0;
    _yawRate = 0;
    tiltPitch = tiltRoll = 0;
    collisions = invalidActions = 0;
    airborneTime = _stableTime = _time = 0;
    _wind.setZero();
    _cooldown.clear();
    _events.clear();
    stick.clear();
  }

  // ---- simulation step -----------------------------------------------------
  void update(double dtRaw) {
    final dt = dtRaw.clamp(0.0, 0.05).toDouble();
    if (dt <= 0) return;
    _time += dt;
    final c = config;
    final thr = _dz(stick.throttle);
    final yawIn = _dz(stick.yaw);
    final pit = _dz(stick.pitch);
    final rol = _dz(stick.roll);

    // Manual lift-off: arm, then push the throttle stick up (like the real controller).
    if (state == FlightState.armed && thr > 0.35) _setState(FlightState.flying);

    final fwd = forward;
    final rgt = right;
    var target = Vector3.zero();
    var targetYawRate = 0.0;

    switch (state) {
      case FlightState.disarmed:
      case FlightState.armed:
      case FlightState.landed:
        break; // motors idle: sticks have no effect on the drone
      case FlightState.takingOff:
        target.y = c.takeoffClimbSpeed;
        if (position.y >= c.takeoffAltitude) _setState(FlightState.flying);
        break;
      case FlightState.flying:
        target.y = thr * c.maxVSpeed;
        target += fwd * (pit * c.maxHSpeed) + rgt * (rol * c.maxHSpeed);
        targetYawRate = yawIn * c.maxYawRate;
        break;
      case FlightState.landing:
        target.y = -c.landingSpeed;
        target += fwd * (pit * c.maxHSpeed * 0.6) + rgt * (rol * c.maxHSpeed * 0.6);
        targetYawRate = yawIn * c.maxYawRate;
        if (thr > 0.5) _setState(FlightState.flying); // go-around
        break;
    }

    // Random wind drift while airborne.
    if (isAirborne && windDrift > 0) {
      _wind.x += (_rng.nextDouble() - 0.5) * windDrift * 6 * dt;
      _wind.z += (_rng.nextDouble() - 0.5) * windDrift * 6 * dt;
      _wind.x *= 1 - 0.4 * dt;
      _wind.z *= 1 - 0.4 * dt;
      final m = math.sqrt(_wind.x * _wind.x + _wind.z * _wind.z);
      if (m > windDrift) {
        _wind.x *= windDrift / m;
        _wind.z *= windDrift / m;
      }
      target.x += _wind.x;
      target.z += _wind.z;
    }

    // Basic stabilisation: velocity eases towards the commanded velocity, so releasing
    // the sticks brings the drone to a hover (altitude hold).
    final k = 1 - math.exp(-c.responsiveness * dt);
    if (isAirborne) {
      velocity += (target - velocity) * k;
      _yawRate += (targetYawRate - _yawRate) * k;
    } else {
      velocity = Vector3.zero();
      _yawRate = 0;
    }
    position += velocity * dt;
    yaw += _yawRate * dt;
    if (yaw > math.pi) yaw -= 2 * math.pi;
    if (yaw < -math.pi) yaw += 2 * math.pi;

    // Ground detection / touchdown.
    if (state == FlightState.takingOff && position.y < 0) position.y = 0;
    if ((state == FlightState.flying || state == FlightState.landing) && position.y <= 0) {
      final impact = -velocity.y;
      position.y = 0;
      velocity = Vector3.zero();
      if (impact > c.hardLandingSpeed) {
        if (_emit(FlightEventType.collision, 'Hard landing! Descend more gently.', key: 'hard', cooldown: 1)) {
          collisions++;
        }
      }
      _setState(FlightState.landed);
      _emit(FlightEventType.touchdown, 'Touchdown.');
    }

    // Ceiling and geofence.
    if (position.y > c.maxAltitude) {
      position.y = c.maxAltitude;
      if (velocity.y > 0) velocity.y = 0;
      _emit(FlightEventType.ceiling, 'Maximum altitude reached.', key: 'ceil', cooldown: 2);
    }
    if (position.x.abs() > c.fence) {
      position.x = position.x.sign * c.fence;
      velocity.x = 0;
      _emit(FlightEventType.fence, 'Out of the flight area - turn back.', key: 'fence', cooldown: 2);
    }
    if (position.z.abs() > c.fence) {
      position.z = position.z.sign * c.fence;
      velocity.z = 0;
      _emit(FlightEventType.fence, 'Out of the flight area - turn back.', key: 'fence', cooldown: 2);
    }

    // Obstacle (pillar) collisions.
    for (final o in obstacles) {
      final dx = position.x - o.x;
      final dz = position.z - o.z;
      final d = math.sqrt(dx * dx + dz * dz);
      final minD = o.radius + c.droneRadius;
      if (d < minD && position.y < o.height + c.droneRadius) {
        final nx = d < 1e-6 ? 1.0 : dx / d;
        final nz = d < 1e-6 ? 0.0 : dz / d;
        position.x = o.x + nx * minD;
        position.z = o.z + nz * minD;
        velocity.x = 0;
        velocity.z = 0;
        if (_emit(FlightEventType.collision, 'Collision with an obstacle!', key: 'obs', cooldown: 0.8)) {
          collisions++;
        }
      }
    }

    // Visual tilt and statistics.
    final bf = velocity.dot(fwd);
    final br = velocity.dot(rgt);
    tiltPitch += (-_clampD(bf / c.maxHSpeed, -1, 1) * 0.3 - tiltPitch) * k;
    tiltRoll += (-_clampD(br / c.maxHSpeed, -1, 1) * 0.3 - tiltRoll) * k;
    if (isAirborne) {
      airborneTime += dt;
      if (horizontalSpeed < 0.25 && velocity.y.abs() < 0.25) _stableTime += dt;
    }
  }

  // ---- internals ---------------------------------------------------------
  double _dz(double v) => v.abs() < config.deadzone ? 0 : v.clamp(-1.0, 1.0).toDouble();
  double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  void _setState(FlightState s) => state = s;

  bool _invalid(String msg) {
    invalidActions++;
    _events.add(FlightEvent(FlightEventType.invalidAction, msg));
    return false;
  }

  bool _emit(FlightEventType type, String msg, {String? key, double cooldown = 0}) {
    if (key != null) {
      final until = _cooldown[key] ?? 0;
      if (_time < until) return false;
      _cooldown[key] = _time + cooldown;
    }
    _events.add(FlightEvent(type, msg));
    return true;
  }
}
