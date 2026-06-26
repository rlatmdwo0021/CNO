import 'dart:async';
import 'package:flutter/material.dart';

import 'game_service.dart';
import 'models.dart';
import 'widgets.dart';

class LobbyScreen extends StatefulWidget {
  final GameService service;
  const LobbyScreen(this.service, {super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with SingleTickerProviderStateMixin {
  TabController? _tabs;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final games = widget.service.games;
    _tabs = TabController(length: games.isEmpty ? 1 : games.length, vsync: this);
    _tabs!.addListener(() {
      if (!_tabs!.indexIsChanging) _refreshCurrentTab();
    });
    _refreshCurrentTab();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refreshCurrentTab());
  }

  void _refreshCurrentTab() {
    final games = widget.service.games;
    if (games.isEmpty || _tabs == null) return;
    final g = games[_tabs!.index.clamp(0, games.length - 1)];
    if (g.isLive) widget.service.refreshRooms(g.id);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    if (s.games.isEmpty || _tabs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: cGold)));
    }
    return Scaffold(
      body: Container(
        decoration: casinoBg,
        child: SafeArea(
          child: Column(
            children: [
              _topBar(s),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                indicatorColor: cGold,
                indicatorWeight: 3,
                labelColor: cGold,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1),
                tabAlignment: TabAlignment.start,
                tabs: s.games.map((g) => Tab(text: g.name)).toList(),
              ),
              const Divider(height: 1, color: Color(0x33D4AF37)),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: s.games.map((g) => _gameTab(s, g)).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(GameService s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _logoutConfirm(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cPanel,
                border: Border.all(color: cGold, width: 2),
              ),
              child: const Icon(Icons.person, color: cGoldBright, size: 24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PLAYER',
                    style: TextStyle(fontSize: 9, color: cGold, letterSpacing: 1.5)),
                Text(s.name.isEmpty ? '...' : s.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(s.grade.toUpperCase(),
                    style: const TextStyle(fontSize: 9, color: cGoldBright, letterSpacing: 1)),
              ],
            ),
          ),
          _coinPill(),
        ],
      ),
    );
  }

  Widget _coinPill() {
    final s = widget.service;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TEST ONLY — tap gold to top up.
          GestureDetector(
            onTap: s.devTopup,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(fmtCoins(s.gold),
                    style: const TextStyle(color: cGoldBright, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 4),
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
          ),
          const SizedBox(width: 12),
          const Text('💎', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(fmtCoins(s.diamond),
              style: const TextStyle(color: Color(0xFF7FD4E8), fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _gameTab(GameService s, GameInfo g) {
    if (g.isLive) {
      // rooms are loaded per selected tab; only show them once they match this game
      if (s.roomsGameId != g.id || s.rooms.isEmpty) {
        return const Center(child: Text('방 불러오는 중…', style: TextStyle(color: Colors.white54)));
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [for (final r in s.rooms) _roomCard(s, r)],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(g.id == 'slots' ? '🎰' : '🎡', style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text('${g.name} 준비중', style: const TextStyle(color: Colors.white54, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _roomCard(GameService s, RoomInfo r) {
    final isRoulette = r.gameId == 'roulette';
    final (phaseText, phaseColor) = switch (r.phase) {
      'betting' => ('BETTING', cPillRed),
      'locked' => (isRoulette ? 'SPINNING' : 'DEALING', cGold),
      'settled' => ('RESULT', Colors.white54),
      _ => ('WAIT', Colors.white38),
    };
    final outcomes = r.roadmap.bead.map((c) => c.outcome).toList();
    final isVip = r.id == 'vip' || r.id == 'ro-vip';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cGold, width: 1.4),
        boxShadow: [BoxShadow(color: cGold.withValues(alpha: 0.18), blurRadius: 14, spreadRadius: -4)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => s.joinRoom(r.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: goldText(Text(
                  isVip ? '${r.name} SALON  ♛' : '${r.name} ROOM',
                  style: const TextStyle(
                      fontFamily: 'serif', fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
                )),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('베팅 ${fmtCoins(r.minBet)} ~ ${fmtCoins(r.maxBet)}',
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const Spacer(),
                  const Icon(Icons.person, size: 13, color: Colors.white54),
                  const SizedBox(width: 2),
                  Text('${r.players}',
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: phaseColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: phaseColor),
                    ),
                    child: Text(phaseText,
                        style: TextStyle(fontSize: 10, color: phaseColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isRoulette) ...[
                const Text('최근 결과',
                    style: TextStyle(fontSize: 12, color: cGold, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                RouletteRecentStrip(r.recent ?? const [], size: 24),
              ] else ...[
                PbtGrid(outcomes, cell: 12),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Win Tallies:',
                        style: TextStyle(fontSize: 12, color: cGold, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    _tally('P', r.counts.player, playerColor),
                    _tally('B', r.counts.banker, bankerColor),
                    _tally('T', r.counts.tie, tieColor),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tally(String letter, int n, Color color) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Text('$letter: $n',
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
      );

  Future<void> _logoutConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cPanel,
        title: const Text('로그아웃', style: TextStyle(color: Colors.white)),
        content: const Text('로그아웃 하시겠습니까?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('로그아웃', style: TextStyle(color: cGold))),
        ],
      ),
    );
    if (ok == true) widget.service.logout();
  }
}
