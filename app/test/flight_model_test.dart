import 'package:flutter_test/flutter_test.dart';
import 'package:pluto_ar_sim/sim/flight_model.dart';

void run(FlightModel f, double seconds, {double dt = 0.02}) {
  for (var t = 0.0; t < seconds; t += dt) {
    f.update(dt);
  }
}

FlightModel airborne() {
  final f = FlightModel();
  f.arm();
  f.takeOff();
  run(f, 4);
  return f;
}

void main() {
  group('state machine', () {
    test('cannot take off while disarmed', () {
      final f = FlightModel();
      expect(f.takeOff(), isFalse);
      expect(f.state, FlightState.disarmed);
      expect(f.invalidActions, 1);
    });

    test('arm -> take off -> flying -> land -> landed -> disarm', () {
      final f = FlightModel();
      expect(f.arm(), isTrue);
      expect(f.state, FlightState.armed);
      expect(f.takeOff(), isTrue);
      run(f, 4);
      expect(f.state, FlightState.flying);
      expect(f.altitude, greaterThanOrEqualTo(0.55));
      expect(f.land(), isTrue);
      run(f, 8);
      expect(f.state, FlightState.landed);
      expect(f.altitude, 0);
      expect(f.disarm(), isTrue);
      expect(f.state, FlightState.disarmed);
    });

    test('cannot disarm in the air', () {
      final f = airborne();
      expect(f.disarm(), isFalse);
      expect(f.state, FlightState.flying);
    });
  });

  group('flight model', () {
    test('sticks have no effect before arming', () {
      final f = FlightModel();
      f.stick.pitch = 1;
      f.stick.throttle = 1;
      run(f, 2);
      expect(f.position.length, 0);
      expect(f.state, FlightState.disarmed);
    });

    test('forward stick moves the drone towards -z at yaw 0', () {
      final f = airborne();
      final z0 = f.position.z;
      f.stick.pitch = 1;
      run(f, 1);
      expect(f.position.z, lessThan(z0 - 0.3));
    });

    test('releasing the sticks brings the drone to a hover', () {
      final f = airborne();
      f.stick.pitch = 1;
      run(f, 1);
      f.stick.clear();
      run(f, 3);
      expect(f.horizontalSpeed, lessThan(0.05));
    });

    test('geofence keeps the drone inside the flight area', () {
      final f = airborne();
      f.stick.pitch = 1;
      run(f, 10);
      expect(f.position.z.abs(), lessThanOrEqualTo(f.config.fence + 1e-9));
    });

    test('pillar collision is detected and counted', () {
      final f = FlightModel();
      f.obstacles = const [Obstacle(0, -0.6)];
      f.arm();
      f.takeOff();
      run(f, 4);
      f.stick.pitch = 1;
      run(f, 3);
      expect(f.collisions, greaterThanOrEqualTo(1));
    });

    test('yaw stick rotates the drone clockwise', () {
      final f = airborne();
      f.stick.yaw = 1;
      run(f, 0.5);
      expect(f.yaw, greaterThan(0.3));
    });
  });
}
