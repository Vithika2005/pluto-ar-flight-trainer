import 'dart:math' as math;
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../config.dart';
import '../services/api.dart';
import '../sim/flight_model.dart';
import '../sim/mission_session.dart';
import '../sim/training_session.dart';
import '../sim/tutorial_session.dart';
import '../widgets/joystick.dart';

/// The AR flight trainer: ARKit camera view + virtual Pluto drone + on-screen controller.
/// kind = 'tutorial' or 'mission' (mission = 1..3).
class ArScreen extends StatefulWidget {
  const ArScreen({super.key, required this.kind, this.mission = 1});
  final String kind;
  final int mission;

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FlightModel _flight = FlightModel();
  late TrainingSession _session;
  late final Ticker _ticker;
  ARKitController? _ar;
  Duration _last = Duration.zero;
  int _frame = 0;

  bool _placed = false;
  bool _paused = false;
  bool _resultShown = false;
  vm.Vector3 _anchor = vm.Vector3.zero();
  double _courseYaw = 0;
  double _scale = 0.5; // 1 sim metre = 0.5 real metres by default (fits a desk / small room)
  int _renderedVersion = -1;
  final List<String> _staticNames = [];
  ARKitNode? _root;
  ARKitNode? _drone;
  ARKitNode? _shadow;

  Offset _left = Offset.zero; // throttle (y) + yaw (x)
  Offset _right = Offset.zero; // pitch (y) + roll (x)
  String _banner = '';
  Color _bannerColor = Colors.white;
  DateTime _bannerUntil = DateTime.fromMillisecondsSinceEpoch(0);

  TrainingSession _makeSession() => widget.kind == 'tutorial' ? TutorialSession() : MissionSession(widget.mission);

  @override
  void initState() {
    super.initState();
    _session = _makeSession();
    _flight.obstacles = _session.obstacles;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _ar?.dispose();
    super.dispose();
  }

  // Interruptions (phone call, app switch): pause the simulation until the user resumes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _placed && mounted) {
      setState(() => _paused = true);
    }
  }

  // ---- AR session ---------------------------------------------------------
  void _onCreated(ARKitController c) {
    _ar = c;
    c.onARTap = _onTap;
  }

  void _onTap(List<ARKitTestResult> hits) {
    if (_placed || hits.isEmpty) return;
    final h = hits.firstWhere(
      (x) => x.type == ARKitHitTestResultType.existingPlaneUsingExtent,
      orElse: () => hits.first,
    );
    final t = h.worldTransform.getColumn(3);
    _anchor = vm.Vector3(t.x, t.y, t.z);
    _buildCourse();
    setState(() => _placed = true);
  }

  ARKitMaterial _mat(Color color, {double alpha = 1.0, bool bright = false}) => ARKitMaterial(
        lightingModelName: bright ? ARKitLightingModel.constant : ARKitLightingModel.lambert,
        diffuse: ARKitMaterialProperty.color(color),
        transparency: alpha,
      );

  vm.Vector3 _flightPos() => vm.Vector3(_flight.position.x, _flight.position.y, _flight.position.z);

  void _buildCourse() {
    final c = _ar;
    if (c == null) return;
    _root = ARKitNode(
      name: 'course',
      position: _anchor,
      eulerAngles: vm.Vector3(0, _courseYaw, 0),
      scale: vm.Vector3.all(_scale),
    );
    c.add(_root!);
    _drone = ARKitNode(name: 'drone', position: _flightPos());
    c.add(_drone!, parentNodeName: 'course');
    _buildDroneParts(c);
    _shadow = ARKitNode(
      name: 'shadow',
      geometry: ARKitCylinder(radius: 0.09, height: 0.002, materials: [_mat(Colors.black, alpha: 0.5)]),
      position: vm.Vector3(_flight.position.x, 0.003, _flight.position.z),
    );
    c.add(_shadow!, parentNodeName: 'course');
    _flight.obstacles = _session.obstacles;
    _rebuildStatic();
  }

  /// Placeholder drone built from primitives. Set kPlutoModelPath in config.dart to use the
  /// official Pluto 3D model instead.
  void _buildDroneParts(ARKitController c) {
    void part(String name, dynamic geometry, vm.Vector3 pos, {vm.Vector3? euler}) {
      c.add(ARKitNode(name: name, geometry: geometry, position: pos, eulerAngles: euler), parentNodeName: 'drone');
    }

    if (kPlutoModelPath != null) {
      c.add(
        ARKitReferenceNode(
          name: 'pluto_model',
          url: kPlutoModelPath!,
          scale: vm.Vector3.all(kPlutoModelScale),
        ),
        parentNodeName: 'drone',
      );
      return;
    }
    final dark = _mat(const Color(0xFF263238));
    part('body', ARKitBox(width: 0.12, height: 0.04, length: 0.12, materials: [dark]), vm.Vector3.zero());
    part('arm1', ARKitBox(width: 0.34, height: 0.012, length: 0.02, materials: [dark]), vm.Vector3.zero(), euler: vm.Vector3(0, math.pi / 4, 0));
    part('arm2', ARKitBox(width: 0.34, height: 0.012, length: 0.02, materials: [dark]), vm.Vector3.zero(), euler: vm.Vector3(0, -math.pi / 4, 0));
    const o = 0.12;
    var i = 0;
    for (final sx in [-1.0, 1.0]) {
      for (final sz in [-1.0, 1.0]) {
        part('rotor${i++}', ARKitCylinder(radius: 0.07, height: 0.006, materials: [_mat(Colors.lightBlueAccent, alpha: 0.6)]), vm.Vector3(sx * o, 0.03, sz * o));
      }
    }
    // Red nose marker so the heading (yaw) is visible.
    part('nose', ARKitBox(width: 0.04, height: 0.03, length: 0.05, materials: [_mat(Colors.redAccent, bright: true)]), vm.Vector3(0, 0.01, -0.09));
  }

  void _rebuildStatic() {
    final c = _ar;
    if (c == null || _root == null) return;
    for (final n in _staticNames) {
      c.remove(n);
    }
    _staticNames.clear();
    final snap = _session.scene;
    _renderedVersion = snap.version;

    void add(String name, dynamic geometry, vm.Vector3 pos) {
      c.add(ARKitNode(name: name, geometry: geometry, position: pos), parentNodeName: 'course');
      _staticNames.add(name);
    }

    add('pad', ARKitCylinder(radius: kPadRadius, height: 0.01, materials: [_mat(Colors.deepOrange, alpha: 0.85, bright: true)]), vm.Vector3(0, 0.005, 0));
    final z = snap.zoneCenter;
    if (z != null) {
      add(
        'zone',
        ARKitCylinder(
          radius: snap.zoneRadius,
          height: snap.zoneHalfHeight * 2,
          materials: [_mat(snap.zoneActive ? Colors.greenAccent : Colors.yellowAccent, alpha: 0.3, bright: true)],
        ),
        vm.Vector3(z.x, z.y, z.z),
      );
    }
    for (var i = snap.activeCheckpoint; i < snap.checkpoints.length; i++) {
      final p = snap.checkpoints[i];
      final active = i == snap.activeCheckpoint;
      add(
        'cp$i',
        ARKitSphere(radius: 0.3, materials: [_mat(active ? Colors.lightGreenAccent : Colors.white, alpha: active ? 0.45 : 0.15, bright: true)]),
        vm.Vector3(p.x, p.y, p.z),
      );
    }
    for (var i = 0; i < snap.obstacles.length; i++) {
      final o = snap.obstacles[i];
      add('obs$i', ARKitCylinder(radius: o.radius, height: o.height, materials: [_mat(Colors.redAccent, alpha: 0.7)]), vm.Vector3(o.x, o.height / 2, o.z));
    }
  }

  void _render() {
    final d = _drone;
    final s = _shadow;
    if (d == null || s == null) return;
    d.position = _flightPos();
    d.eulerAngles = vm.Vector3(_flight.tiltPitch, -_flight.yaw, _flight.tiltRoll);
    s.position = vm.Vector3(_flight.position.x, 0.003, _flight.position.z);
    if (_session.scene.version != _renderedVersion) _rebuildStatic();
  }

  // ---- simulation loop ------------------------------------------------------
  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (!_placed || _paused || _ar == null) return;
    _flight.stick
      ..throttle = _left.dy
      ..yaw = _left.dx
      ..pitch = _right.dy
      ..roll = _right.dx;
    _flight.windDrift = _session.windDrift;
    _flight.update(dt);
    _session.update(dt, _flight);
    _handleEvents();
    _frame++;
    if (_frame.isEven) {
      _render();
      if (mounted) setState(() {});
    }
  }

  void _handleEvents() {
    for (final e in _flight.drainEvents()) {
      switch (e.type) {
        case FlightEventType.collision:
          _showBanner(e.message, Colors.redAccent);
          HapticFeedback.heavyImpact();
          break;
        case FlightEventType.invalidAction:
        case FlightEventType.fence:
        case FlightEventType.ceiling:
          _showBanner(e.message, Colors.amber);
          break;
        case FlightEventType.touchdown:
          _showBanner(e.message, Colors.lightBlueAccent);
          break;
      }
    }
    for (final e in _session.drainEvents()) {
      switch (e.type) {
        case SessionEventType.stageComplete:
          _showBanner(e.message, Colors.greenAccent);
          HapticFeedback.mediumImpact();
          if (widget.kind == 'tutorial' && e.stage > 0) {
            api.saveStage(e.stage).catchError((_) {});
          }
          break;
        case SessionEventType.finished:
        case SessionEventType.failed:
          _onSessionEnd();
          break;
      }
    }
  }

  void _showBanner(String msg, Color color) {
    _banner = msg;
    _bannerColor = color;
    _bannerUntil = DateTime.now().add(const Duration(milliseconds: 2600));
  }

  // ---- results ----------------------------------------------------------------
  void _onSessionEnd() {
    if (_resultShown) return;
    _resultShown = true;
    final r = _session.result(_flight);
    api
        .saveAttempt(
          mode: _session.id,
          score: r.score,
          durationSec: r.durationSec,
          collisions: r.collisions,
          stability: r.stability,
          success: r.success,
        )
        .catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _showResultDialog(r));
  }

  String _feedback(SessionResult r) {
    if (!r.success) return 'Tip: fly slower near obstacles and keep the drone inside the flight area.';
    if (r.collisions > 2) return 'Tip: fly more slowly around obstacles - each collision costs 10 points.';
    if (r.stability < 50) return 'Tip: release the sticks to let the drone stabilise and hover.';
    return 'Great flying! You are ready for the next challenge.';
  }

  Future<void> _showResultDialog(SessionResult r) async {
    if (!mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(r.success ? 'Complete!' : 'Mission failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.success) Text('★' * r.stars + '☆' * (3 - r.stars), style: const TextStyle(fontSize: 28, color: Colors.amber)),
            Text('Score: ${r.score} / 100'),
            Text('Time: ${r.durationSec.toStringAsFixed(0)} s'),
            Text('Collisions: ${r.collisions}'),
            Text('Flight stability: ${r.stability.toStringAsFixed(0)}%'),
            const SizedBox(height: 8),
            Text(_feedback(r)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Menu')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Try again')),
        ],
      ),
    );
    if (!mounted) return;
    if (retry == true) {
      _restart();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _restart() {
    _flight.reset();
    _session = _makeSession();
    _flight.obstacles = _session.obstacles;
    _resultShown = false;
    _rebuildStatic();
    setState(() {});
  }

  // ---- controls -----------------------------------------------------------------
  void _cmd(String cmd) {
    if (!_placed || _paused) return;
    if (!_session.allows(cmd)) {
      _showBanner('That control is not needed for this step yet.', Colors.amber);
      setState(() {});
      return;
    }
    switch (cmd) {
      case 'arm':
        _flight.arm();
        break;
      case 'disarm':
        _flight.disarm();
        break;
      case 'takeoff':
        _flight.takeOff();
        break;
      case 'land':
        _flight.land();
        break;
    }
    setState(() {});
  }

  void _replace() {
    _ar?.remove('course');
    _staticNames.clear();
    _root = null;
    _drone = null;
    _shadow = null;
    setState(() {
      _placed = false;
      _paused = false;
    });
  }

  void _rotate() {
    _courseYaw += math.pi / 4;
    _root?.eulerAngles = vm.Vector3(0, _courseYaw, 0);
  }

  void _cycleScale() {
    _scale = _scale == 0.25 ? 0.5 : (_scale == 0.5 ? 1.0 : 0.25);
    _root?.scale = vm.Vector3.all(_scale);
    _showBanner('Course scale ${_scale}x', Colors.white);
  }

  // ---- UI --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final stick = ((w - 124) / 2).clamp(100.0, 150.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ARKitSceneView(
            onARKitViewCreated: _onCreated,
            enableTapRecognizer: true,
            planeDetection: ARPlaneDetection.horizontal,
            showFeaturePoints: true,
          ),
          if (!_placed) _placementOverlay(),
          if (_placed) ..._hud(stick),
          if (_placed && _paused) _pauseOverlay(),
        ],
      ),
    );
  }

  Widget _placementOverlay() => Positioned.fill(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Move your phone slowly over a flat surface (floor or table) until yellow points appear, '
                  'then TAP the surface to place the landing pad and flight course. '
                  'Stand behind the pad: the drone\'s nose points away from you.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _pauseOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black54,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Paused', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 8),
                    const Text('If the course drifted, use the menu > Re-place course.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => setState(() => _paused = false), child: const Text('Resume')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Color _stateColor(FlightState s) {
    switch (s) {
      case FlightState.disarmed:
        return Colors.redAccent;
      case FlightState.armed:
        return Colors.amber;
      case FlightState.takingOff:
      case FlightState.flying:
        return Colors.greenAccent;
      case FlightState.landing:
        return Colors.lightBlueAccent;
      case FlightState.landed:
        return Colors.white70;
    }
  }

  List<Widget> _hud(double stick) {
    final f = _flight;
    final showBanner = DateTime.now().isBefore(_bannerUntil);
    return [
      Positioned.fill(
        child: SafeArea(
          child: Column(
            children: [
              _topBar(f),
              _instructionCard(),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Joystick(size: stick, topLabel: 'THROTTLE', sideLabel: '< YAW >', onChanged: (o) => _left = o),
                    SizedBox(
                      width: 100,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _btn(f.state == FlightState.disarmed ? 'ARM' : 'DISARM', f.state == FlightState.disarmed ? Colors.green : Colors.red.shade700,
                              () => _cmd(f.state == FlightState.disarmed ? 'arm' : 'disarm')),
                          const SizedBox(height: 8),
                          _btn('TAKE OFF', Colors.indigo, () => _cmd('takeoff')),
                          const SizedBox(height: 8),
                          _btn('LAND', Colors.deepOrange, () => _cmd('land')),
                        ],
                      ),
                    ),
                    Joystick(size: stick, topLabel: 'PITCH', sideLabel: '< ROLL >', onChanged: (o) => _right = o),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (showBanner)
        Positioned(
          left: 16,
          right: 16,
          bottom: stick + 90,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                border: Border.all(color: _bannerColor, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_banner, textAlign: TextAlign.center, style: TextStyle(color: _bannerColor, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
    ];
  }

  Widget _btn(String label, Color color, VoidCallback onTap) => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(100, 44), padding: EdgeInsets.zero),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );

  Widget _topBar(FlightModel f) => Row(
        children: [
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.state.label, style: TextStyle(color: _stateColor(f.state), fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    'ALT ${f.altitude.toStringAsFixed(2)} m   SPD ${f.horizontalSpeed.toStringAsFixed(1)} m/s   HDG ${f.headingDegrees.toStringAsFixed(0)}\u00B0\n'
                    'POS ${f.position.x.toStringAsFixed(1)}, ${(-f.position.z).toStringAsFixed(1)}   HITS ${f.collisions}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'pause':
                  setState(() => _paused = !_paused);
                  break;
                case 'rotate':
                  _rotate();
                  break;
                case 'scale':
                  _cycleScale();
                  setState(() {});
                  break;
                case 'replace':
                  _replace();
                  break;
                case 'restart':
                  _restart();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pause', child: Text('Pause / resume')),
              PopupMenuItem(value: 'rotate', child: Text('Rotate course 45\u00B0')),
              PopupMenuItem(value: 'scale', child: Text('Change course size')),
              PopupMenuItem(value: 'replace', child: Text('Re-place course')),
              PopupMenuItem(value: 'restart', child: Text('Restart')),
            ],
          ),
        ],
      );

  Widget _instructionCard() {
    final s = _session;
    final items = s.checklist;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.title}  |  ${s.stageLabel}', style: const TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(s.instruction, style: const TextStyle(fontSize: 13)),
          if (s.hint.isNotEmpty) Text(s.hint, style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: s.progress, minHeight: 4),
          if (items.isNotEmpty && items.length <= 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  for (final it in items)
                    Text(
                      '${it.done ? '\u2713' : '\u25CB'} ${it.text}',
                      style: TextStyle(fontSize: 10, color: it.done ? Colors.greenAccent : Colors.white60),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
