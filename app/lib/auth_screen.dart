import 'package:flutter/material.dart';

import 'game_service.dart';
import 'widgets.dart';

class AuthScreen extends StatefulWidget {
  final GameService service;
  const AuthScreen(this.service, {super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _registerMode = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final u = _username.text.trim();
    final p = _password.text;
    if (u.isEmpty || p.isEmpty) return;
    if (_registerMode) {
      widget.service.register(u, p, _name.text.trim());
    } else {
      widget.service.login(u, p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final online = s.conn == Conn.online;
    final busy = s.authPending;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🃏 Baccarat',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: goldColor)),
                const SizedBox(height: 4),
                Text(_registerMode ? '회원가입' : '로그인',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colors.white70)),
                const SizedBox(height: 24),

                _field(_username, '아이디', icon: Icons.person),
                const SizedBox(height: 12),
                _field(_password, '비밀번호', icon: Icons.lock, obscure: true),
                if (_registerMode) ...[
                  const SizedBox(height: 12),
                  _field(_name, '표시 이름 (선택)', icon: Icons.badge),
                ],

                if (s.authError != null) ...[
                  const SizedBox(height: 14),
                  Text(s.authError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: bankerColor, fontSize: 13)),
                ],
                if (!online) ...[
                  const SizedBox(height: 14),
                  Text(s.conn == Conn.connecting ? '서버 연결 중… (최대 50초)' : '서버 연결 끊김 — 재시도 중…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: (online && !busy) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(_registerMode ? '회원가입' : '로그인',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            _registerMode = !_registerMode;
                            widget.service.authError = null;
                          }),
                  child: Text(
                    _registerMode ? '이미 계정이 있어요 — 로그인' : '계정이 없어요 — 회원가입',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {required IconData icon, bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: feltLight,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: goldColor),
        ),
      ),
    );
  }
}
