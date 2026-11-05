import 'package:flutter/material.dart';
import '../services/api.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          bottom: const TabBar(tabs: [Tab(text: 'My attempts'), Tab(text: 'Leaderboard')]),
        ),
        body: const TabBarView(children: [_AttemptsTab(), _LeaderboardTab()]),
      ),
    );
  }
}

const _modeNames = {
  'tutorial': 'Tutorial',
  'mission1': 'Mission 1',
  'mission2': 'Mission 2',
  'mission3': 'Mission 3',
};

class _AttemptsTab extends StatelessWidget {
  const _AttemptsTab();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: api.attempts(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('No attempts yet - go fly!'));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            final ok = r['success'] == true;
            return ListTile(
              leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.greenAccent : Colors.redAccent),
              title: Text('${_modeNames[r['mode']] ?? r['mode']} - score ${r['score']}'),
              subtitle: Text(
                '${(r['durationSec'] as num).toStringAsFixed(0)} s - ${r['collisions']} collisions - '
                'stability ${(r['stability'] as num).toStringAsFixed(0)}%\n${r['createdAt']} UTC',
              ),
              isThreeLine: true,
            );
          },
        );
      },
    );
  }
}

class _LeaderboardTab extends StatefulWidget {
  const _LeaderboardTab();
  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  String _mode = 'mission1';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'tutorial', label: Text('Tut')),
              ButtonSegment(value: 'mission1', label: Text('M1')),
              ButtonSegment(value: 'mission2', label: Text('M2')),
              ButtonSegment(value: 'mission3', label: Text('M3')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(_mode),
            future: api.leaderboard(_mode),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Nobody has completed this yet.'));
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text('${rows[i]['username']}'),
                  subtitle: Text('best time ${(rows[i]['bestTime'] as num).toStringAsFixed(0)} s - ${rows[i]['attempts']} attempts'),
                  trailing: Text('${rows[i]['bestScore']}', style: Theme.of(context).textTheme.titleLarge),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
