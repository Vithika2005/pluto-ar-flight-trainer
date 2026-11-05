import 'package:flutter/material.dart';
import '../services/api.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController(text: api.baseUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _register = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await api.setBaseUrl(_server.text);
      await api.health();
      setState(() => _info = 'Connected to the server.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await api.setBaseUrl(_server.text);
      if (_register) {
        await api.register(_user.text.trim(), _pass.text);
      } else {
        await api.login(_user.text.trim(), _pass.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.flight, size: 64, color: Colors.orangeAccent),
                  const SizedBox(height: 8),
                  Text('Pluto AR Flight Trainer', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text('Learn to fly before you fly.', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Server URL', hintText: 'http://192.168.1.10:3000', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _user, autocorrect: false, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  if (_info != null) Text(_info!, style: const TextStyle(color: Colors.greenAccent)),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _busy ? null : _submit, child: Text(_register ? 'Create account' : 'Log in')),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'I already have an account' : 'Create a new account'),
                  ),
                  OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Test server connection')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
