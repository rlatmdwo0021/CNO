import 'package:flutter/material.dart';

import 'game_service.dart';
import 'models.dart';
import 'widgets.dart';

class RoomListScreen extends StatelessWidget {
  final GameService service;
  const RoomListScreen(this.service, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = service;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: s.backToLobby,
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    tooltip: '뒤로',
                  ),
                  const Expanded(
                    child: Text('바카라 — 방 선택',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Text('${s.balance}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: goldColor)),
                  IconButton(
                    onPressed: s.refreshRooms,
                    icon: const Icon(Icons.refresh, size: 20, color: Colors.white70),
                    tooltip: '새로고침',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: s.rooms.isEmpty
                    ? const Center(
                        child: Text('방 불러오는 중…', style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        itemCount: s.rooms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _roomTile(s.rooms[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomTile(RoomInfo r) {
    final phaseText = r.phase == 'betting'
        ? '베팅중'
        : r.phase == 'locked'
            ? '딜링중'
            : r.phase == 'settled'
                ? '정산'
                : '대기';
    return GestureDetector(
      onTap: () => service.joinRoom(r.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: feltLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: goldColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('한도 ${r.minBet} ~ ${r.maxBet}',
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.white54),
                    const SizedBox(width: 2),
                    Text('${r.players}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: feltColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(phaseText, style: const TextStyle(fontSize: 11, color: tieColor)),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
