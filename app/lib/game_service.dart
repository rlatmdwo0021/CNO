import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

/// Resolve the WebSocket backend address.
///  - If SERVER_URL is provided at build time, use it (needed for native apps).
///  - On web, derive it from the page's own origin, so opening the app at
///    `http://PC-IP:8080` connects to `ws://PC-IP:8080` — same host, same port.
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

enum AppView { lobby, table }

/// Holds all client state and talks the WebSocket protocol. Widgets listen via
/// [ChangeNotifier]; the UI never touches the socket directly.
class GameService extends ChangeNotifier {
  WebSocketChannel? _ch;
  Conn conn = Conn.connecting;

  // --- auth state ---
  bool loggedIn = false;
  bool authPending = false; // a login/register is in flight
  String? authError; // last auth failure message (shown on the auth screen)
  String? _sessionToken; // in-memory only; lets us re-auth on reconnect

  String? playerId;
  String name = '';
  String grade = '브론즈';
  int gold = 0; // free coins — the betting currency
  int diamond = 0; // paid coins — 0 until the payment system exists
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

  int chip = 100; // selected chip denomination (placed onto a zone)
  final List<int> chips = const [25, 100, 500, 1000, 10000];
  final Map<String, int> myBets = {}; // betType -> my stake this round
  final Map<String, int> tableBets = {}; // betType -> everyone's stake this round
  final Map<String, int> lastBets = {}; // my bets from the previous round (for 반복)

  // --- navigation ---
  AppView view = AppView.lobby;
  List<GameInfo> games = [];
  List<RoomInfo> rooms = [];
  String roomsGameId = ''; // which game the current `rooms` list belongs to
  String? roomId; // current room (null = not in a room)
  String roomName = '';
  String roomGameId = 'baccarat'; // 'baccarat' | 'roulette' — routes the table screen

  // --- roulette ---
  String? winning; // winning pocket id ('0'|'00'|'1'..'36')
  String? winColor; // 'red' | 'black' | 'green'
  List<String> recent = []; // recent winning pockets, oldest first
  int lastNet = 0; // my net coins from the last spin (for the result banner)

  bool get canBet => phase == 'betting' && conn == Conn.online && roomId != null;

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
      // Reconnect within the same run: re-auth with the in-memory token.
      // Otherwise wait for the user to log in / register on the AuthScreen.
      if (_sessionToken != null) _send({'t': 'auth', 'token': _sessionToken});
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

  /// Cancel & refund all my bets in the current betting window.
  void clearBets() {
    if (conn != Conn.online || roomId == null) return;
    _send({'t': 'clearBets'});
  }

  /// TEST ONLY — remove before release. Tap the gold balance to top up coins;
  /// the server credits the wallet and echoes the new balance.
  void devTopup() {
    if (conn != Conn.online) return;
    _send({'t': 'devTopup'});
  }

  /// Place [amount] on [type]. Limit checks happen in the UI (so it can show a
  /// warning); the server still re-validates authoritatively.
  void bet(String type, int amount) {
    if (!canBet || amount <= 0) return;
    _send({'t': 'bet', 'betType': type, 'amount': amount});
  }

  /// Roulette: place [amount] on a spot id (e.g. 's:17', 'red', 'dz:2').
  void betSpot(String spotId, int amount) {
    if (!canBet || amount <= 0) return;
    _send({'t': 'bet', 'spotId': spotId, 'amount': amount});
  }

  void login(String username, String password) {
    if (conn != Conn.online) return;
    authPending = true;
    authError = null;
    notifyListeners();
    _send({'t': 'login', 'username': username, 'password': password});
  }

  void register(String username, String password, String name) {
    if (conn != Conn.online) return;
    authPending = true;
    authError = null;
    notifyListeners();
    _send({'t': 'register', 'username': username, 'password': password, 'name': name});
  }

  /// Test-only quick login: server logs into (or creates) a shared guest
  /// account. Idempotent — no login/register race.
  void devLogin() {
    if (conn != Conn.online) return;
    authPending = true;
    authError = null;
    notifyListeners();
    _send({'t': 'guest'});
  }

  /// Return to the login screen. Next login rebinds this socket on the server.
  void logout() {
    if (roomId != null) _send({'t': 'leaveRoom'});
    _sessionToken = null;
    loggedIn = false;
    authError = null;
    playerId = null;
    name = '';
    phase = 'idle';
    feed.clear();
    view = AppView.lobby;
    games = [];
    rooms = [];
    roomId = null;
    notifyListeners();
  }

  // --- rooms (the lobby browses rooms per game tab) ---
  void refreshRooms(String gameId) {
    if (conn == Conn.online) _send({'t': 'listRooms', 'gameId': gameId});
  }

  void joinRoom(String id) {
    if (conn != Conn.online) return;
    _send({'t': 'joinRoom', 'roomId': id}); // view switches on 'roomJoined'
  }

  void leaveRoom() {
    if (roomId != null) _send({'t': 'leaveRoom'});
    roomId = null;
    roomName = '';
    phase = 'idle';
    player = null;
    banker = null;
    outcome = null;
    feed.clear();
    view = AppView.lobby;
    notifyListeners();
  }

  void _log(String s) {
    feed.insert(0, s);
    if (feed.length > 40) feed.removeRange(40, feed.length);
  }

  Future<void> _onMessage(dynamic data) async {
    final m = jsonDecode(data as String) as Map<String, dynamic>;
    final t = m['t'];
    // Ignore room events that aren't for the room we're currently in.
    if ((t == 'open' || t == 'locked' || t == 'settled' || t == 'spin' || t == 'bet' || t == 'betsCleared') &&
        m['roomId'] != roomId) {
      return;
    }
    switch (t) {
      case 'session':
        if (m['token'] != null) _sessionToken = m['token'] as String;
        loggedIn = true;
        authPending = false;
        authError = null;
        playerId = m['playerId'] as String;
        name = m['name'] as String;
        grade = (m['grade'] ?? '브론즈') as String;
        gold = m['gold'] as int;
        diamond = (m['diamond'] ?? 0) as int;
        games = (m['games'] as List).map((g) => GameInfo.fromJson(g as Map<String, dynamic>)).toList();
        view = AppView.lobby;
        roomId = null;
        break;
      case 'authError':
        authError = m['message'] as String?;
        authPending = false;
        loggedIn = false; // back to the login screen (e.g. expired session)
        _sessionToken = null;
        view = AppView.lobby;
        roomId = null;
        break;
      case 'rooms':
        roomsGameId = (m['gameId'] ?? '') as String;
        rooms = (m['rooms'] as List).map((r) => RoomInfo.fromJson(r as Map<String, dynamic>)).toList();
        break;
      case 'roomJoined':
        roomId = m['roomId'] as String;
        roomName = m['name'] as String;
        roomGameId = (m['gameId'] ?? 'baccarat') as String;
        recent = List<String>.from((m['recent'] ?? const []) as List);
        winning = null;
        minBet = m['minBet'] as int;
        maxBet = m['maxBet'] as int;
        // default-select a chip valid for this room's per-bet limits
        if (chip < minBet || chip > maxBet) {
          chip = chips.firstWhere((c) => c >= minBet && c <= maxBet, orElse: () => chips.first);
        }
        phase = m['phase'] as String;
        endsAt = (m['endsAt'] ?? 0) as int;
        roadmap = Roadmap.fromJson(m['roadmap'] as Map<String, dynamic>);
        player = null;
        banker = null;
        outcome = null;
        feed.clear();
        myBets.clear();
        tableBets.clear();
        view = AppView.table;
        break;
      case 'open':
        phase = 'betting';
        roundId = m['roundId'] as String;
        endsAt = m['endsAt'] as int;
        player = null;
        banker = null;
        outcome = null;
        myResults = [];
        // remember last round's bets (for the 반복 button) before clearing
        if (myBets.isNotEmpty) {
          lastBets
            ..clear()
            ..addAll(myBets);
        }
        myBets.clear();
        tableBets.clear();
        break;
      case 'bet':
        final bType = (m['betType'] ?? m['spotId']) as String;
        final amt = m['amount'] as int;
        tableBets[bType] = (tableBets[bType] ?? 0) + amt; // everyone (incl. me)
        if (m['playerId'] == playerId) {
          myBets[bType] = (myBets[bType] ?? 0) + amt;
        }
        break;
      case 'betsCleared':
        final cleared = m['byType'] as Map<String, dynamic>;
        final isMe = m['playerId'] == playerId;
        cleared.forEach((type, v) {
          final amt = v as int;
          final left = (tableBets[type] ?? 0) - amt;
          if (left > 0) {
            tableBets[type] = left;
          } else {
            tableBets.remove(type);
          }
          if (isMe) myBets.remove(type);
        });
        break;
      case 'betAck':
        if (m['ok'] == true) {
          if (m['balance'] != null) gold = m['balance'] as int;
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
      case 'spin':
        phase = 'settled';
        winning = m['winning'] as String;
        winColor = m['color'] as String;
        recent = List<String>.from((m['recent'] ?? const []) as List);
        final settled = (m['settled'] as List).cast<Map<String, dynamic>>();
        lastNet = settled
            .where((x) => x['playerId'] == playerId)
            .fold<int>(0, (a, x) => a + (x['net'] as int));
        break;
      case 'balance':
        gold = (m['gold'] ?? gold) as int;
        diamond = (m['diamond'] ?? diamond) as int;
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
