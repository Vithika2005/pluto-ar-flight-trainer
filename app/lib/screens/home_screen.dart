import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'ar_screen.dart';
import 'login_screen.dart';
import 'progress_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await api.summary();
      if (mounted) setState(() => _summary = s);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _logout();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await api.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _open(String kind, {int mission = 1}) async {
    if (!Platform.isIOS) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The AR trainer needs an ARKit-capable iPhone.')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArScreen(kind: kind, mission: mission)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final stages = ((_summary?['stagesCompleted'] as List?) ?? const []).length;
    final best = (_summary?['best'] as Map?) ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, ${api.username ?? 'pilot'}'),
        actions: [
          IconButton(
            tooltip: 'Progress & leaderboard',
            icon: const Icon(Icons.leaderboard),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgressScreen())),
          ),
          IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                color: Colors.red.shade900,
                child: Padding(padding: const EdgeInsets.all(12), child: Text('$_error\nPull down to retry.')),
              ),
            const Text('Place the course on a flat surface, then fly with the on-screen sticks.'),
            const SizedBox(height: 12),
            _tile(Icons.school, 'Guided tutorial', '$stages / 7 stages completed', () => _open('tutorial')),
            _tile(Icons.flight_takeoff, 'Mission 1 - Takeoff & Landing', _bestText(best['mission1']), () => _open('mission', mission: 1)),
            _tile(Icons.center_focus_strong, 'Mission 2 - Hover & Directional Control', _bestText(best['mission2']), () => _open('mission', mission: 2)),
            _tile(Icons.route, 'Mission 3 - AR Navigation Challenge', _bestText(best['mission3']), () => _open('mission', mission: 3)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('Server'),
              subtitle: Text(api.baseUrl),
              onTap: _editServer,
            ),
          ],
        ),
      ),
    );
  }

  String _bestText(dynamic v) => v == null ? 'Not completed yet' : 'Best score: $v / 100';

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
        child: ListTile(
          leading: Icon(icon, color: Colors.orangeAccent),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  Future<void> _editServer() async {
    final c = TextEditingController(text: api.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(controller: c, keyboardType: TextInputType.url, autocorrect: false),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await api.setBaseUrl(c.text);
      _load();
    }
  }
}
