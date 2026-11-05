import 'package:flutter_test/flutter_test.dart';
import 'package:pluto_ar_sim/sim/flight_model.dart';
import 'package:pluto_ar_sim/sim/mission_session.dart';
import 'package:pluto_ar_sim/sim/tutorial_session.dart';

void main() {
  test('tutorial stage 1 needs every stick direction', () {
    final f = FlightModel();
    final t = TutorialSession();
    t.update(0.02, f);
    expect(t.stage, 1);
    final moves = <List<double>>[
      [1, 0, 0, 0], [-1, 0, 0, 0], [0, -1, 0, 0], [0, 1, 0, 0],
      [0, 0, 1, 0], [0, 0, -1, 0], [0, 0, 0, -1], [0, 0, 0, 1],
    ];
    for (final m in moves) {
      f.stick
        ..throttle = m[0]
        ..yaw = m[1]
        ..pitch = m[2]
        ..roll = m[3];
      t.update(0.02, f);
    }
    expect(t.stage, 2);
  });

  test('tutorial stage 2 advances only after arming', () {
    final f = FlightModel();
    final t = TutorialSession()..stage = 2;
    t.update(0.02, f);
    expect(t.stage, 2);
    f.arm();
    t.update(0.02, f);
    expect(t.stage, 3);
  });

  test('tutorial blocks take-off before it is introduced', () {
    final t = TutorialSession();
    expect(t.allows('arm'), isFalse);
    t.stage = 2;
    expect(t.allows('arm'), isTrue);
    expect(t.allows('takeoff'), isFalse);
    t.stage = 3;
    expect(t.allows('takeoff'), isTrue);
  });

  test('mission 1 completes: arm, climb, hold, land on pad, disarm', () {
    final f = FlightModel();
    final m = MissionSession(1);
    void step(double seconds) {
      for (var t = 0.0; t < seconds; t += 0.02) {
        f.update(0.02);
        m.update(0.02, f);
      }
    }

    f.arm();
    step(0.1);
    f.takeOff();
    step(4);
    f.stick.throttle = 0.5; // climb a little above 0.8 m
    step(1.5);
    f.stick.clear();
    step(4); // hold between 0.8 and 1.4 m
    f.land();
    step(8);
    f.disarm();
    step(0.1);
    expect(m.finished, isTrue);
    expect(m.result(f).success, isTrue);
  });
}
