import 'dart:async';
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

class _TableScreenState extends State<TableScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drive the betting-window countdown.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int get _secondsLeft {
    final s = widget.service;
    if (s.phase != 'betting') return 0;
    final ms = s.endsAt - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(s),
                  const SizedBox(height: 12),
                  _phaseBanner(s),
                  const SizedBox(height: 12),
                  _hands(s),
                  const SizedBox(height: 16),
                  _controls(s),
                  const SizedBox(height: 16),
                  _roads(s),
                  const SizedBox(height: 12),
                  _feed(s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(GameService s) {
    final connText = s.conn == Conn.online
        ? '● 온라인'
        : (s.conn == Conn.connecting ? '○ 연결 중' : '○ 끊김');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🃏 Baccarat',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${s.name.isEmpty ? '...' : s.name} · $connText',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${s.balance}',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold, color: goldColor)),
            TextButton(
              onPressed: s.newAccount,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 28)),
              child: const Text('새 계정', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _phaseBanner(GameService s) {
    String text;
    if (s.phase == 'betting') {
      text = '베팅하세요 — $_secondsLeft초';
    } else if (s.phase == 'locked') {
      text = '베팅 마감 — 딜링 중…';
    } else if (s.phase == 'settled' && s.outcome != null) {
      text = s.outcome == 'tie' ? '타이!' : '${s.outcome == 'player' ? 'PLAYER' : 'BANKER'} 승';
    } else {
      text = '대기 중…';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: feltLight, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (s.roundId != null)
            Text(s.roundId!, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _hands(GameService s) {
    return Row(
      children: [
        Expanded(child: _handPanel('PLAYER', s.player, s.outcome == 'player', playerColor)),
        const SizedBox(width: 12),
        Expanded(child: _handPanel('BANKER', s.banker, s.outcome == 'banker', bankerColor)),
      ],
    );
  }

  Widget _handPanel(String title, HandView? hand, bool isWinner, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: feltLight,
        borderRadius: BorderRadius.circular(10),
        border: isWinner ? Border.all(color: goldColor, width: 2) : null,
      ),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: hand == null
                ? const Center(child: Text('—', style: TextStyle(color: Colors.white30)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: hand.cards.map((c) => PlayingCardWidget(c)).toList(),
                  ),
          ),
          const SizedBox(height: 6),
          Text(hand == null ? '' : '${hand.value}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _controls(GameService s) {
    return Column(
      children: [
        Row(
          children: s.chips
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _chip(s, c),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _market(s, 'player', 'PLAYER\n1:1', playerColor)),
            const SizedBox(width: 8),
            Expanded(child: _market(s, 'tie', 'TIE\n8:1', tieColor)),
            const SizedBox(width: 8),
            Expanded(child: _market(s, 'banker', 'BANKER\n0.95:1', bankerColor)),
          ],
        ),
      ],
    );
  }

  Widget _chip(GameService s, int value) {
    final active = s.chip == value;
    return GestureDetector(
      onTap: () => s.setChip(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? goldColor : feltLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? goldColor : Colors.white24),
        ),
        alignment: Alignment.center,
        child: Text('$value',
            style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _market(GameService s, String type, String label, Color color) {
    final enabled = s.canBet;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: ElevatedButton(
        onPressed: enabled ? () => s.bet(type) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _roadCard(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: feltLight, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 10, color: Colors.white70, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _roads(GameService s) {
    final r = s.roadmap;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _roadCard('Bead Plate', RoadBoard(cells: r.bead, cell: 22, builder: beadCell))),
            const SizedBox(width: 8),
            Expanded(child: _roadCard('Big Road', RoadBoard(cells: r.big, cell: 22, builder: bigCell))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _roadCard('Big Eye',
                    RoadBoard(cells: r.bigEye, cell: 14, builder: derivedCell(DerivedShape.disc)))),
            const SizedBox(width: 8),
            Expanded(
                child: _roadCard('Small',
                    RoadBoard(cells: r.small, cell: 14, builder: derivedCell(DerivedShape.ring)))),
            const SizedBox(width: 8),
            Expanded(
                child: _roadCard('Cockroach',
                    RoadBoard(cells: r.cockroach, cell: 14, builder: derivedCell(DerivedShape.slash)))),
          ],
        ),
      ],
    );
  }

  Widget _feed(GameService s) {
    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: feltLight, borderRadius: BorderRadius.circular(10)),
      child: ListView(
        children: s.feed
            .map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(line, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ))
            .toList(),
      ),
    );
  }
}
