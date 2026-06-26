import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_screen.dart';
import 'game_service.dart';
import 'lobby_screen.dart';
import 'roulette_screen.dart';
import 'table_screen.dart';
import 'widgets.dart';

void main() {
  final service = GameService();
  service.start();
  runApp(BaccaratApp(service));
}

class BaccaratApp extends StatelessWidget {
  final GameService service;
  const BaccaratApp(this.service, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baccarat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: feltColor,
        fontFamily: 'Roboto',
      ),
      home: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          // Hardware back: table -> lobby, lobby -> login. Only the login
          // screen lets the system actually exit the app (never just minimize).
          final canExit = !service.loggedIn;
          return PopScope(
            canPop: canExit,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              if (service.view == AppView.table) {
                if (await _confirm(context, '로비로 이동', '로비로 가시겠습니까?', '이동')) {
                  service.leaveRoom();
                }
              } else if (service.loggedIn) {
                if (await _confirm(context, '종료', '앱을 종료하시겠습니까?', '종료')) {
                  SystemNavigator.pop();
                }
              }
            },
            child: _screen(service),
          );
        },
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String message, String confirmText) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: feltLight,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText, style: const TextStyle(color: goldColor)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _screen(GameService service) {
    if (!service.loggedIn) return AuthScreen(service);
    switch (service.view) {
      case AppView.lobby:
        return LobbyScreen(service);
      case AppView.table:
        return service.roomGameId == 'roulette' ? RouletteScreen(service) : TableScreen(service);
    }
  }
}
