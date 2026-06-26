import 'package:flutter/material.dart';

import 'game_service.dart';
import 'models.dart';
import 'widgets.dart';

class LobbyScreen extends StatelessWidget {
  final GameService service;
  const LobbyScreen(this.service, {super.key});

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name.isEmpty ? '...' : s.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Text('게임 로비', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${s.balance}',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold, color: goldColor)),
                      const Text('보유 코인', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: s.logout,
                    icon: const Icon(Icons.logout, size: 20, color: Colors.white70),
                    tooltip: '로그아웃',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('게임 선택',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                  children: s.games.map((g) => _gameCard(g)).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameCard(GameInfo g) {
    final live = g.isLive;
    final emoji = g.id == 'baccarat'
        ? '🃏'
        : g.id == 'slots'
            ? '🎰'
            : g.id == 'blackjack'
                ? '♠️'
                : '🎲';
    return Opacity(
      opacity: live ? 1 : 0.45,
      child: GestureDetector(
        onTap: live ? () => service.selectGame(g.id) : null,
        child: Container(
          decoration: BoxDecoration(
            color: feltLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: live ? goldColor.withValues(alpha: 0.5) : Colors.white12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(g.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(live ? '입장하기' : '준비중',
                  style: TextStyle(
                      fontSize: 12, color: live ? goldColor : Colors.white38)),
            ],
          ),
        ),
      ),
    );
  }
}
