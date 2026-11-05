import 'package:flutter/material.dart';

/// Spring-loaded virtual joystick. Reports x (right = +) and y (up = +) in -1..1.
class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.size, required this.onChanged, this.topLabel = '', this.sideLabel = ''});
  final double size;
  final ValueChanged<Offset> onChanged;
  final String topLabel; // vertical axis name
  final String sideLabel; // horizontal axis name

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero; // screen coordinates, -1..1 (y down)
  int? _pointer;

  void _update(Offset local) {
    final r = widget.size / 2;
    var v = (local - Offset(r, r)) / (r * 0.7);
    if (v.distance > 1) v = v / v.distance;
    setState(() => _knob = v);
    widget.onChanged(Offset(v.dx, -v.dy));
  }

  void _release() {
    setState(() {
      _knob = Offset.zero;
      _pointer = null;
    });
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _update(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _update(e.localPosition);
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) _release();
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _release();
        },
        child: CustomPaint(
          painter: _StickPainter(_knob, widget.topLabel, widget.sideLabel),
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.knob, this.top, this.side);
  final Offset knob;
  final String top;
  final String side;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.black.withOpacity(0.35));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final cross = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), cross);
    final active = knob != Offset.zero;
    canvas.drawCircle(c + knob * (r * 0.7), r * 0.3, Paint()..color = active ? Colors.orangeAccent : Colors.white70);
    _text(canvas, top, Offset(c.dx, c.dy - r + 10));
    _text(canvas, side, Offset(c.dx, c.dy + r - 10));
  }

  void _text(Canvas canvas, String s, Offset center) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: s, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.knob != knob;
}
