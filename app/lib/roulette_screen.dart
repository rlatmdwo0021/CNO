import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'game_service.dart';
import 'widgets.dart';

// American wheel pocket order (clockwise).
const List<String> _americanOrder = [
  '0', '28', '9', '26', '30', '11', '7', '20', '32', '17', '5', '22', '34', '15', '3', '24', '36',
  '13', '1', '00', '27', '10', '25', '29', '12', '8', '19', '31', '18', '6', '21', '33', '16', '4',
  '23', '35', '14', '2'
];

class RouletteScreen extends StatefulWidget {
  final GameService service;
  const RouletteScreen(this.service, {super.key});
  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _Fly {
  final int value;
  final Offset from;
  final Offset to;
  final AnimationController ctrl;
  _Fly(this.value, this.from, this.to, this.ctrl);
}

class _RouletteScreenState extends State<RouletteScreen> with TickerProviderStateMixin {
  Timer? _ticker;
  String _lastPhase = '';

  // wheel
  late final Ticker _freeTicker;
  late final AnimationController _landCtrl;
  double _ballAngle = 0;
  double _landBase = 0, _landTarget = 0;
  bool _spinning = false;
  bool _landed = false;

  // chip fly + spot positions
  final _stackKey = GlobalKey();
  final _trayKey = GlobalKey();
  final _chipKeys = <int, GlobalKey>{};
  final _spotKeys = <String, GlobalKey>{};
  final List<_Fly> _flying = [];

  @override
  void initState() {
    super.initState();
    for (final c in widget.service.chips) {
      _chipKeys[c] = GlobalKey();
    }
    _lastPhase = widget.service.phase;
    _landCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    _landCtrl.addListener(() {
      final t = Curves.easeOutCubic.transform(_landCtrl.value);
      setState(() => _ballAngle = _landBase + (_landTarget - _landBase) * t);
    });
    _landCtrl.addStatusListener((st) {
      if (st == AnimationStatus.completed) setState(() => _landed = true);
    });
    _freeTicker = createTicker((_) {
      if (_spinning) setState(() => _ballAngle += 0.30);
    });
    widget.service.addListener(_onChange);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.service.removeListener(_onChange);
    _freeTicker.dispose();
    _landCtrl.dispose();
    for (final f in _flying) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  void _onChange() {
    final s = widget.service;
    if (s.phase == _lastPhase) return;
    _lastPhase = s.phase;
    if (s.phase == 'locked') {
      setState(() {
        _spinning = true;
        _landed = false;
      });
      _freeTicker.start();
    } else if (s.phase == 'settled' && s.winning != null) {
      _land(s.winning!);
    } else if (s.phase == 'betting') {
      setState(() => _landed = false);
    }
  }

  void _land(String winning) {
    final idx = _americanOrder.indexOf(winning);
    if (idx < 0) return;
    final sector = 2 * pi / _americanOrder.length;
    final base = _ballAngle;
    var target = idx * sector;
    while (target < base + 3 * 2 * pi) {
      target += 2 * pi;
    }
    _spinning = false;
    _freeTicker.stop();
    _landBase = base;
    _landTarget = target;
    _landCtrl.forward(from: 0);
  }

  int get _secondsLeft {
    final s = widget.service;
    if (s.phase != 'betting') return 0;
    final ms = s.endsAt - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  // ---- positions / fly ----
  GlobalKey _spotKey(String id) => _spotKeys.putIfAbsent(id, () => GlobalKey());

  Offset? _center(GlobalKey? k) {
    final ctx = k?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stackBox == null || !box.hasSize) return null;
    final g = box.localToGlobal(box.size.center(Offset.zero));
    return stackBox.globalToLocal(g);
  }

  void _fly(int value, Offset from, Offset to, {int delayMs = 0}) {
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    final f = _Fly(value, from, to, ctrl);
    ctrl.addStatusListener((st) {
      if (st == AnimationStatus.completed) {
        if (mounted) setState(() => _flying.remove(f));
        ctrl.dispose();
      }
    });
    setState(() => _flying.add(f));
    if (delayMs > 0) {
      Future.delayed(Duration(milliseconds: delayMs), () => mounted ? ctrl.forward() : ctrl.dispose());
    } else {
      ctrl.forward();
    }
  }

  // ---- betting ----
  void _place(String spotId) {
    final s = widget.service;
    if (!s.canBet) return;
    final cur = s.myBets[spotId] ?? 0;
    final remaining = s.maxBet - cur;
    if (remaining <= 0) return _warn('이 칸은 최대 ${fmtCoins(s.maxBet)} 까지입니다');
    if (cur == 0 && s.chip < s.minBet) return _warn('최소 베팅 ${fmtCoins(s.minBet)} 이상이어야 합니다');
    final amt = s.chip > remaining ? remaining : s.chip;
    if (amt > s.gold) return _warn('골드가 부족합니다');
    s.betSpot(spotId, amt);
    final from = _center(_chipKeys[s.chip]) ?? _center(_trayKey);
    final to = _center(_spotKey(spotId));
    if (from != null && to != null) _fly(s.chip, from, to);
  }

  void _cancel() {
    final s = widget.service;
    if (!s.canBet || s.myBets.values.every((v) => v <= 0)) return;
    final tray = _center(_trayKey);
    s.myBets.forEach((spotId, total) {
      final from = _center(_spotKeys[spotId]);
      if (from == null || tray == null) return;
      _fly(s.chip, from, tray);
    });
    s.clearBets();
  }

  void _repeat() {
    final s = widget.service;
    if (!s.canBet) return;
    if (s.lastBets.isEmpty) return _warn('반복할 이전 베팅이 없습니다');
    final total = s.lastBets.values.fold<int>(0, (a, b) => a + b);
    if (total > s.gold) return _warn('골드가 부족합니다');
    s.lastBets.forEach((spotId, amt) {
      if (amt <= 0) return;
      s.betSpot(spotId, amt);
      final from = _center(_trayKey);
      final to = _center(_spotKey(spotId));
      if (from != null && to != null) _fly(s.chip, from, to);
    });
  }

  void _warn(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD54F), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
      ]),
      backgroundColor: const Color(0xFF8A1418),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: cGold, width: 1)),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/roulette_felt.png'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Stack(
            key: _stackKey,
            children: [
              ListenableBuilder(
                listenable: s,
                builder: (context, _) => Column(
                  children: [
                    _topBar(s),
                    // top (wheel + history) stays fixed
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                      child: _wheelArea(s),
                    ),
                    // only the betting board fills the middle, scaled to fit (no scroll)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(child: FittedBox(fit: BoxFit.contain, child: _board(s))),
                      ),
                    ),
                    // chip tray + actions stay fixed at the bottom
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Column(
                        children: [
                          _chipTray(s),
                          const SizedBox(height: 8),
                          _actions(s),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final f in _flying)
                AnimatedBuilder(
                  animation: f.ctrl,
                  builder: (_, _) {
                    final t = Curves.easeInOut.transform(f.ctrl.value);
                    final p = Offset.lerp(f.from, f.to, t)!;
                    final lift = -34 * (4 * t * (1 - t));
                    return Positioned(
                      left: p.dx - 16,
                      top: p.dy - 16 + lift,
                      child: SizedBox(width: 32, height: 32, child: Image.asset('assets/images/chip_${f.value}.png')),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- top bar ----
  Widget _topBar(GameService s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: s.leaveRoom, icon: const Icon(Icons.arrow_back, color: cGoldBright), tooltip: '로비'),
              Expanded(
                child: Center(
                  child: goldText(const Text('Roulette',
                      style: TextStyle(
                          fontFamily: 'serif', fontStyle: FontStyle.italic, fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          Row(
            children: [
              Text(s.roomName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 6),
              Text('한도 ${fmtCoins(s.minBet)}~${fmtCoins(s.maxBet)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const Spacer(),
              CoinBar(gold: s.gold, diamond: s.diamond, compact: true, onTapGold: s.devTopup),
            ],
          ),
        ],
      ),
    );
  }

  // ---- history (left, going down) + wheel (right) ----
  Widget _wheelArea(GameService s) {
    // while the ball is still spinning/landing, never reveal the number
    final spinning = s.phase == 'locked' || (s.phase == 'settled' && !_landed);
    final status = s.phase == 'betting' ? '베팅하세요 · ${_secondsLeft}s' : (spinning ? 'NO MORE BETS — 스핀!' : '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _historyColumn(s),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              SizedBox(width: 178, height: 178, child: CustomPaint(painter: _WheelPainter(_ballAngle))),
              const SizedBox(height: 6),
              if (_landed && s.winning != null)
                _resultBanner(s)
              else
                Text(status,
                    style: TextStyle(
                        color: s.phase == 'locked' ? cGoldBright : Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  /// Previous results, newest at the top going down. The just-spun number only
  /// joins the list once the ball has actually landed (result first, then history).
  Widget _historyColumn(GameService s) {
    final full = s.recent;
    final hist = (_landed || full.isEmpty) ? full : full.sublist(0, full.length - 1);
    final show = hist.length > 6 ? hist.sublist(hist.length - 6) : hist;
    final ordered = show.reversed.toList(); // newest first (top)
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          const Text('이전결과', style: TextStyle(color: cGold, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final p in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                width: 34,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rouletteColor(p),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: cGold.withValues(alpha: 0.45)),
                ),
                child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  List<int> _pile(int total) {
    final out = <int>[];
    var rem = total;
    for (final c in const [10000, 1000, 500, 100, 25]) {
      while (rem >= c && out.length < 8) {
        out.add(c);
        rem -= c;
      }
    }
    return out;
  }

  /// A small pile of chip images sitting on a spot, with the total below.
  Widget _spotChips(int total) {
    final pile = _pile(total);
    final show = pile.length > 3 ? pile.sublist(0, 3) : pile;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < show.length; i++)
            Positioned(
              bottom: 6 + i * 3.0,
              child: SizedBox(width: 22, height: 22, child: Image.asset('assets/images/chip_${show[i]}.png')),
            ),
          Positioned(
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
              child: Text(fmtCoins(total), style: const TextStyle(color: cGoldBright, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultBanner(GameService s) {
    final win = s.lastNet > 0;
    final color = win ? const Color(0xFF2E9E5B) : const Color(0xFF8A1418);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cGold),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: rouletteColor(s.winning!), shape: BoxShape.circle, border: Border.all(color: Colors.white70)),
            child: Text(s.winning!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Text(s.lastNet == 0 ? '결과' : (win ? '+${fmtCoins(s.lastNet)}' : fmtCoins(s.lastNet)),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // ---- betting board (classic horizontal layout, fixed size, fit via FittedBox)
  // Top row 3,6,..36 / mid 2,5,..35 / bottom 1,4,..34, with 0/00 on top, 2:1
  // columns on the right, dozens + even-money below.
  Widget _board(GameService s) {
    Widget num(String n) => Expanded(
        child: Padding(padding: const EdgeInsets.all(1.5), child: _numCell(s, 's:$n', n, rouletteColor(n), h: 34)));
    Widget out(String id, String label, {Color? fill, double fs = 11}) => Expanded(
        child: Padding(padding: const EdgeInsets.all(1.5), child: _outsideCell(s, id, label, h: 30, fs: fs, fill: fill)));
    Widget two(int col) => SizedBox(
        width: 34,
        child: Padding(padding: const EdgeInsets.all(1.5), child: _outsideCell(s, 'col:$col', '2:1', h: 34, fs: 9)));
    const rightPad = SizedBox(width: 34);

    return SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 0 / 00 (top)
          Row(children: [num('0'), num('00'), rightPad]),
          // 3 number rows with the 2:1 column bets on the right
          for (var row = 0; row < 3; row++)
            Row(children: [
              for (var c = 0; c < 12; c++) num('${3 * c + (3 - row)}'),
              two(3 - row),
            ]),
          // dozens
          Row(children: [out('dz:1', '1st 12'), out('dz:2', '2nd 12'), out('dz:3', '3rd 12'), rightPad]),
          // even-money
          Row(children: [
            out('low', '1-18'),
            out('even', 'EVEN'),
            out('red', '', fill: rouletteRed),
            out('black', '', fill: rouletteBlack),
            out('odd', 'ODD'),
            out('high', '19-36'),
            rightPad,
          ]),
        ],
      ),
    );
  }

  Widget _numCell(GameService s, String spotId, String label, Color color, {double h = 30}) {
    final mine = s.myBets[spotId] ?? 0;
    final isWinner = _landed && s.winning == label;
    return GestureDetector(
      onTap: s.canBet ? () => _place(spotId) : null,
      child: Container(
        key: _spotKey(spotId),
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: isWinner ? cGoldBright : cGold.withValues(alpha: 0.4), width: isWinner ? 3 : 1),
          boxShadow: isWinner ? [BoxShadow(color: cGoldBright.withValues(alpha: 0.9), blurRadius: 12, spreadRadius: 1)] : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            if (isWinner)
              const Positioned(top: -3, child: Text('●', style: TextStyle(color: cGoldBright, fontSize: 11))),
            if (mine > 0) _spotChips(mine),
          ],
        ),
      ),
    );
  }

  Widget _outsideCell(GameService s, String spotId, String label, {double h = 30, double fs = 12, Color? fill}) {
    final mine = s.myBets[spotId] ?? 0;
    return GestureDetector(
      onTap: s.canBet ? () => _place(spotId) : null,
      child: Container(
        key: _spotKey(spotId),
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? const Color(0xFF0C4D38),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: cGold.withValues(alpha: 0.4)),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (label.isNotEmpty)
              Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fs)),
            if (mine > 0) _spotChips(mine),
          ],
        ),
      ),
    );
  }

  // ---- chip tray (reused styling) ----
  Widget _chipTray(GameService s) {
    return Container(
      key: _trayKey,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6E1F26), Color(0xFF3A0E12)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cGold.withValues(alpha: 0.55), width: 1.3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final c in s.chips) _chip(s, c)]),
          const SizedBox(height: 8),
          Text('칩을 선택하고 베팅 칸을 탭하세요', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
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

  Widget _actions(GameService s) {
    final hasBets = s.myBets.values.any((v) => v > 0);
    final canCancel = s.canBet && hasBets;
    final canRepeat = s.canBet && !hasBets && s.lastBets.isNotEmpty;
    final lastTotal = s.lastBets.values.fold<int>(0, (a, b) => a + b);
    return Row(
      children: [
        Expanded(child: _actionBtn('취소', Icons.undo_rounded, canCancel, _cancel, const Color(0xFF7A1B22))),
        const SizedBox(width: 10),
        Expanded(child: _actionBtn(lastTotal > 0 ? '반복  ${fmtCoins(lastTotal)}' : '반복', Icons.repeat_rounded, canRepeat, _repeat, const Color(0xFF1B5E45))),
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
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, Color.lerp(color, Colors.black, 0.4)!]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cGold.withValues(alpha: 0.55), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cGoldBright, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wheel: a static colored ring of the 38 American pockets with a white ball
/// resting at [ballAngle] (radians, clockwise from the top).
class _WheelPainter extends CustomPainter {
  final double ballAngle;
  _WheelPainter(this.ballAngle);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rOuter = size.width / 2;
    final rInner = rOuter * 0.62;
    final n = _americanOrder.length;
    final sector = 2 * pi / n;
    // top = -pi/2 in canvas angle; pockets laid clockwise from there.
    const top = -pi / 2;

    for (var i = 0; i < n; i++) {
      final a0 = top + i * sector - sector / 2;
      final paint = Paint()..style = PaintingStyle.fill..color = rouletteColor(_americanOrder[i]);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: rOuter), a0, sector, false)
        ..close();
      canvas.drawPath(path, paint);
      // number text
      final mid = top + i * sector;
      final tp = TextPainter(
        text: TextSpan(text: _americanOrder[i], style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final tr = (rOuter + rInner) / 2;
      final pos = Offset(c.dx + tr * cos(mid) - tp.width / 2, c.dy + tr * sin(mid) - tp.height / 2);
      tp.paint(canvas, pos);
    }

    // inner hub
    canvas.drawCircle(c, rInner, Paint()..color = const Color(0xFF20140A));
    canvas.drawCircle(c, rInner, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = cGold);
    canvas.drawCircle(c, rOuter, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = cGold);

    // ball on the ring
    final ba = top + ballAngle;
    final br = (rOuter + rInner) / 2 + 1;
    final ball = Offset(c.dx + br * cos(ba), c.dy + br * sin(ba));
    canvas.drawCircle(ball, 5, Paint()..color = Colors.white);
    canvas.drawCircle(ball, 5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.ballAngle != ballAngle;
}
