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
    final n = widget.service.games.isEmpty ? 1 : widget.service.games.length;
    _tabs = TabController(length: n, vsync: this);
    // Live room status: refresh now and every few seconds while in the lobby.
    widget.service.refreshRooms();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => widget.service.refreshRooms());
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(s),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              indicatorColor: goldColor,
              labelColor: goldColor,
              unselectedLabelColor: Colors.white60,
              tabAlignment: TabAlignment.start,
              tabs: s.games.map((g) => Tab(text: g.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: s.games.map((g) => _gameTab(s, g)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(GameService s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(s.name.isEmpty ? '...' : s.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                GradeBadge(s.grade),
              ],
            ),
          ),
          CoinBar(gold: s.gold, diamond: s.diamond),
          IconButton(
            onPressed: s.logout,
            icon: const Icon(Icons.logout, size: 20, color: Colors.white70),
            tooltip: '로그아웃',
          ),
        ],
      ),
    );
  }

  Widget _gameTab(GameService s, GameInfo g) {
    if (g.id == 'baccarat') return _baccaratRooms(s);
    if (g.id == 'slots') return _slotsPlaceholder();
    return _comingSoon('${g.name}은 곧 추가됩니다');
  }

  Widget _baccaratRooms(GameService s) {
    if (s.rooms.isEmpty) {
      return const Center(child: Text('방 불러오는 중…', style: TextStyle(color: Colors.white54)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: s.rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _roomTile(s, s.rooms[i]),
    );
  }

  Widget _roomTile(GameService s, RoomInfo r) {
    final (phaseText, phaseColor) = switch (r.phase) {
      'betting' => ('베팅중', tieColor),
      'locked' => ('딜링중', goldColor),
      'settled' => ('정산', Colors.white70),
      _ => ('대기', Colors.white54),
    };
    return GestureDetector(
      onTap: () => s.joinRoom(r.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: feltLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: goldColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(r.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Text('한도 ${fmtCoins(r.minBet)}~${fmtCoins(r.maxBet)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                const Spacer(),
                const Icon(Icons.person, size: 14, color: Colors.white54),
                const SizedBox(width: 2),
                Text('${r.players}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration:
                      BoxDecoration(color: feltColor, borderRadius: BorderRadius.circular(20)),
                  child: Text(phaseText, style: TextStyle(fontSize: 11, color: phaseColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Recent results at a glance (mini bead plate).
            MiniBead(r.recent),
          ],
        ),
      ),
    );
  }

  Widget _slotsPlaceholder() {
    const machines = ['럭키 세븐', '후르츠 파티', '메가 휠', '골든 드래곤'];
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1,
      children: machines
          .map((m) => Opacity(
                opacity: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    color: feltLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🎰', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(m, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      const Text('준비중', style: TextStyle(fontSize: 11, color: Colors.white38)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _comingSoon(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎡', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
