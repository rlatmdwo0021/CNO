import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'game_service.dart';
import 'lobby_screen.dart';
import 'room_list_screen.dart';
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
          if (!service.loggedIn) return AuthScreen(service);
          switch (service.view) {
            case AppView.lobby:
              return LobbyScreen(service);
            case AppView.rooms:
              return RoomListScreen(service);
            case AppView.table:
              return TableScreen(service);
          }
        },
      ),
    );
  }
}
