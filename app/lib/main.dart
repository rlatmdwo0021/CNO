import 'package:flutter/material.dart';

import 'game_service.dart';
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
      home: TableScreen(service),
    );
  }
}
