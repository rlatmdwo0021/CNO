// Plain data models parsed from the server's JSON protocol.

class GameInfo {
  final String id;
  final String name;
  final String status; // live | soon
  GameInfo(this.id, this.name, this.status);
  factory GameInfo.fromJson(Map<String, dynamic> j) =>
      GameInfo(j['id'] as String, j['name'] as String, j['status'] as String);
  bool get isLive => status == 'live';
}

class RoomInfo {
  final String id;
  final String name;
  final int minBet;
  final int maxBet;
  final int players;
  final String phase;
  RoomInfo(this.id, this.name, this.minBet, this.maxBet, this.players, this.phase);
  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
        j['id'] as String,
        j['name'] as String,
        j['minBet'] as int,
        j['maxBet'] as int,
        j['players'] as int,
        j['phase'] as String,
      );
}

class CardView {
  final String rank;
  final String suit; // S H D C
  CardView(this.rank, this.suit);
  factory CardView.fromJson(Map<String, dynamic> j) =>
      CardView(j['rank'] as String, j['suit'] as String);

  bool get isRed => suit == 'H' || suit == 'D';
  String get suitSymbol => const {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'}[suit] ?? '?';
}

class HandView {
  final List<CardView> cards;
  final int value;
  HandView(this.cards, this.value);
  factory HandView.fromJson(Map<String, dynamic> j) => HandView(
        (j['cards'] as List).map((c) => CardView.fromJson(c as Map<String, dynamic>)).toList(),
        j['value'] as int,
      );
}

class SettledBet {
  final String playerId;
  final String betType;
  final int amount;
  final bool? won; // null = push
  final int net;
  SettledBet(this.playerId, this.betType, this.amount, this.won, this.net);
  factory SettledBet.fromJson(Map<String, dynamic> j) => SettledBet(
        j['playerId'] as String,
        j['betType'] as String,
        j['amount'] as int,
        j['won'] as bool?,
        j['net'] as int,
      );
}

/// One cell of any road, normalised to row/col + a small payload.
class RoadCell {
  final int row;
  final int col;
  final String outcome; // player | banker | tie  (or color for derived)
  final int ties;
  final bool playerPair;
  final bool bankerPair;
  RoadCell(this.row, this.col, this.outcome,
      {this.ties = 0, this.playerPair = false, this.bankerPair = false});
}

class Roadmap {
  final List<RoadCell> bead;
  final List<RoadCell> big;
  final List<RoadCell> bigEye; // outcome holds 'red' | 'blue'
  final List<RoadCell> small;
  final List<RoadCell> cockroach;
  Roadmap(this.bead, this.big, this.bigEye, this.small, this.cockroach);

  static Roadmap empty() => Roadmap([], [], [], [], []);

  factory Roadmap.fromJson(Map<String, dynamic> j) {
    List<RoadCell> bead(List cells) => cells
        .map((c) => RoadCell(c['row'], c['col'], c['outcome'],
            playerPair: c['playerPair'] ?? false, bankerPair: c['bankerPair'] ?? false))
        .toList();
    List<RoadCell> big(List cells) => cells
        .map((c) => RoadCell(c['row'], c['col'], c['outcome'],
            ties: c['ties'] ?? 0,
            playerPair: c['playerPair'] ?? false,
            bankerPair: c['bankerPair'] ?? false))
        .toList();
    List<RoadCell> derived(Map d) =>
        (d['cells'] as List).map((c) => RoadCell(c['row'], c['col'], c['color'])).toList();

    return Roadmap(
      bead((j['bead']['cells'] as List)),
      big((j['big']['cells'] as List)),
      derived(j['bigEye']),
      derived(j['small']),
      derived(j['cockroach']),
    );
  }
}
