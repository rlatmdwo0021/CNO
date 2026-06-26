import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import 'game_service.dart';
import 'models.dart';
import 'widgets.dart';

class TableScreen extends StatefulWidget {
  final GameService service;
  const TableScreen(this.service, {super.key});
  @override
  State<TableScreen> createState() => _TableScreenState();
}

/// One chip flying across the table (placement, win return, or loss to dealer).
class _Fly {
  final int value;
  final Offset from;
  final Offset to;
  final AnimationController ctrl;
  _Fly(this.value, this.from, this.to, this.ctrl);
}

class _TableScreenState extends State<TableScreen> with TickerProviderStateMixin {
  Timer? _ticker;

  // Keys for measuring positions (in _stack's coordinate space).
  final _stackKey = GlobalKey();
  final _trayKey = GlobalKey();
  final _dealerKey = GlobalKey();
  final _zoneKeys = {'player': GlobalKey(), 'tie': GlobalKey(), 'banker': GlobalKey()};
  final _chipKeys = <int, GlobalKey>{};

  // Zones whose pile is hidden after settlement (chips have flown off) until the
  // next betting round clears it. The pile itself is derived from myBets.
  final Set<String> _settled = {};

  final List<_Fly> _flying = [];
  String _lastPhase = '';

  // Card reveal choreography: deal order P1,B1,P2,B2,(P3),(B3); each flips in turn.
  late final AnimationController _revealCtrl;
  List<(String, int)> _revealOrder = [];

  @override
  void initState() {
    super.initState();
    for (final c in widget.service.chips) {
      _chipKeys[c] = GlobalKey();
    }
    _lastPhase = widget.service.phase;
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    widget.service.addListener(_onServiceChange);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.service.removeListener(_onServiceChange);
    _revealCtrl.dispose();
    for (final f in _flying) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  int get _secondsLeft {
    final s = widget.service;
    if (s.phase != 'betting') return 0;
    final ms = s.endsAt - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  // ---- reacting to phase changes (settle / new round) ----
  void _onServiceChange() {
    final s = widget.service;
    if (s.phase == _lastPhase) return;
    final prev = _lastPhase;
    _lastPhase = s.phase;
    if (s.phase == 'settled') {
      _startReveal(s);
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleAnim(s));
    } else if (s.phase == 'betting' && prev != 'betting') {
      if (mounted) setState(() => _settled.clear());
    }
  }

  /// Break a stake total into chip denominations, largest first (for the pile).
  List<int> _pile(int total) {
    final out = <int>[];
    var rem = total;
    for (final c in const [10000, 1000, 500, 100, 25]) {
      while (rem >= c && out.length < 12) {
        out.add(c);
        rem -= c;
      }
    }
    return out;
  }

  // ---- coordinate helpers ----
  Offset? _center(GlobalKey? k) {
    final ctx = k?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stackBox == null || !box.hasSize) return null;
    final g = box.localToGlobal(box.size.center(Offset.zero));
    return stackBox.globalToLocal(g);
  }

  void _fly(int value, Offset from, Offset to, {VoidCallback? onArrive, int delayMs = 0}) {
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    final f = _Fly(value, from, to, ctrl);
    ctrl.addStatusListener((st) {
      if (st == AnimationStatus.completed) {
        if (mounted) {
          setState(() => _flying.remove(f));
        } else {
          _flying.remove(f);
        }
        ctrl.dispose();
        onArrive?.call();
      }
    });
    setState(() => _flying.add(f));
    if (delayMs > 0) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) {
          ctrl.forward();
        } else {
          ctrl.dispose();
        }
      });
    } else {
      ctrl.forward();
    }
  }

  // ---- card reveal choreography ----
  void _startReveal(GameService s) {
    final p = s.player, b = s.banker;
    if (p == null || b == null) return;
    final order = <(String, int)>[];
    for (var i = 0; i < 2; i++) {
      order.add(('player', i));
      order.add(('banker', i));
    }
    if (p.cards.length > 2) order.add(('player', 2));
    if (b.cards.length > 2) order.add(('banker', 2));
    _revealOrder = order;
    _revealCtrl.duration = Duration(milliseconds: order.length * 360);
    _revealCtrl.forward(from: 0);
  }

  int _revealIndex(String side, int cardIdx) {
    for (var k = 0; k < _revealOrder.length; k++) {
      if (_revealOrder[k].$1 == side && _revealOrder[k].$2 == cardIdx) return k;
    }
    return -1;
  }

  // 0 = face-down, 1 = fully flipped to face, for the k-th dealt card.
  double _flipT(int k) {
    final n = _revealOrder.length;
    if (n == 0) return 1;
    final start = k / n, end = (k + 0.8) / n;
    final v = _revealCtrl.value;
    if (v >= end) return 1;
    if (v <= start) return 0;
    return (v - start) / (end - start);
  }

  // tie pushes player/banker (stake returned) -> treat as "to tray".
  bool? _won(String type, String? outcome) {
    if (outcome == null) return null;
    if (outcome == 'tie') return type == 'tie' ? true : null;
    return type == outcome;
  }

  void _settleAnim(GameService s) {
    final tray = _center(_trayKey);
    final dealer = _center(_dealerKey);
    for (final type in const ['player', 'tie', 'banker']) {
      final total = s.myBets[type] ?? 0;
      if (total <= 0) continue;
      final from = _center(_zoneKeys[type]);
      if (from == null) continue;
      final lost = _won(type, s.outcome) == false;
      final pile = _pile(total); // largest first
      for (int i = 0; i < pile.length && i < 6; i++) {
        final v = pile[i];
        // win/push: each chip returns to its own slot in the tray;
        // loss: all chips sweep to the dealer.
        final target = lost ? dealer : (_center(_chipKeys[v]) ?? tray);
        if (target == null) continue;
        _fly(v, from, target, delayMs: i * 70);
      }
      _settled.add(type); // hide the pile now that chips are flying off
    }
    if (mounted) setState(() {});
  }

  // ---- placing a bet ----
  void _place(GameService s, String type) {
    if (!s.canBet) return;
    final cur = s.myBets[type] ?? 0;
    final remaining = s.maxBet - cur;
    if (remaining <= 0) return _warn('이 영역은 최대 ${fmtCoins(s.maxBet)} 까지입니다');
    if (cur == 0 && s.chip < s.minBet) return _warn('최소 베팅 ${fmtCoins(s.minBet)} 이상이어야 합니다');
    // a chip larger than the room cap only tops the total up to the cap
    final amt = s.chip > remaining ? remaining : s.chip;
    if (amt > s.gold) return _warn('골드가 부족합니다');
    _settled.remove(type); // re-betting a just-cancelled/settled zone shows its pile again
    s.bet(type, amt);
    final from = _center(_chipKeys[s.chip]) ?? _center(_trayKey);
    final to = _center(_zoneKeys[type]);
    if (from != null && to != null) _fly(s.chip, from, to);
  }

  // ---- cancel all my bets (refund) + chips fly back to the tray ----
  void _cancel(GameService s) {
    if (!s.canBet || s.myBets.values.every((v) => v <= 0)) return;
    final tray = _center(_trayKey);
    s.myBets.forEach((type, total) {
      final from = _center(_zoneKeys[type]);
      if (from == null) return;
      final pile = _pile(total);
      for (int i = 0; i < pile.length && i < 6; i++) {
        final v = pile[i];
        final target = _center(_chipKeys[v]) ?? tray;
        if (target == null) continue;
        _fly(v, from, target, delayMs: i * 60);
      }
    });
    s.clearBets(); // server refunds; betsCleared clears the piles
  }

  // ---- repeat the previous round's bets ----
  void _repeat(GameService s) {
    if (!s.canBet) return;
    if (s.lastBets.isEmpty) return _warn('반복할 이전 베팅이 없습니다');
    final total = s.lastBets.values.fold<int>(0, (a, b) => a + b);
    if (total > s.gold) return _warn('골드가 부족합니다');
    s.lastBets.forEach((type, amt) {
      if (amt <= 0) return;
      _settled.remove(type);
      s.bet(type, amt);
      final from = _center(_trayKey);
      final to = _center(_zoneKeys[type]);
      if (from != null && to != null) _fly(_repChip(amt), from, to);
    });
  }

  // representative chip image for a flown stake total
  int _repChip(int amt) {
    for (final c in const [10000, 1000, 500, 100, 25]) {
      if (amt >= c) return c;
    }
    return 25;
  }

  Widget _actions(GameService s) {
    final hasBets = s.myBets.values.any((v) => v > 0);
    final canCancel = s.canBet && hasBets;
    final canRepeat = s.canBet && !hasBets && s.lastBets.isNotEmpty;
    final lastTotal = s.lastBets.values.fold<int>(0, (a, b) => a + b);
    return Row(
      children: [
        Expanded(
          child: _actionBtn(
            '취소',
            Icons.undo_rounded,
            canCancel,
            () => _cancel(s),
            const Color(0xFF7A1B22),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionBtn(
            lastTotal > 0 ? '반복  ${fmtCoins(lastTotal)}' : '반복',
            Icons.repeat_rounded,
            canRepeat,
            () => _repeat(s),
            const Color(0xFF1B5E45),
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, bool enabled, VoidCallback onTap, Color color) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, Color.lerp(color, Colors.black, 0.4)!],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cGold.withValues(alpha: 0.55), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cGoldBright, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  void _warn(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD54F), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ]),
      backgroundColor: const Color(0xFF8A1418),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: cGold, width: 1)),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return Scaffold(
      body: Container(
        decoration: casinoBg,
        child: SafeArea(
          child: Stack(
            key: _stackKey,
            children: [
              ListenableBuilder(
                listenable: s,
                builder: (context, _) => Column(
                  children: [
                    _topBar(s),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        child: Column(
                          children: [
                            _felt(s),
                            const SizedBox(height: 14),
                            _bettingZones(s),
                            const SizedBox(height: 14),
                            _chipSelector(s),
                            const SizedBox(height: 10),
                            _actions(s),
                            const SizedBox(height: 14),
                            _scoreboard(s),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // flying chips (above everything)
              for (final f in _flying)
                AnimatedBuilder(
                  animation: f.ctrl,
                  builder: (_, _) {
                    final t = Curves.easeInOut.transform(f.ctrl.value);
                    final p = Offset.lerp(f.from, f.to, t)!;
                    final lift = -38 * (4 * t * (1 - t)); // parabolic hop
                    return Positioned(
                      left: p.dx - 18,
                      top: p.dy - 18 + lift,
                      child: _chipImg(f.value, 36),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipImg(int value, double size) => SizedBox(
        width: size,
        height: size,
        child: Image.asset('assets/images/chip_$value.png'),
      );

  // ---- top bar ----
  Widget _topBar(GameService s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: s.leaveRoom,
                icon: const Icon(Icons.arrow_back, color: cGoldBright),
                tooltip: '로비',
              ),
              Expanded(
                child: Center(
                  key: _dealerKey,
                  child: goldText(const Text('Baccarat',
                      style: TextStyle(
                          fontFamily: 'serif',
                          fontStyle: FontStyle.italic,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white))),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          Row(
            children: [
              Text(s.roomName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 6),
              Text('한도 ${fmtCoins(s.minBet)}~${fmtCoins(s.maxBet)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const Spacer(),
              CoinBar(gold: s.gold, diamond: s.diamond, compact: true, onTapGold: s.devTopup),
            ],
          ),
        ],
      ),
    );
  }

  // ---- felt table with the two hands ----
  Widget _felt(GameService s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [Color(0xFF1B6B4F), Color(0xFF0C3D2C)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cGold.withValues(alpha: 0.6), width: 1.5),
      ),
      child: AnimatedBuilder(
        animation: _revealCtrl,
        builder: (_, _) => Row(
          children: [
            Expanded(child: _handCol('PLAYER', 'player', s.player, s.outcome == 'player', playerColor)),
            Container(width: 1, height: 96, color: cGold.withValues(alpha: 0.3)),
            Expanded(child: _handCol('BANKER', 'banker', s.banker, s.outcome == 'banker', bankerColor)),
          ],
        ),
      ),
    );
  }

  Widget _handCol(String title, String side, HandView? hand, bool isWinner, Color color) {
    return Column(
      children: [
        goldText(Text(title,
            style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2))),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          decoration: isWinner
              ? BoxDecoration(
                  color: cGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cGold))
              : null,
          // hide the total until the cards have (mostly) been turned over
          child: Text((hand == null || !_revealDone) ? '–' : '${hand.value}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: hand == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [_CardBack(), _CardBack()],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var j = 0; j < hand.cards.length; j++) _revealCard(side, j, hand.cards[j]),
                  ],
                ),
        ),
      ],
    );
  }

  bool get _revealDone => _revealOrder.isEmpty || _revealCtrl.value >= 0.85;

  /// A card in a hand: face-down until its turn, then it flips to the real face.
  Widget _revealCard(String side, int cardIdx, CardView card) {
    final k = _revealIndex(side, cardIdx);
    if (k == -1) return _flipCard(card, 1); // no choreography → static face
    // first two cards are always on the table; 3rd card pops in at its turn
    final present = cardIdx < 2 || _revealCtrl.value >= k / _revealOrder.length;
    if (!present) return const SizedBox.shrink();
    return _flipCard(card, _flipT(k));
  }

  Widget _flipCard(CardView card, double t) {
    final angle = t * pi; // 0 = back, pi = fully turned to face
    final front = t > 0.5;
    final child = front
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(pi), // un-mirror the face
            child: _cardFace(card),
          )
        : const _CardBack();
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(angle),
      child: child,
    );
  }

  Widget _cardFace(CardView card) {
    final color = card.isRed ? bankerColor : const Color(0xFF111111);
    return Container(
      width: 40,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Center(
        child: Text('${card.rank}${card.suitSymbol}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  // ---- betting zones (player / tie+timer / banker) ----
  Widget _bettingZones(GameService s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _zone(s, 'player', 'PLAYER', '1 : 1', cZoneBlue)),
        const SizedBox(width: 6),
        Expanded(child: _tieZone(s)),
        const SizedBox(width: 6),
        Expanded(child: _zone(s, 'banker', 'BANKER', '0.95 : 1', cZoneRed)),
      ],
    );
  }

  Widget _zone(GameService s, String type, String label, String payout, Color color) {
    final total = s.tableBets[type] ?? 0;
    final mine = s.myBets[type] ?? 0;
    final enabled = s.canBet;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? () => _place(s, type) : null,
        child: Container(
          key: _zoneKeys[type],
          height: 124,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, Color.lerp(color, Colors.black, 0.45)!],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cGold.withValues(alpha: 0.7), width: 1.3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
              Text(payout, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              _myStack(type),
              const SizedBox(height: 2),
              if (_settled.contains(type)) const SizedBox(height: 18) else _betChip(total, mine),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tieZone(GameService s) {
    final total = s.tableBets['tie'] ?? 0;
    final mine = s.myBets['tie'] ?? 0;
    final enabled = s.canBet;
    final left = _secondsLeft;
    return GestureDetector(
      onTap: enabled ? () => _place(s, 'tie') : null,
      child: Container(
        key: _zoneKeys['tie'],
        height: 124,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF146B3F), Color(0xFF062A18)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cGold.withValues(alpha: 0.7), width: 1.3),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('TIE',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
            const SizedBox(height: 4),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(color: cGoldBright, width: 2),
              ),
              alignment: Alignment.center,
              child: s.phase == 'betting'
                  ? Text('$left',
                      style: const TextStyle(color: cGoldBright, fontWeight: FontWeight.bold, fontSize: 18))
                  : Text(s.phase == 'locked' ? '딜' : '8:1',
                      style: const TextStyle(color: cGoldBright, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(height: 2),
            _myStack('tie'),
            if (total > 0 && !_settled.contains('tie'))
              Text('${fmtCoins(total)}${mine > 0 ? ' (나)' : ''}',
                  style: TextStyle(
                      color: mine > 0 ? cGoldBright : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  /// My resting chips piled on a zone (derived from my stake total; largest
  /// denomination at the bottom). Hidden while a settlement is flying off.
  Widget _myStack(String type) {
    if (_settled.contains(type)) return const SizedBox(height: 26);
    final total = widget.service.myBets[type] ?? 0;
    final pile = _pile(total); // largest first
    if (pile.isEmpty) return const SizedBox(height: 26);
    final show = pile.length > 5 ? pile.sublist(0, 5) : pile;
    return SizedBox(
      height: 24 + (show.length - 1) * 5,
      width: 30,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // index 0 (largest) sits at the bottom
          for (int i = 0; i < show.length; i++)
            Positioned(bottom: i * 5.0, child: _chipImg(show[i], 24)),
        ],
      ),
    );
  }

  Widget _betChip(int total, int mine) {
    if (total <= 0) return const SizedBox(height: 18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mine > 0 ? cGoldBright : Colors.white54),
      ),
      child: Text('${fmtCoins(total)}${mine > 0 ? ' 나' : ''}',
          style: TextStyle(
              color: mine > 0 ? cGoldBright : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  // ---- chip tray (wine panel; pick a chip, then tap a zone) ----
  Widget _chipSelector(GameService s) {
    return Container(
      key: _trayKey,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6E1F26), Color(0xFF3A0E12)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cGold.withValues(alpha: 0.55), width: 1.3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [for (final c in s.chips) _chip(s, c)],
          ),
          const SizedBox(height: 8),
          Text('칩을 선택하고 베팅 영역을 탭하세요',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _chip(GameService s, int value) {
    final active = s.chip == value;
    return GestureDetector(
      onTap: () => s.setChip(value),
      child: AnimatedContainer(
        key: _chipKeys[value],
        duration: const Duration(milliseconds: 120),
        width: active ? 56 : 46,
        height: active ? 56 : 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: active ? Border.all(color: cGoldBright, width: 2.5) : null,
          boxShadow: active
              ? [BoxShadow(color: cGold.withValues(alpha: 0.65), blurRadius: 12, spreadRadius: -1)]
              : const [BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: Image.asset('assets/images/chip_$value.png'),
      ),
    );
  }

  // ---- white scoreboard (bead plate + big road + derived) ----
  Widget _scoreboard(GameService s) {
    final r = s.roadmap;
    Widget lbl(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(t,
              style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        );
    Widget derived(String t, List<RoadCell> cells, DerivedShape shape) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [lbl(t), RoadBoard(cells: cells, cell: 11, minCols: 6, builder: derivedCell(shape))],
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [lbl('BEAD PLATE'), RoadBoard(cells: r.bead, cell: 16, minCols: 9, builder: beadCell)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [lbl('BIG ROAD'), RoadBoard(cells: r.big, cell: 16, minCols: 9, builder: bigCell)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: derived('빅아이', r.bigEye, DerivedShape.disc)),
              const SizedBox(width: 8),
              Expanded(child: derived('스몰', r.small, DerivedShape.ring)),
              const SizedBox(width: 8),
              Expanded(child: derived('콕로치', r.cockroach, DerivedShape.slash)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A face-down card (shown before the reveal).
class _CardBack extends StatelessWidget {
  const _CardBack();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cGold.withValues(alpha: 0.6)),
      ),
      child: Image.asset('assets/images/card_back.png', fit: BoxFit.cover),
    );
  }
}
