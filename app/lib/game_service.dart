import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

const String kTokenKey = 'casino_token';

/// Resolve the WebSocket backend address.
///  - If SERVER_URL is provided at build time, use it (needed for native apps).
///  - On web, derive it from the page's own origin, so opening the app at
///    http://<pc-ip>:8080 connects to ws://<pc-ip>:8080 — same host, same port.
///    Phones therefore work with no rebuild: load the page, the socket follows.
String resolveServerUrl() {
  const override = String.fromEnvironment('SERVER_URL');
  if (override.isNotEmpty) return override;
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') {
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
    final port = base.hasPort ? base.port : (base.scheme == 'https' ? 443 : 80);
    return '$wsScheme://${base.host}:$port';
  }
  return 'ws://localhost:8080'; // native fallback
}

enum Conn { connecting, online, offline }

/// Holds all client state and talks the WebSocket protocol. Widgets listen via
/// [ChangeNotifier]; the UI never touches the socket directly.
class GameService extends ChangeNotifier {
  WebSocketChannel? _ch;
  Conn conn = Conn.connecting;

  String? playerId;
  String name = '';
  int balance = 0;
  int minBet = 10;
  int maxBet = 500;

  String phase = 'idle'; // idle | betting | locked | settled
  String? roundId;
  int endsAt = 0; // betting window end (epoch ms)

  HandView? player;
  HandView? banker;
  String? outcome; // player | banker | tie
  List<SettledBet> myResults = [];
  final List<String> feed = [];
  Roadmap roadmap = Roadmap.empty();

  int chip = 50;
  final List<int> chips = const [10, 50, 100, 250];

  bool get canBet => phase == 'betting' && conn == Conn.online;

  Future<void> start() => _connect();

  Future<void> _connect() async {
    conn = Conn.connecting;
    notifyListeners();
    try {
      final ch = WebSocketChannel.connect(Uri.parse(resolveServerUrl()));
      _ch = ch;
      ch.stream.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone());
      await ch.ready;
      conn = Conn.online;
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(kTokenKey);
      _send(token != null ? {'t': 'auth', 'token': token} : {'t': 'register'});
      notifyListeners();
    } catch (_) {
      _onDone();
    }
  }

  void _onDone() {
    conn = Conn.offline;
    phase = 'idle';
    notifyListeners();
    Future.delayed(const Duration(seconds: 2), () {
      if (conn == Conn.offline) _connect();
    });
  }

  void _send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

  void setChip(int c) {
    chip = c;
    notifyListeners();
  }

  void bet(String type) {
    if (!canBet) return;
    _send({'t': 'bet', 'betType': type, 'amount': chip});
  }

  Future<void> newAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTokenKey);
    playerId = null;
    name = '';
    _send({'t': 'register'});
  }

  void _log(String s) {
    feed.insert(0, s);
    if (feed.length > 40) feed.removeRange(40, feed.length);
  }

  Future<void> _onMessage(dynamic data) async {
    final m = jsonDecode(data as String) as Map<String, dynamic>;
    switch (m['t']) {
      case 'session':
        if (m['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(kTokenKey, m['token'] as String);
        }
        playerId = m['playerId'] as String;
        name = m['name'] as String;
        balance = m['balance'] as int;
        minBet = m['limits']['minBet'] as int;
        maxBet = m['limits']['maxBet'] as int;
        phase = m['phase'] as String;
        endsAt = (m['endsAt'] ?? 0) as int;
        roadmap = Roadmap.fromJson(m['roadmap'] as Map<String, dynamic>);
        break;
      case 'authError':
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(kTokenKey);
        _send({'t': 'register'});
        break;
      case 'open':
        phase = 'betting';
        roundId = m['roundId'] as String;
        endsAt = m['endsAt'] as int;
        player = null;
        banker = null;
        outcome = null;
        myResults = [];
        break;
      case 'bet':
        final mine = m['playerId'] == playerId;
        _log('${mine ? '나' : m['playerId']} → ${m['betType']} ${m['amount']}');
        break;
      case 'betAck':
        if (m['ok'] == true) {
          if (m['balance'] != null) balance = m['balance'] as int;
        } else {
          _log('베팅 거절: ${m['error']}');
        }
        break;
      case 'locked':
        phase = 'locked';
        break;
      case 'settled':
        phase = 'settled';
        player = HandView.fromJson(m['player'] as Map<String, dynamic>);
        banker = HandView.fromJson(m['banker'] as Map<String, dynamic>);
        outcome = m['outcome'] as String;
        roadmap = Roadmap.fromJson(m['roadmap'] as Map<String, dynamic>);
        myResults = (m['settled'] as List)
            .map((s) => SettledBet.fromJson(s as Map<String, dynamic>))
            .where((s) => s.playerId == playerId)
            .toList();
        for (final r in myResults) {
          final tag = r.won == null ? '푸시' : (r.won! ? '승' : '패');
          _log('내 ${r.betType} $tag ${r.net >= 0 ? '+' : ''}${r.net}');
        }
        break;
      case 'balance':
        balance = m['balance'] as int;
        break;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ch?.sink.close();
    super.dispose();
  }
}
