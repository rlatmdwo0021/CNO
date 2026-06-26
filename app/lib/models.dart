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

class RoomCounts {
  final int player;
  final int banker;
  final int tie;
  RoomCounts(this.player, this.banker, this.tie);
  factory RoomCounts.fromJson(Map<String, dynamic> j) =>
      RoomCounts(j['player'] ?? 0, j['banker'] ?? 0, j['tie'] ?? 0);
}

class RoomLastResult {
  final String outcome;
  final int playerValue;
  final int bankerValue;
  RoomLastResult(this.outcome, this.playerValue, this.bankerValue);
  factory RoomLastResult.fromJson(Map<String, dynamic> j) =>
      RoomLastResult(j['outcome'] as String, j['playerValue'] as int, j['bankerValue'] as int);
}

class RoomInfo {
  final String id;
  final String name;
  final String gameId;
  final int minBet;
  final int maxBet;
  final int players;
  final String phase;
  final RoomCounts counts;
  final RoomLastResult? lastResult;
  final Roadmap roadmap;
  final List<String>? recent; // roulette recent winning pockets
  RoomInfo(this.id, this.name, this.gameId, this.minBet, this.maxBet, this.players, this.phase,
      this.counts, this.lastResult, this.roadmap, this.recent);
  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
        j['id'] as String,
        j['name'] as String,
        (j['gameId'] ?? 'baccarat') as String,
        j['minBet'] as int,
        j['maxBet'] as int,
        j['players'] as int,
        j['phase'] as String,
        RoomCounts.fromJson((j['counts'] ?? {}) as Map<String, dynamic>),
        j['lastResult'] == null
            ? null
            : RoomLastResult.fromJson(j['lastResult'] as Map<String, dynamic>),
        j['roadmap'] == null
            ? Roadmap.empty()
            : Roadmap.fromJson(j['roadmap'] as Map<String, dynamic>),
        j['recent'] == null ? null : List<String>.from(j['recent'] as List),
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
