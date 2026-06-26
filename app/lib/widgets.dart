import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';

const playerColor = Color(0xFF3B82F6);
const bankerColor = Color(0xFFEF4444);
const tieColor = Color(0xFF22C55E);
const feltColor = Color(0xFF0B3D2E);
const feltLight = Color(0xFF0E5440);
const goldColor = Color(0xFFFFD76B);

Color outcomeColor(String o) =>
    o == 'player' ? playerColor : (o == 'banker' ? bankerColor : tieColor);

// --- premium casino palette (from the mockups) ---
const cGold = Color(0xFFD4AF37);
const cGoldBright = Color(0xFFEBCB6B);
const cBgTop = Color(0xFF134736);
const cBgBottom = Color(0xFF06190F);
const cPanel = Color(0xFF0E4231);
const cGridBg = Color(0xFF0A3527);
const cGridLine = Color(0xFF1A4D3B);
const cZoneBlue = Color(0xFF2E6DA4);
const cZoneRed = Color(0xFFA8403C);
const cPillRed = Color(0xFFC23B30);

const casinoBg = BoxDecoration(
  image: DecorationImage(
    image: AssetImage('assets/images/bg_felt.jpg'),
    fit: BoxFit.cover,
  ),
);

ShaderMask goldText(Widget child) => ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFCEFB6), cGold, Color(0xFFB07E1B)],
      ).createShader(r),
      child: child,
    );

/// Compact P/B/T results grid (one column per round) for lobby room cards.
class PbtGrid extends StatelessWidget {
  final List<String> outcomes; // chronological
  final double cell;
  const PbtGrid(this.outcomes, {super.key, this.cell = 13});

  @override
  Widget build(BuildContext context) {
    const rows = ['player', 'banker', 'tie'];
    const labels = ['P', 'B', 'T'];
    final colors = [playerColor, bankerColor, tieColor];

    Widget gridCell(int rowIdx, String? o) => Container(
          width: cell,
          height: cell,
          decoration: BoxDecoration(border: Border.all(color: cGridLine, width: 0.5)),
          child: o != null && rows[rowIdx] == o
              ? Center(
                  child: Container(
                    width: cell * 0.62,
                    height: cell * 0.62,
                    decoration: BoxDecoration(color: colors[rowIdx], shape: BoxShape.circle),
                  ),
                )
              : null,
        );

    return Container(
      decoration: BoxDecoration(
        color: cGridBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cGold.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(
                  width: cell,
                  height: cell,
                  child: Center(
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: cell * 0.62,
                            color: colors[i],
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: false,
              child: Row(
                children: [
                  for (final o in outcomes)
                    Column(children: [for (var i = 0; i < 3; i++) gridCell(i, o)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Format an integer with thousands separators (e.g. 12000 -> "12,000").
String fmtCoins(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return (n < 0 ? '-' : '') + buf.toString();
}

/// Free (gold) + paid (diamond) coin balances, side by side.
class CoinBar extends StatelessWidget {
  final int gold;
  final int diamond;
  final bool compact;
  final VoidCallback? onTapGold; // TEST ONLY — tap the gold balance to top up
  const CoinBar(
      {super.key, required this.gold, required this.diamond, this.compact = false, this.onTapGold});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 13.0 : 15.0;
    Widget coin(String emoji, int v, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: size)),
            const SizedBox(width: 3),
            Text(fmtCoins(v),
                style: TextStyle(fontSize: size, fontWeight: FontWeight.bold, color: c)),
          ],
        );
    Widget goldCoin = coin('🪙', gold, goldColor);
    if (onTapGold != null) {
      // TEST ONLY — tappable gold with a small "+" badge.
      goldCoin = GestureDetector(
        onTap: onTapGold,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            goldCoin,
            const SizedBox(width: 3),
            Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFF2E9E5B), shape: BoxShape.circle),
              child: const Text('＋',
                  style: TextStyle(
                      fontSize: 11, height: 1, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        goldCoin,
        const SizedBox(width: 12),
        coin('💎', diamond, const Color(0xFF6BD4F0)),
      ],
    );
  }
}

// ---- roulette helpers (shared by lobby + table) ----
const Set<int> rouletteRedNumbers = {
  1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
};
const Color rouletteGreen = Color(0xFF1B8A4C);
const Color rouletteRed = Color(0xFFC62828);
const Color rouletteBlack = Color(0xFF1B1B1B);

Color rouletteColor(String pocket) {
  if (pocket == '0' || pocket == '00') return rouletteGreen;
  return rouletteRedNumbers.contains(int.tryParse(pocket) ?? -1) ? rouletteRed : rouletteBlack;
}

/// Horizontal strip of recent winning pockets (newest on the right).
class RouletteRecentStrip extends StatelessWidget {
  final List<String> recent; // oldest first
  final double size;
  const RouletteRecentStrip(this.recent, {super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return SizedBox(
        height: size,
        child: const Center(child: Text('아직 결과 없음', style: TextStyle(fontSize: 11, color: Colors.white30))),
      );
    }
    final show = recent.length > 18 ? recent.sublist(recent.length - 18) : recent;
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true, // newest first on the right side
        itemCount: show.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final p = show[show.length - 1 - i];
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rouletteColor(p),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: cGold.withValues(alpha: 0.45)),
            ),
            child: Text(p,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }
}

/// Compact bead-plate preview of recent outcomes (6 rows, column-major),
/// for showing a room's current game at a glance in the lobby.
class MiniBead extends StatelessWidget {
  final List<String> outcomes; // player | banker | tie, oldest first
  final double dot;
  const MiniBead(this.outcomes, {super.key, this.dot = 9});

  @override
  Widget build(BuildContext context) {
    if (outcomes.isEmpty) {
      return SizedBox(
        height: dot * 6 + 10,
        child: const Center(
            child: Text('아직 결과 없음', style: TextStyle(fontSize: 11, color: Colors.white30))),
      );
    }
    final cols = (outcomes.length / 6).ceil();
    return SizedBox(
      height: dot * 6 + 4,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: false, // newest columns visible on the right
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < cols; c++)
              Column(
                children: [
                  for (var r = 0; r < 6; r++) _cell(c * 6 + r),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int i) {
    if (i >= outcomes.length) return SizedBox(width: dot + 2, height: dot + 2);
    final o = outcomes[i];
    final letter = o == 'player' ? 'P' : (o == 'banker' ? 'B' : 'T');
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(color: outcomeColor(o), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(letter,
            style: TextStyle(fontSize: dot * 0.62, color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// Small player grade badge (placeholder tier for now).
class GradeBadge extends StatelessWidget {
  final String grade;
  const GradeBadge(this.grade, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF7A5230),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('🥉 $grade',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}

/// A single playing card with a gentle pop-in animation.
class PlayingCardWidget extends StatelessWidget {
  final CardView card;
  const PlayingCardWidget(this.card, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = card.isRed ? bankerColor : const Color(0xFF111111);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Transform.scale(scale: t < 0.05 ? 0.05 : t, child: child),
      child: Container(
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
      ),
    );
  }
}

const roadGridLine = Color(0xFFAEB6BD); // visible grid lines on the white scoreboard

/// A 6-row road drawn as a real-casino white scoreboard: a light grid with
/// the colored marks placed in their cells. Bounded height + horizontal scroll
/// so it can never overflow. `minCols` keeps an empty board showing a grid.
class RoadBoard extends StatefulWidget {
  final List<RoadCell> cells;
  final double cell;
  final Widget Function(RoadCell) builder;
  final int minCols;
  const RoadBoard({
    super.key,
    required this.cells,
    required this.cell,
    required this.builder,
    this.minCols = 6,
  });

  @override
  State<RoadBoard> createState() => _RoadBoardState();
}

class _RoadBoardState extends State<RoadBoard> {
  static const int rows = 6;
  final ScrollController _ctrl = ScrollController();
  int _lastCount = -1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cells = widget.cells;
    final cell = widget.cell;
    // When a new result lands, jump to the newest (rightmost) column. Only on
    // count change, so the user can freely scroll back to older results.
    if (cells.length != _lastCount) {
      _lastCount = cells.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ctrl.hasClients) _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
      });
    }
    final maxCol = cells.isEmpty ? -1 : cells.map((c) => c.col).reduce(max);
    final cols = max(widget.minCols, maxCol + 1);
    final grid = {for (final c in cells) '${c.col},${c.row}': c};
    return SizedBox(
      height: cell * rows,
      child: SingleChildScrollView(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var col = 0; col < cols; col++)
              Column(
                children: [
                  for (var row = 0; row < rows; row++)
                    Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        border: Border.all(color: roadGridLine, width: 0.7),
                      ),
                      padding: const EdgeInsets.all(1.5),
                      child: grid['$col,$row'] != null ? widget.builder(grid['$col,$row']!) : null,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The full white casino scoreboard (Big Road, Bead Plate, and optionally the
/// three derived roads). Reused big on the table and small in the lobby tiles.
class Scoreboard extends StatelessWidget {
  final Roadmap roadmap;
  final double cell;
  final double derivedSize;
  final bool showDerived;
  final bool showLabels;
  const Scoreboard(
    this.roadmap, {
    super.key,
    this.cell = 20,
    this.derivedSize = 12,
    this.showDerived = true,
    this.showLabels = true,
  });

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(
        builder: (context, cons) {
          // Fill the available width with grid columns (more data just scrolls).
          final mainCols = max(1, (cons.maxWidth / cell).floor());
          final thirdCols = max(1, (((cons.maxWidth - 12) / 3) / derivedSize).floor());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLabels) _label('빅로드 (Big Road)'),
              RoadBoard(cells: roadmap.big, cell: cell, minCols: mainCols, builder: bigCell),
              if (showLabels) _label('비드 플레이트 (Bead Plate)'),
              RoadBoard(cells: roadmap.bead, cell: cell, minCols: mainCols, builder: beadCell),
              if (showDerived) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _derived('빅아이', roadmap.bigEye, DerivedShape.disc, thirdCols)),
                    const SizedBox(width: 6),
                    Expanded(child: _derived('스몰', roadmap.small, DerivedShape.ring, thirdCols)),
                    const SizedBox(width: 6),
                    Expanded(child: _derived('콕로치', roadmap.cockroach, DerivedShape.slash, thirdCols)),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _derived(String label, List<RoadCell> cells, DerivedShape shape, int cols) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabels) _label(label),
          RoadBoard(cells: cells, cell: derivedSize, minCols: cols, builder: derivedCell(shape)),
        ],
      );
}

Widget beadCell(RoadCell c) => Container(
      decoration: BoxDecoration(color: outcomeColor(c.outcome), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        c.outcome == 'player' ? 'P' : (c.outcome == 'banker' ? 'B' : 'T'),
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );

Widget bigCell(RoadCell c) => Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: outcomeColor(c.outcome), width: 2),
          ),
          alignment: Alignment.center,
          child: c.ties > 0
              ? Text('${c.ties}',
                  style: const TextStyle(color: tieColor, fontSize: 8, fontWeight: FontWeight.bold))
              : null,
        ),
        if (c.playerPair)
          const Positioned(
              left: 0, bottom: 0, child: _Dot(playerColor)),
        if (c.bankerPair)
          const Positioned(right: 0, top: 0, child: _Dot(bankerColor)),
      ],
    );

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) =>
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

enum DerivedShape { disc, ring, slash }

Widget Function(RoadCell) derivedCell(DerivedShape shape) => (c) {
      final color = c.outcome == 'red' ? bankerColor : playerColor;
      switch (shape) {
        case DerivedShape.disc:
          return Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle));
        case DerivedShape.ring:
          return Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle, border: Border.all(color: color, width: 2)));
        case DerivedShape.slash:
          return Center(
            child: Transform.rotate(
              angle: -pi / 4,
              child: Container(width: 8, height: 2, color: color),
            ),
          );
      }
    };
