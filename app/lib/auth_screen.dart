import 'package:flutter/material.dart';

import 'game_service.dart';

// Casino palette (emerald felt + gold).
const _gold1 = Color(0xFFFCEFB6);
const _gold2 = Color(0xFFE6C257);
const _gold3 = Color(0xFFB07E1B);
const _goldSoft = Color(0xFFD9BE6E);
const _cream = Color(0xFFE9DEBC);

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
  bool _obscure = true;

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
    if (_registerMode) {
      if (u.isEmpty || p.isEmpty) return;
      widget.service.register(u, p, _name.text.trim());
    } else {
      if (u.isEmpty && p.isEmpty) {
        widget.service.devLogin(); // test: empty = instant guest login
      } else if (u.isNotEmpty && p.isNotEmpty) {
        widget.service.login(u, p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final online = s.conn == Conn.online;
    final busy = s.authPending;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg_felt.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Color(0xCC0A1410), BlendMode.darken),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _logo(),
                  const SizedBox(height: 36),
                  _glassCard(s, online, busy),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_gold1, _gold2, _gold3],
      ).createShader(r),
      child: Column(
        children: [
          SizedBox(
            height: 70,
            child: Stack(
              alignment: Alignment.topCenter,
              children: const [
                Text('♠', style: TextStyle(fontSize: 62, color: Colors.white, height: 1)),
                Positioned(
                    top: 6,
                    child: Text('♛', style: TextStyle(fontSize: 20, color: Colors.white))),
              ],
            ),
          ),
          const Text(
            'BACCARAT',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 44,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard(GameService s, bool online, bool busy) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold2.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(color: _gold2.withValues(alpha: 0.28), blurRadius: 26, spreadRadius: -4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_username, 'Player ID', Icons.person_outline),
          const SizedBox(height: 16),
          _field(_password, 'Password', Icons.lock_outline,
              obscure: _obscure,
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: _goldSoft, size: 20),
              )),
          if (_registerMode) ...[
            const SizedBox(height: 16),
            _field(_name, '표시 이름 (선택)', Icons.badge_outlined),
          ],
          if (s.authError != null) ...[
            const SizedBox(height: 14),
            Text(s.authError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13)),
          ],
          if (!online) ...[
            const SizedBox(height: 12),
            Text(s.conn == Conn.connecting ? '서버 연결 중… (최대 50초)' : '연결 끊김 — 재시도 중…',
                style: TextStyle(color: _cream.withValues(alpha: 0.6), fontSize: 12)),
          ],
          const SizedBox(height: 24),
          _loginButton(online, busy),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: busy ? null : () => _toast('준비 중입니다'),
            child: const Text('Forgot Password?',
                style: TextStyle(
                    fontFamily: 'serif',
                    color: _goldSoft,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: _goldSoft)),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: busy
                ? null
                : () => setState(() {
                      _registerMode = !_registerMode;
                      widget.service.authError = null;
                    }),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'serif', fontSize: 14, color: _cream),
                children: [
                  TextSpan(text: _registerMode ? '이미 계정이 있나요? ' : 'First time? '),
                  TextSpan(
                    text: _registerMode ? 'Login' : 'Create Account',
                    style: const TextStyle(
                        color: _gold2,
                        decoration: TextDecoration.underline,
                        decorationColor: _gold2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (!_registerMode)
            Text('테스트: 빈칸으로 LOGIN을 누르면 바로 입장',
                style: TextStyle(fontSize: 10, color: _cream.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _loginButton(bool online, bool busy) {
    final enabled = online && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        onTap: enabled ? _submit : null,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8E394), Color(0xFFE2B94C), Color(0xFFC8962C)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: _gold2.withValues(alpha: 0.5), blurRadius: 18, spreadRadius: -2),
            ],
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A370A)))
              : Text(
                  _registerMode ? 'CREATE ACCOUNT' : 'LOGIN',
                  style: const TextStyle(
                    fontFamily: 'serif',
                    color: Color(0xFF4A370A),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 17),
      cursorColor: _gold2,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _cream.withValues(alpha: 0.65), fontSize: 17),
        prefixIcon: Icon(icon, color: _goldSoft),
        suffixIcon: suffix,
        isDense: true,
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: _goldSoft.withValues(alpha: 0.6))),
        focusedBorder:
            const UnderlineInputBorder(borderSide: BorderSide(color: _gold2, width: 1.6)),
      ),
    );
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 1)));
}
