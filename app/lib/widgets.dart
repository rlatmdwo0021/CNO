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
      builder: (_, t, child) => Transform.scale(scale: t, child: child),
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

/// Generic 6-row road board: lays sparse cells into columns.
class RoadBoard extends StatelessWidget {
  final List<RoadCell> cells;
  final double cell;
  final Widget Function(RoadCell) builder;
  const RoadBoard({super.key, required this.cells, required this.cell, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return SizedBox(height: cell * 6);
    final maxCol = cells.map((c) => c.col).reduce(max);
    final grid = {for (final c in cells) '${c.col},${c.row}': c};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // keep the newest columns in view
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int col = 0; col <= maxCol; col++)
            Column(
              children: [
                for (int row = 0; row < 6; row++)
                  SizedBox(
                    width: cell,
                    height: cell,
                    child: grid.containsKey('$col,$row')
                        ? Padding(padding: const EdgeInsets.all(1), child: builder(grid['$col,$row']!))
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

Widget beadCell(RoadCell c) => Container(
      decoration: BoxDecoration(color: outcomeColor(c.outcome), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        c.outcome == 'player' ? 'P' : (c.outcome == 'banker' ? 'B' : 'T'),
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );

Widget bigCell(RoadCell c) => Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: outcomeColor(c.outcome), width: 2.5),
          ),
          alignment: Alignment.center,
          child: c.ties > 0
              ? Text('${c.ties}',
                  style: const TextStyle(color: tieColor, fontSize: 10, fontWeight: FontWeight.bold))
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
              child: Container(width: 14, height: 3, color: color),
            ),
          );
      }
    };
