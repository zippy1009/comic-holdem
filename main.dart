import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TexasHoldemComicApp());
}

class TexasHoldemComicApp extends StatelessWidget {
  const TexasHoldemComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comic Texas Hold\'em 6-Max',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F131A),
      ),
      home: const PokerTableScreen(),
    );
  }
}

// ============================================================================
// 1. DOMAIN MODELS (카드, 덱, 플레이어, 팟, 테이블 상태)
// ============================================================================

enum Suit {
  spades('♠', Color(0xFF212121)),
  hearts('♥', Color(0xFFD32F2F)),
  diamonds('♦', Color(0xFF1976D2)),
  clubs('♣', Color(0xFF388E3C));

  final String symbol;
  final Color color;
  const Suit(this.symbol, this.color);
}

enum Rank {
  two(2, '2'),
  three(3, '3'),
  four(4, '4'),
  five(5, '5'),
  six(6, '6'),
  seven(7, '7'),
  eight(8, '8'),
  nine(9, '9'),
  ten(10, '10'),
  jack(11, 'J'),
  queen(12, 'Q'),
  king(13, 'K'),
  ace(14, 'A');

  final int value;
  final String label;
  const Rank(this.value, this.label);
}

class PlayingCard implements Comparable<PlayingCard> {
  final Suit suit;
  final Rank rank;

  const PlayingCard({required this.suit, required this.rank});

  @override
  int compareTo(PlayingCard other) => other.rank.value.compareTo(rank.value);

  @override
  String toString() => '${suit.symbol}${rank.label}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayingCard && suit == other.suit && rank == other.rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

class Deck {
  final List<PlayingCard> _cards = [];
  final Random _random = Random();

  Deck() {
    resetAndShuffle();
  }

  void resetAndShuffle() {
    _cards.clear();
    for (final suit in Suit.values) {
      for (final rank in Rank.values) {
        _cards.add(PlayingCard(suit: suit, rank: rank));
      }
    }
    for (int i = _cards.length - 1; i > 0; i--) {
      int j = _random.nextInt(i + 1);
      final temp = _cards[i];
      _cards[i] = _cards[j];
      _cards[j] = temp;
    }
  }

  PlayingCard draw() => _cards.removeLast();
  List<PlayingCard> drawMany(int count) => List.generate(count, (_) => draw());
}

enum PlayerStatus { active, folded, allIn, sittingOut }

enum BotPersona { tightAggressive, looseAggressive, callingStation, balanced }

class Player {
  final String id;
  final String name;
  final int seatIndex;
  final bool isBot;
  final BotPersona persona;
  final int chips;
  final List<PlayingCard> holeCards;
  final PlayerStatus status;
  final int currentRoundBet;
  final int totalHandBet;
  final bool hasActedThisRound;
  final String? lastActionText;

  const Player({
    required this.id,
    required this.name,
    required this.seatIndex,
    required this.isBot,
    this.persona = BotPersona.balanced,
    required this.chips,
    this.holeCards = const [],
    this.status = PlayerStatus.active,
    this.currentRoundBet = 0,
    this.totalHandBet = 0,
    this.hasActedThisRound = false,
    this.lastActionText,
  });

  bool get canAct => status == PlayerStatus.active && chips > 0;
  bool get isInHand =>
      status == PlayerStatus.active || status == PlayerStatus.allIn;

  Player copyWith({
    int? chips,
    List<PlayingCard>? holeCards,
    PlayerStatus? status,
    int? currentRoundBet,
    int? totalHandBet,
    bool? hasActedThisRound,
    String? lastActionText,
    bool clearActionText = false,
  }) {
    return Player(
      id: id,
      name: name,
      seatIndex: seatIndex,
      isBot: isBot,
      persona: persona,
      chips: chips ?? this.chips,
      holeCards: holeCards ?? this.holeCards,
      status: status ?? this.status,
      currentRoundBet: currentRoundBet ?? this.currentRoundBet,
      totalHandBet: totalHandBet ?? this.totalHandBet,
      hasActedThisRound: hasActedThisRound ?? this.hasActedThisRound,
      lastActionText:
          clearActionText ? null : (lastActionText ?? this.lastActionText),
    );
  }
}

class Pot {
  final int amount;
  final Set<String> eligiblePlayerIds;

  const Pot({required this.amount, required this.eligiblePlayerIds});

  Pot copyWith({int? amount, Set<String>? eligiblePlayerIds}) {
    return Pot(
      amount: amount ?? this.amount,
      eligiblePlayerIds: eligiblePlayerIds ?? this.eligiblePlayerIds,
    );
  }
}

enum Street { waiting, preFlop, flop, turn, river, showdown }

enum ActionType { fold, check, call, raise, allIn }

class PlayerAction {
  final String playerId;
  final ActionType type;
  final int amount;

  const PlayerAction({
    required this.playerId,
    required this.type,
    this.amount = 0,
  });
}

class TableState {
  final int handNumber;
  final Street street;
  final List<Player> players;
  final List<PlayingCard> communityCards;
  final List<Pot> pots;
  final int dealerSeatIndex;
  final int currentTurnSeatIndex;
  final int smallBlind;
  final int bigBlind;
  final int currentHighestBet;
  final int lastRaiseDelta;
  final String statusMessage;
  final Set<String> winnerIds;

  const TableState({
    this.handNumber = 0,
    this.street = Street.waiting,
    required this.players,
    this.communityCards = const [],
    this.pots = const [],
    this.dealerSeatIndex = 0,
    this.currentTurnSeatIndex = 0,
    this.smallBlind = 10,
    this.bigBlind = 20,
    this.currentHighestBet = 0,
    this.lastRaiseDelta = 20,
    this.statusMessage = '새 핸드를 시작하세요.',
    this.winnerIds = const {},
  });

  int get totalPotAmount {
    final closed = pots.fold<int>(0, (s, p) => s + p.amount);
    final current = players.fold<int>(0, (s, p) => s + p.currentRoundBet);
    return closed + current;
  }

  Player get currentPlayer =>
      players.firstWhere((p) => p.seatIndex == currentTurnSeatIndex);

  int get callAmountForCurrentPlayer {
    final needed = currentHighestBet - currentPlayer.currentRoundBet;
    return needed.clamp(0, currentPlayer.chips);
  }

  int get minRaiseTargetBet => currentHighestBet + lastRaiseDelta;

  TableState copyWith({
    int? handNumber,
    Street? street,
    List<Player>? players,
    List<PlayingCard>? communityCards,
    List<Pot>? pots,
    int? dealerSeatIndex,
    int? currentTurnSeatIndex,
    int? smallBlind,
    int? bigBlind,
    int? currentHighestBet,
    int? lastRaiseDelta,
    String? statusMessage,
    Set<String>? winnerIds,
  }) {
    return TableState(
      handNumber: handNumber ?? this.handNumber,
      street: street ?? this.street,
      players: players ?? this.players,
      communityCards: communityCards ?? this.communityCards,
      pots: pots ?? this.pots,
      dealerSeatIndex: dealerSeatIndex ?? this.dealerSeatIndex,
      currentTurnSeatIndex: currentTurnSeatIndex ?? this.currentTurnSeatIndex,
      smallBlind: smallBlind ?? this.smallBlind,
      bigBlind: bigBlind ?? this.bigBlind,
      currentHighestBet: currentHighestBet ?? this.currentHighestBet,
      lastRaiseDelta: lastRaiseDelta ?? this.lastRaiseDelta,
      statusMessage: statusMessage ?? this.statusMessage,
      winnerIds: winnerIds ?? this.winnerIds,
    );
  }
}

// ============================================================================
// 2. 7-CARD HAND EVALUATOR (7장 중 최고 5장 족보 판별기)
// ============================================================================

enum HandCategory {
  highCard(0, '하이카드'),
  onePair(1, '원페어'),
  twoPair(2, '투페어'),
  threeOfAKind(3, '트리플'),
  straight(4, '스트레이트'),
  flush(5, '플러시'),
  fullHouse(6, '풀하우스'),
  fourOfAKind(7, '포카드'),
  straightFlush(8, '스트레이트 플러시');

  final int rankValue;
  final String koreanName;
  const HandCategory(this.rankValue, this.koreanName);
}

class EvaluatedHand implements Comparable<EvaluatedHand> {
  final HandCategory category;
  final List<int> tieBreakers;
  final int score;

  const EvaluatedHand({
    required this.category,
    required this.tieBreakers,
    required this.score,
  });

  String get description {
    final topRank = Rank.values.firstWhere((r) => r.value == tieBreakers.first);
    return '${topRank.label} 탑 ${category.koreanName}';
  }

  @override
  int compareTo(EvaluatedHand other) => score.compareTo(other.score);
}

class HandEvaluator {
  static EvaluatedHand evaluateBest(List<PlayingCard> cards) {
    if (cards.length < 5) {
      throw ArgumentError('최소 5장의 카드가 필요합니다.');
    }
    final combos = _generate5CardCombinations(cards);
    EvaluatedHand? best;
    for (final combo in combos) {
      final evaluated = _evaluate5Cards(combo);
      if (best == null || evaluated.score > best.score) {
        best = evaluated;
      }
    }
    return best!;
  }

  static EvaluatedHand _evaluate5Cards(List<PlayingCard> fiveCards) {
    final sorted = List<PlayingCard>.from(fiveCards)..sort();
    final isFlush = sorted.every((c) => c.suit == sorted.first.suit);

    final Map<int, int> counts = {};
    for (final c in sorted) {
      counts[c.rank.value] = (counts[c.rank.value] ?? 0) + 1;
    }

    final sortedRanks = counts.keys.toList()
      ..sort((a, b) {
        final countCompare = counts[b]!.compareTo(counts[a]!);
        return countCompare != 0 ? countCompare : b.compareTo(a);
      });

    bool isStraight = false;
    int straightHigh = 0;
    if (counts.length == 5) {
      final highest = sorted.first.rank.value;
      final lowest = sorted.last.rank.value;
      if (highest - lowest == 4) {
        isStraight = true;
        straightHigh = highest;
      } else if (sorted[0].rank == Rank.ace &&
          sorted[1].rank == Rank.five &&
          sorted[2].rank == Rank.four &&
          sorted[3].rank == Rank.three &&
          sorted[4].rank == Rank.two) {
        isStraight = true;
        straightHigh = 5;
      }
    }

    HandCategory category;
    List<int> tieBreakers = sortedRanks;

    if (isFlush && isStraight) {
      category = HandCategory.straightFlush;
      tieBreakers = [straightHigh];
    } else if (counts[sortedRanks[0]] == 4) {
      category = HandCategory.fourOfAKind;
    } else if (counts[sortedRanks[0]] == 3 && counts[sortedRanks[1]] == 2) {
      category = HandCategory.fullHouse;
    } else if (isFlush) {
      category = HandCategory.flush;
    } else if (isStraight) {
      category = HandCategory.straight;
      tieBreakers = [straightHigh];
    } else if (counts[sortedRanks[0]] == 3) {
      category = HandCategory.threeOfAKind;
    } else if (counts[sortedRanks[0]] == 2 && counts[sortedRanks[1]] == 2) {
      category = HandCategory.twoPair;
    } else if (counts[sortedRanks[0]] == 2) {
      category = HandCategory.onePair;
    } else {
      category = HandCategory.highCard;
    }

    int score = category.rankValue << 20;
    for (int i = 0; i < tieBreakers.length; i++) {
      score |= (tieBreakers[i] << (16 - i * 4));
    }

    return EvaluatedHand(
      category: category,
      tieBreakers: tieBreakers,
      score: score,
    );
  }

  static List<List<PlayingCard>> _generate5CardCombinations(
      List<PlayingCard> cards) {
    final List<List<PlayingCard>> results = [];
    void helper(int start, List<PlayingCard> current) {
      if (current.length == 5) {
        results.add(List.from(current));
        return;
      }
      for (int i = start; i < cards.length; i++) {
        current.add(cards[i]);
        helper(i + 1, current);
        current.removeLast();
      }
    }

    helper(0, []);
    return results;
  }
}

// ============================================================================
// 3. GAME ENGINE (블라인드, 배팅 라운드, 사이드 팟 분할, 쇼다운 정산)
// ============================================================================

class GameEngine {
  final Deck _deck = Deck();

  TableState startNewHand(TableState currentState) {
    _deck.resetAndShuffle();

    List<Player> players = currentState.players.map((p) {
      int startingChips = p.chips;
      if (startingChips <= 0) {
        startingChips = 1000; // 파산 시 1,000칩 자동 리바이
      }
      return p.copyWith(
        chips: startingChips,
        holeCards: _deck.drawMany(2),
        status: PlayerStatus.active,
        currentRoundBet: 0,
        totalHandBet: 0,
        hasActedThisRound: false,
        clearActionText: true,
      );
    }).toList();

    final activeSeats = players
        .where((p) => p.status == PlayerStatus.active)
        .map((p) => p.seatIndex)
        .toList();

    final nextDealerSeat =
        _getNextSeat(currentState.dealerSeatIndex, activeSeats);
    final sbSeat = _getNextSeat(nextDealerSeat, activeSeats);
    final bbSeat = _getNextSeat(sbSeat, activeSeats);
    final utgSeat = _getNextSeat(bbSeat, activeSeats);

    players = _postBlind(players, sbSeat, currentState.smallBlind, 'SB');
    players = _postBlind(players, bbSeat, currentState.bigBlind, 'BB');

    return currentState.copyWith(
      handNumber: currentState.handNumber + 1,
      street: Street.preFlop,
      players: players,
      communityCards: [],
      pots: [],
      dealerSeatIndex: nextDealerSeat,
      currentTurnSeatIndex: utgSeat,
      currentHighestBet: currentState.bigBlind,
      lastRaiseDelta: currentState.bigBlind,
      statusMessage: 'Hand #${currentState.handNumber + 1} - 프리플랍 배팅 시작!',
      winnerIds: {},
    );
  }

  TableState handleAction(TableState state, PlayerAction action) {
    final idx = state.players.indexWhere((p) => p.id == action.playerId);
    if (idx == -1) return state;

    final player = state.players[idx];
    List<Player> updatedPlayers = List.from(state.players);
    int newHighestBet = state.currentHighestBet;
    int newLastRaiseDelta = state.lastRaiseDelta;
    String actionLabel = '';

    switch (action.type) {
      case ActionType.fold:
        actionLabel = 'FOLD';
        updatedPlayers[idx] = player.copyWith(
          status: PlayerStatus.folded,
          hasActedThisRound: true,
          lastActionText: actionLabel,
        );
        break;

      case ActionType.check:
        actionLabel = 'CHECK';
        updatedPlayers[idx] = player.copyWith(
          hasActedThisRound: true,
          lastActionText: actionLabel,
        );
        break;

      case ActionType.call:
        final needed = state.currentHighestBet - player.currentRoundBet;
        final added = min(needed, player.chips);
        final isAllIn = added == player.chips;
        actionLabel = isAllIn ? 'ALL-IN!' : 'CALL $added';

        updatedPlayers[idx] = player.copyWith(
          chips: player.chips - added,
          currentRoundBet: player.currentRoundBet + added,
          totalHandBet: player.totalHandBet + added,
          status: isAllIn ? PlayerStatus.allIn : PlayerStatus.active,
          hasActedThisRound: true,
          lastActionText: actionLabel,
        );
        break;

      case ActionType.raise:
      case ActionType.allIn:
        final maxPossible = player.currentRoundBet + player.chips;
        final targetBet = action.type == ActionType.allIn
            ? maxPossible
            : min(action.amount, maxPossible);
        final added = targetBet - player.currentRoundBet;
        final isAllIn = added == player.chips;

        if (targetBet > state.currentHighestBet) {
          final raiseDelta = targetBet - state.currentHighestBet;
          if (raiseDelta >= state.lastRaiseDelta) {
            newLastRaiseDelta = raiseDelta;
            updatedPlayers = updatedPlayers.map((p) {
              if (p.id != player.id && p.status == PlayerStatus.active) {
                return p.copyWith(hasActedThisRound: false);
              }
              return p;
            }).toList();
          }
          newHighestBet = targetBet;
        }

        actionLabel = isAllIn ? 'ALL-IN! ($targetBet)' : 'RAISE $targetBet';
        updatedPlayers[idx] = player.copyWith(
          chips: player.chips - added,
          currentRoundBet: targetBet,
          totalHandBet: player.totalHandBet + added,
          status: isAllIn ? PlayerStatus.allIn : PlayerStatus.active,
          hasActedThisRound: true,
          lastActionText: actionLabel,
        );
        break;
    }

    TableState nextState = state.copyWith(
      players: updatedPlayers,
      currentHighestBet: newHighestBet,
      lastRaiseDelta: newLastRaiseDelta,
      statusMessage: '${player.name} ➔ $actionLabel',
    );

    return _advanceTurnOrStreet(nextState);
  }

  TableState _advanceTurnOrStreet(TableState state) {
    final inHand = state.players.where((p) => p.isInHand).toList();

    if (inHand.length == 1) {
      return _settlePotsAndEndHand(state, isFoldWin: true);
    }

    final activePlayers = state.players.where((p) => p.canAct).toList();
    final isRoundComplete = activePlayers.every(
      (p) => p.hasActedThisRound && p.currentRoundBet == state.currentHighestBet,
    );

    if (!isRoundComplete) {
      final activeSeats = activePlayers.map((p) => p.seatIndex).toList();
      final nextSeat = _getNextSeat(state.currentTurnSeatIndex, activeSeats);
      return state.copyWith(currentTurnSeatIndex: nextSeat);
    }

    final updatedPots = _calculateSidePots(state.players);
    final resetPlayers = state.players.map((p) {
      return p.copyWith(
        currentRoundBet: 0,
        hasActedThisRound: false,
        clearActionText: p.status == PlayerStatus.active,
      );
    }).toList();

    TableState clearedState = state.copyWith(
      players: resetPlayers,
      pots: updatedPots,
      currentHighestBet: 0,
      lastRaiseDelta: state.bigBlind,
    );

    if (activePlayers.length <= 1 && clearedState.street != Street.river) {
      final needed = 5 - clearedState.communityCards.length;
      final fullBoard = [
        ...clearedState.communityCards,
        if (needed > 0) ..._deck.drawMany(needed),
      ];
      return _settlePotsAndEndHand(
        clearedState.copyWith(street: Street.river, communityCards: fullBoard),
        isFoldWin: false,
      );
    }

    return _moveToNextStreet(clearedState);
  }

  TableState _moveToNextStreet(TableState state) {
    final activeSeats = state.players
        .where((p) => p.canAct)
        .map((p) => p.seatIndex)
        .toList();
    final firstSeat = activeSeats.isNotEmpty
        ? _getNextSeat(state.dealerSeatIndex, activeSeats)
        : state.dealerSeatIndex;

    switch (state.street) {
      case Street.preFlop:
        return state.copyWith(
          street: Street.flop,
          communityCards: [...state.communityCards, ..._deck.drawMany(3)],
          currentTurnSeatIndex: firstSeat,
          statusMessage: '플랍(Flop) 카드 3장 오픈!',
        );
      case Street.flop:
        return state.copyWith(
          street: Street.turn,
          communityCards: [...state.communityCards, _deck.draw()],
          currentTurnSeatIndex: firstSeat,
          statusMessage: '턴(Turn) 카드 오픈!',
        );
      case Street.turn:
        return state.copyWith(
          street: Street.river,
          communityCards: [...state.communityCards, _deck.draw()],
          currentTurnSeatIndex: firstSeat,
          statusMessage: '리버(River) 마지막 카드 오픈!',
        );
      case Street.river:
        return _settlePotsAndEndHand(state, isFoldWin: false);
      default:
        return state;
    }
  }

  List<Pot> _calculateSidePots(List<Player> players) {
    final contributors = players.where((p) => p.totalHandBet > 0).toList();
    if (contributors.isEmpty) return [];

    final tiers = contributors.map((p) => p.totalHandBet).toSet().toList()
      ..sort();

    List<Pot> pots = [];
    int prevTier = 0;

    for (final tier in tiers) {
      int sliceAmount = 0;
      Set<String> eligible = {};

      for (final p in contributors) {
        if (p.totalHandBet > prevTier) {
          sliceAmount += min(p.totalHandBet, tier) - prevTier;
          if (p.isInHand) eligible.add(p.id);
        }
      }

      if (sliceAmount > 0) {
        if (pots.isNotEmpty &&
            pots.last.eligiblePlayerIds.length == eligible.length &&
            pots.last.eligiblePlayerIds.containsAll(eligible)) {
          pots[pots.length - 1] =
              pots.last.copyWith(amount: pots.last.amount + sliceAmount);
        } else {
          pots.add(Pot(amount: sliceAmount, eligiblePlayerIds: eligible));
        }
      }
      prevTier = tier;
    }
    return pots;
  }

  TableState _settlePotsAndEndHand(TableState state,
      {required bool isFoldWin}) {
    final finalPots = _calculateSidePots(state.players);
    Map<String, int> payouts = {for (var p in state.players) p.id: 0};
    Set<String> allWinnerIds = {};
    String winningSummary = '';

    for (final pot in finalPots) {
      final eligibles = state.players
          .where((p) => pot.eligiblePlayerIds.contains(p.id))
          .toList();
      if (eligibles.isEmpty) continue;

      List<String> potWinners = [];
      if (isFoldWin || eligibles.length == 1) {
        potWinners = [eligibles.first.id];
        winningSummary = '🎉 ${eligibles.first.name} 전원 폴드 유도 승리!';
      } else {
        int bestScore = -1;
        EvaluatedHand? bestHand;
        for (final p in eligibles) {
          final eval = HandEvaluator.evaluateBest(
              [...p.holeCards, ...state.communityCards]);
          if (eval.score > bestScore) {
            bestScore = eval.score;
            bestHand = eval;
            potWinners = [p.id];
          } else if (eval.score == bestScore) {
            potWinners.add(p.id);
          }
        }
        final winnerNames = state.players
            .where((p) => potWinners.contains(p.id))
            .map((p) => p.name)
            .join(', ');
        winningSummary = '🏆 $winnerNames 승리! [${bestHand?.description ?? ''}]';
      }

      allWinnerIds.addAll(potWinners);
      final share = pot.amount ~/ potWinners.length;
      final rem = pot.amount % potWinners.length;

      for (int i = 0; i < potWinners.length; i++) {
        final wId = potWinners[i];
        payouts[wId] = (payouts[wId] ?? 0) + share + (i == 0 ? rem : 0);
      }
    }

    final updatedPlayers = state.players.map((p) {
      final won = payouts[p.id] ?? 0;
      return p.copyWith(
        chips: p.chips + won,
        currentRoundBet: 0,
        lastActionText: won > 0 ? '+$won 획득!' : p.lastActionText,
      );
    }).toList();

    return state.copyWith(
      street: Street.showdown,
      players: updatedPlayers,
      pots: finalPots,
      statusMessage: winningSummary,
      winnerIds: allWinnerIds,
    );
  }

  List<Player> _postBlind(
      List<Player> players, int seatIndex, int amount, String label) {
    return players.map((p) {
      if (p.seatIndex != seatIndex) return p;
      final actual = min(p.chips, amount);
      final isAllIn = actual == p.chips;
      return p.copyWith(
        chips: p.chips - actual,
        currentRoundBet: actual,
        totalHandBet: actual,
        status: isAllIn ? PlayerStatus.allIn : PlayerStatus.active,
        lastActionText: '$label $actual',
      );
    }).toList();
  }

  int _getNextSeat(int currentSeat, List<int> validSeats) {
    final sorted = List<int>.from(validSeats)..sort();
    for (final seat in sorted) {
      if (seat > currentSeat) return seat;
    }
    return sorted.first;
  }
}

// ============================================================================
// 4. AI BOT ENGINE (프리플랍 핸드 강도 + 포스트플랍 족보/팟오즈 의사결정)
// ============================================================================

class BotDecisionMaker {
  static final Random _rng = Random();

  static PlayerAction decideAction(TableState state, Player bot) {
    final toCall = state.callAmountForCurrentPlayer;
    final strength = _evaluateStrength(bot.holeCards, state.communityCards);

    double aggressionBonus = switch (bot.persona) {
      BotPersona.looseAggressive => 0.15,
      BotPersona.tightAggressive => -0.05,
      BotPersona.callingStation => 0.0,
      BotPersona.balanced => 0.05,
    };

    final adjustedStrength = (strength + aggressionBonus).clamp(0.0, 1.0);

    if (toCall == 0) {
      if (adjustedStrength > 0.65 && _rng.nextDouble() < 0.7) {
        final int target =
            max(state.minRaiseTargetBet, (state.totalPotAmount * 0.6).toInt());
        return _buildRaiseOrCall(state, bot, target);
      }
      return PlayerAction(playerId: bot.id, type: ActionType.check);
    }

    final potOdds = toCall / (state.totalPotAmount + toCall + 1);

    if (adjustedStrength > 0.78) {
      if (_rng.nextDouble() < 0.65 && bot.chips > toCall) {
        final int target = state.currentHighestBet +
            max(state.lastRaiseDelta, (state.totalPotAmount * 0.75).toInt());
        return _buildRaiseOrCall(state, bot, target);
      }
      return PlayerAction(playerId: bot.id, type: ActionType.call);
    }

    if (adjustedStrength >= potOdds ||
        toCall <= state.bigBlind * 2 ||
        (bot.persona == BotPersona.callingStation && _rng.nextDouble() < 0.6)) {
      return PlayerAction(playerId: bot.id, type: ActionType.call);
    }

    if (_rng.nextDouble() < 0.12 && toCall <= bot.chips * 0.2) {
      return PlayerAction(playerId: bot.id, type: ActionType.call);
    }

    return PlayerAction(playerId: bot.id, type: ActionType.fold);
  }

  static PlayerAction _buildRaiseOrCall(
      TableState state, Player bot, int desiredTargetBet) {
    final maxPossible = bot.currentRoundBet + bot.chips;
    if (maxPossible <= state.currentHighestBet) {
      return PlayerAction(playerId: bot.id, type: ActionType.call);
    }
    if (desiredTargetBet >= maxPossible ||
        maxPossible < state.minRaiseTargetBet) {
      return PlayerAction(playerId: bot.id, type: ActionType.allIn);
    }
    final validRaise = max(desiredTargetBet, state.minRaiseTargetBet);
    return PlayerAction(
        playerId: bot.id, type: ActionType.raise, amount: validRaise);
  }

  static double _evaluateStrength(
      List<PlayingCard> hole, List<PlayingCard> board) {
    if (hole.length < 2) return 0.2;

    if (board.isEmpty) {
      final r1 = hole[0].rank.value;
      final r2 = hole[1].rank.value;
      final high = max(r1, r2);
      final low = min(r1, r2);
      final isPair = r1 == r2;
      final isSuited = hole[0].suit == hole[1].suit;
      final gap = high - low;

      double score = (high + low) / 28.0;
      if (isPair) score += 0.35;
      if (isSuited) score += 0.08;
      if (gap == 1) score += 0.06;
      return score.clamp(0.1, 0.98);
    }

    final eval = HandEvaluator.evaluateBest([...hole, ...board]);
    return switch (eval.category) {
      HandCategory.highCard => 0.22,
      HandCategory.onePair => 0.52 + (eval.tieBreakers.first / 50.0),
      HandCategory.twoPair => 0.74,
      HandCategory.threeOfAKind => 0.83,
      HandCategory.straight => 0.89,
      HandCategory.flush => 0.93,
      HandCategory.fullHouse => 0.97,
      HandCategory.fourOfAKind => 0.99,
      HandCategory.straightFlush => 1.0,
    };
  }
}

// ============================================================================
// 5. ANIMATION & COMIC CHARACTER WIDGETS (3D 카드 플립, 칩 이동, 만화 아바타)
// ============================================================================

class FlippableCard extends StatelessWidget {
  final PlayingCard card;
  final bool isFaceUp;
  final bool small;
  final Duration duration;

  const FlippableCard({
    super.key,
    required this.card,
    required this.isFaceUp,
    this.small = false,
    this.duration = const Duration(milliseconds: 480),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: pi,
        end: isFaceUp ? 0.0 : pi,
      ),
      duration: duration,
      curve: Curves.easeOutBack,
      builder: (context, angle, child) {
        final isShowingBack = angle >= (pi / 2);

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateY(angle),
          child: isShowingBack
              ? _buildCardBack(small: small)
              : _buildCardFront(card, small: small),
        );
      },
    );
  }

  Widget _buildCardFront(PlayingCard card, {required bool small}) {
    final width = small ? 32.0 : 44.0;
    final height = small ? 46.0 : 62.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(1, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            card.rank.label,
            style: TextStyle(
              color: card.suit.color,
              fontWeight: FontWeight.w900,
              fontSize: small ? 12 : 16,
              height: 1.0,
            ),
          ),
          Text(
            card.suit.symbol,
            style: TextStyle(
              color: card.suit.color,
              fontSize: small ? 13 : 18,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack({required bool small}) {
    return Container(
      width: small ? 32.0 : 44.0,
      height: small ? 46.0 : 62.0,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9E1B22), Color(0xFF5E0E12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade200, width: 1.3),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, color: Colors.white24, size: 14),
      ),
    );
  }
}

class FlyingChipData {
  final String id;
  final Alignment startAlignment;
  final Alignment endAlignment;
  final int amount;

  FlyingChipData({
    required this.id,
    required this.startAlignment,
    this.endAlignment = const Alignment(0.0, -0.08),
    required this.amount,
  });
}

class FlyingChipWidget extends StatelessWidget {
  final FlyingChipData data;
  final VoidCallback onComplete;

  const FlyingChipWidget({
    super.key,
    required this.data,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      onEnd: onComplete,
      builder: (context, progress, child) {
        final currentAlign = Alignment.lerp(
          data.startAlignment,
          data.endAlignment,
          progress,
        )!;
        final scale = 1.0 - (progress * 0.2);
        final opacity = (1.0 - (progress * 0.8)).clamp(0.0, 1.0);

        return Align(
          alignment: currentAlign,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.shade700,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 3))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, color: Colors.white, size: 13),
            const SizedBox(width: 3),
            Text(
              '+${data.amount}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CharacterMood {
  normal,
  thinking,
  aggressive,
  allIn,
  folded,
  winner,
  shocked,
}

class CharacterStyle {
  final Color skinColor;
  final Color hairColor;
  final Color clothesColor;
  final bool hasSunglasses;
  final String catchphrase;

  const CharacterStyle({
    required this.skinColor,
    required this.hairColor,
    required this.clothesColor,
    this.hasSunglasses = false,
    required this.catchphrase,
  });
}

const List<CharacterStyle> kCharacterStyles = [
  CharacterStyle(
    skinColor: Color(0xFFFFDFC4),
    hairColor: Color(0xFF2C3E50),
    clothesColor: Color(0xFF2980B9),
    catchphrase: '승부는 지금부터다!',
  ),
  CharacterStyle(
    skinColor: Color(0xFFF5CBA7),
    hairColor: Color(0xFF1A252F),
    clothesColor: Color(0xFF2C3E50),
    hasSunglasses: true,
    catchphrase: '확률 계산은 이미 끝났다.',
  ),
  CharacterStyle(
    skinColor: Color(0xFFFFE0BD),
    hairColor: Color(0xFFC0392B),
    clothesColor: Color(0xFF8E44AD),
    catchphrase: '전부 쓸어 담아줄게!!',
  ),
  CharacterStyle(
    skinColor: Color(0xFFE5B887),
    hairColor: Color(0xFF5D4037),
    clothesColor: Color(0xFF27AE60),
    catchphrase: '끝까지 따라가 볼까나~',
  ),
  CharacterStyle(
    skinColor: Color(0xFFFFDFC4),
    hairColor: Color(0xFFF39C12),
    clothesColor: Color(0xFF16A085),
    catchphrase: '빈틈이 보이는군!',
  ),
  CharacterStyle(
    skinColor: Color(0xFFFFE5D9),
    hairColor: Color(0xFFE84393),
    clothesColor: Color(0xFFD35400),
    catchphrase: '블러핑인지 맞춰봐~!',
  ),
];

class ComicCharacterAvatar extends StatefulWidget {
  final int seatIndex;
  final CharacterMood mood;
  final String? actionText;

  const ComicCharacterAvatar({
    super.key,
    required this.seatIndex,
    required this.mood,
    this.actionText,
  });

  @override
  State<ComicCharacterAvatar> createState() => _ComicCharacterAvatarState();
}

class _ComicCharacterAvatarState extends State<ComicCharacterAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _fxController;

  @override
  void initState() {
    super.initState();
    _fxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = kCharacterStyles[widget.seatIndex % kCharacterStyles.length];
    final isFolded = widget.mood == CharacterMood.folded;

    return AnimatedBuilder(
      animation: _fxController,
      builder: (context, child) {
        double bounceOffset = 0;
        if (widget.mood == CharacterMood.allIn ||
            widget.mood == CharacterMood.winner) {
          bounceOffset = -4.0 * _fxController.value;
        }

        return SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.mood == CharacterMood.allIn)
                _buildAuraEffect(Colors.redAccent, Colors.orangeAccent),
              if (widget.mood == CharacterMood.winner)
                _buildAuraEffect(Colors.amber, Colors.yellowAccent),

              Transform.translate(
                offset: Offset(0, bounceOffset),
                child: ColorFiltered(
                  colorFilter: isFolded
                      ? const ColorFilter.mode(
                          Colors.grey, BlendMode.saturation)
                      : const ColorFilter.mode(
                          Colors.transparent, BlendMode.multiply),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF263040),
                      border: Border.all(
                        color: _getBorderColor(),
                        width: 2.2,
                      ),
                    ),
                    child: ClipOval(
                      child: CustomPaint(
                        painter: _CartoonFacePainter(
                          style: style,
                          mood: widget.mood,
                          animValue: _fxController.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              _buildMoodIconOverlay(),

              if (widget.actionText != null && widget.actionText!.isNotEmpty)
                Positioned(
                  top: -18,
                  child: _buildComicSpeechBubble(widget.actionText!),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _getBorderColor() {
    return switch (widget.mood) {
      CharacterMood.allIn => Colors.redAccent,
      CharacterMood.winner => Colors.amberAccent,
      CharacterMood.thinking => Colors.cyanAccent,
      CharacterMood.aggressive => Colors.orangeAccent,
      _ => Colors.white38,
    };
  }

  Widget _buildAuraEffect(Color outer, Color inner) {
    final scale = 1.0 + (_fxController.value * 0.25);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [inner.withOpacity(0.85), outer.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }

  Widget _buildMoodIconOverlay() {
    switch (widget.mood) {
      case CharacterMood.thinking:
        return Positioned(
          right: 0,
          top: 2 + (_fxController.value * 4),
          child: const Text('💦', style: TextStyle(fontSize: 13)),
        );
      case CharacterMood.allIn:
        return Positioned(
          right: -2,
          bottom: -2,
          child: Transform.scale(
            scale: 0.9 + (_fxController.value * 0.3),
            child: const Text('🔥', style: TextStyle(fontSize: 16)),
          ),
        );
      case CharacterMood.winner:
        return const Positioned(
          top: -6,
          child: Text('👑', style: TextStyle(fontSize: 16)),
        );
      case CharacterMood.shocked:
        return const Positioned(
          left: -2,
          top: 0,
          child: Text('⚡', style: TextStyle(fontSize: 14)),
        );
      case CharacterMood.folded:
        return const Positioned(
          right: -2,
          top: 0,
          child: Text('💤', style: TextStyle(fontSize: 12)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildComicSpeechBubble(String text) {
    final isAllIn = text.contains('ALL-IN');
    final isWin = text.contains('획득');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: isAllIn
            ? Colors.redAccent.shade700
            : (isWin ? Colors.amber.shade400 : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(1, 2))
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isAllIn ? Colors.white : Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

class _CartoonFacePainter extends CustomPainter {
  final CharacterStyle style;
  final CharacterMood mood;
  final double animValue;

  _CartoonFacePainter({
    required this.style,
    required this.mood,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final clothesPaint = Paint()..color = style.clothesColor;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.95), width: w * 0.85, height: h * 0.45),
      clothesPaint,
    );

    final skinPaint = Paint()..color = style.skinColor;
    canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.34, skinPaint);

    final hairPaint = Paint()..color = style.hairColor;
    final hairPath = Path()
      ..moveTo(w * 0.14, h * 0.48)
      ..quadraticBezierTo(w * 0.5, h * 0.05, w * 0.86, h * 0.48)
      ..lineTo(w * 0.78, h * 0.32)
      ..lineTo(w * 0.62, h * 0.38)
      ..lineTo(w * 0.48, h * 0.30)
      ..lineTo(w * 0.32, h * 0.38)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    _drawEyesAndBrows(canvas, w, h);
    _drawMouth(canvas, w, h);
  }

  void _drawEyesAndBrows(Canvas canvas, double w, double h) {
    final leftEyeCenter = Offset(w * 0.37, h * 0.52);
    final rightEyeCenter = Offset(w * 0.63, h * 0.52);

    if (mood == CharacterMood.allIn) {
      final glowPaint = Paint()
        ..color = Colors.redAccent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(leftEyeCenter, 5.0, glowPaint);
      canvas.drawCircle(rightEyeCenter, 5.0, glowPaint);

      final corePaint = Paint()..color = Colors.yellowAccent;
      canvas.drawCircle(leftEyeCenter, 2.2, corePaint);
      canvas.drawCircle(rightEyeCenter, 2.2, corePaint);
      return;
    }

    if (mood == CharacterMood.winner) {
      final winEyePaint = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCenter(center: leftEyeCenter, width: 7, height: 7),
          pi,
          pi,
          false,
          winEyePaint);
      canvas.drawArc(
          Rect.fromCenter(center: rightEyeCenter, width: 7, height: 7),
          pi,
          pi,
          false,
          winEyePaint);
      return;
    }

    if (mood == CharacterMood.shocked || mood == CharacterMood.folded) {
      final xPaint = Paint()
        ..color = Colors.black87
        ..strokeWidth = 1.8;
      for (final c in [leftEyeCenter, rightEyeCenter]) {
        canvas.drawLine(c.translate(-2.5, -2.5), c.translate(2.5, 2.5), xPaint);
        canvas.drawLine(c.translate(2.5, -2.5), c.translate(-2.5, 2.5), xPaint);
      }
      return;
    }

    if (style.hasSunglasses) {
      final glassPaint = Paint()..color = Colors.black87;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: leftEyeCenter, width: 11, height: 6.5),
          const Radius.circular(2),
        ),
        glassPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: rightEyeCenter, width: 11, height: 6.5),
          const Radius.circular(2),
        ),
        glassPaint,
      );
      canvas.drawLine(
          leftEyeCenter, rightEyeCenter, Paint()..strokeWidth = 1.8);
      return;
    }

    final eyeShift =
        mood == CharacterMood.thinking ? (animValue - 0.5) * 2.8 : 0.0;
    final whitePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = Colors.black87;

    canvas.drawCircle(leftEyeCenter, 3.8, whitePaint);
    canvas.drawCircle(rightEyeCenter, 3.8, whitePaint);
    canvas.drawCircle(leftEyeCenter.translate(eyeShift, 0), 2.1, pupilPaint);
    canvas.drawCircle(rightEyeCenter.translate(eyeShift, 0), 2.1, pupilPaint);

    if (mood == CharacterMood.aggressive) {
      final browPaint = Paint()
        ..color = style.hairColor
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(leftEyeCenter.translate(-4, -5),
          leftEyeCenter.translate(3, -2.5), browPaint);
      canvas.drawLine(rightEyeCenter.translate(4, -5),
          rightEyeCenter.translate(-3, -2.5), browPaint);
    }
  }

  void _drawMouth(Canvas canvas, double w, double h) {
    final mouthCenter = Offset(w * 0.5, h * 0.67);
    final mouthPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case CharacterMood.winner:
      case CharacterMood.aggressive:
        canvas.drawArc(
          Rect.fromCenter(center: mouthCenter, width: 10, height: 7),
          0,
          pi,
          false,
          mouthPaint,
        );
        break;
      case CharacterMood.allIn:
        canvas.drawOval(
          Rect.fromCenter(center: mouthCenter, width: 9, height: 7),
          Paint()..color = Colors.red.shade900,
        );
        break;
      case CharacterMood.shocked:
        canvas.drawCircle(mouthCenter, 3.0, mouthPaint);
        break;
      case CharacterMood.thinking:
      case CharacterMood.folded:
      case CharacterMood.normal:
        canvas.drawLine(
          mouthCenter.translate(-3.5, 0),
          mouthCenter.translate(3.5, 0),
          mouthPaint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CartoonFacePainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.animValue != animValue;
}

// ============================================================================
// 6. MAIN POKER TABLE SCREEN (전체 테이블 UI, 애니메이션 & 코믹 컷신 연동)
// ============================================================================

class PokerTableScreen extends StatefulWidget {
  const PokerTableScreen({super.key});

  @override
  State<PokerTableScreen> createState() => _PokerTableScreenState();
}

class _PokerTableScreenState extends State<PokerTableScreen> {
  final GameEngine _engine = GameEngine();
  late TableState _state;
  Timer? _botTimer;
  Timer? _cutsceneTimer;
  double _raiseSliderValue = 40;

  final List<FlyingChipData> _flyingChips = [];
  String? _comicCutsceneBanner;

  static const List<Alignment> _seatAlignments = [
    Alignment(0.0, 0.95), // Seat 0: 나 (Hero)
    Alignment(-0.90, 0.54), // Seat 1: 좌하단
    Alignment(-0.90, -0.54), // Seat 2: 좌상단
    Alignment(0.0, -0.95), // Seat 3: 상단 중앙
    Alignment(0.90, -0.54), // Seat 4: 우상단
    Alignment(0.90, 0.54), // Seat 5: 우하단
  ];

  @override
  void initState() {
    super.initState();
    _initTable();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _cutsceneTimer?.cancel();
    super.dispose();
  }

  void _initTable() {
    final initialPlayers = [
      const Player(
        id: 'hero',
        name: '나 (Hero)',
        seatIndex: 0,
        isBot: false,
        chips: 1000,
      ),
      const Player(
        id: 'bot_1',
        name: '민수 (냉철)',
        seatIndex: 1,
        isBot: true,
        persona: BotPersona.tightAggressive,
        chips: 1000,
      ),
      const Player(
        id: 'bot_2',
        name: '지영 (불꽃)',
        seatIndex: 2,
        isBot: true,
        persona: BotPersona.looseAggressive,
        chips: 1000,
      ),
      const Player(
        id: 'bot_3',
        name: '철수 (끈기)',
        seatIndex: 3,
        isBot: true,
        persona: BotPersona.callingStation,
        chips: 1000,
      ),
      const Player(
        id: 'bot_4',
        name: '현우 (두뇌)',
        seatIndex: 4,
        isBot: true,
        persona: BotPersona.balanced,
        chips: 1000,
      ),
      const Player(
        id: 'bot_5',
        name: '수진 (조커)',
        seatIndex: 5,
        isBot: true,
        persona: BotPersona.looseAggressive,
        chips: 1000,
      ),
    ];

    _state = TableState(players: initialPlayers);
    _startNewHand();
  }

  void _startNewHand() {
    _botTimer?.cancel();
    setState(() {
      _comicCutsceneBanner = null;
      _state = _engine.startNewHand(_state);
      _syncRaiseSlider();
    });
    _scheduleBotIfNeeded();
  }

  void _syncRaiseSlider() {
    final hero = _state.players.first;
    final maxBet = (hero.currentRoundBet + hero.chips).toDouble();
    final minRaise = _state.minRaiseTargetBet.toDouble();
    _raiseSliderValue = min(minRaise, maxBet);
  }

  void _triggerCutsceneBanner(String text) {
    _cutsceneTimer?.cancel();
    setState(() => _comicCutsceneBanner = text);
    _cutsceneTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _comicCutsceneBanner = null);
    });
  }

  void _onPlayerAction(PlayerAction action) {
    _botTimer?.cancel();

    final actingBefore =
        _state.players.firstWhere((p) => p.id == action.playerId);
    final nextState = _engine.handleAction(_state, action);
    final actingAfter =
        nextState.players.firstWhere((p) => p.id == action.playerId);

    final chipSpent = actingBefore.chips - actingAfter.chips;

    setState(() {
      if (chipSpent > 0) {
        _flyingChips.add(
          FlyingChipData(
            id: '${DateTime.now().microsecondsSinceEpoch}_${action.playerId}',
            startAlignment: _seatAlignments[actingBefore.seatIndex],
            amount: chipSpent,
          ),
        );
        HapticFeedback.lightImpact();
      }

      if (actingAfter.status == PlayerStatus.allIn &&
          actingBefore.status != PlayerStatus.allIn) {
        final phrase = kCharacterStyles[actingAfter.seatIndex].catchphrase;
        _triggerCutsceneBanner('🔥 ${actingAfter.name} ALL-IN!! "$phrase" 🔥');
        HapticFeedback.heavyImpact();
      }

      _state = nextState;
      _syncRaiseSlider();
    });

    _scheduleBotIfNeeded();
  }

  void _scheduleBotIfNeeded() {
    if (_state.street == Street.showdown || _state.street == Street.waiting) {
      return;
    }
    final current = _state.currentPlayer;
    if (current.isBot && current.canAct) {
      _botTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        final botAction = BotDecisionMaker.decideAction(_state, current);
        _onPlayerAction(botAction);
      });
    }
  }

  CharacterMood _resolvePlayerMood(Player player) {
    if (player.status == PlayerStatus.folded) {
      return CharacterMood.folded;
    }
    if (_state.street == Street.showdown) {
      return _state.winnerIds.contains(player.id)
        ? CharacterMood.winner
        : CharacterMood.shocked;
    }
    if (player.status == PlayerStatus.allIn) {
      return CharacterMood.allIn;
    }
    if (_state.currentTurnSeatIndex == player.seatIndex) {
      return CharacterMood.thinking;
    }
    if (player.lastActionText != null &&
        player.lastActionText!.startsWith('RAISE')) {
      return CharacterMood.aggressive;
    }
    return CharacterMood.normal;
  }

  String _getHeroHandHint() {
    final hero = _state.players.first;
    if (hero.holeCards.isEmpty) return '';
    final allCards = [...hero.holeCards, ..._state.communityCards];
    if (allCards.length < 5) {
      final isPair = hero.holeCards[0].rank == hero.holeCards[1].rank;
      return isPair
          ? '포켓 페어 (${hero.holeCards[0].rank.label})'
          : '${hero.holeCards[0].rank.label} 하이';
    }
    return HandEvaluator.evaluateBest(allCards).description;
  }

  @override
  Widget build(BuildContext context) {
    final isHeroTurn = _state.street != Street.showdown &&
        _state.currentTurnSeatIndex == 0 &&
        _state.players.first.canAct;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildPokerFelt(constraints),
                      _buildCenterBoard(),
                      ..._buildAllSeats(),
                      ..._flyingChips.map((chipData) {
                        return FlyingChipWidget(
                          key: ValueKey(chipData.id),
                          data: chipData,
                          onComplete: () {
                            if (mounted) {
                              setState(() {
                                _flyingChips
                                    .removeWhere((c) => c.id == chipData.id);
                              });
                            }
                          },
                        );
                      }),
                      if (_comicCutsceneBanner != null)
                        _buildComicCutsceneOverlay(_comicCutsceneBanner!),
                    ],
                  );
                },
              ),
            ),
            _buildBottomControlBar(isHeroTurn),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: const Color(0xFF171E29),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
              const SizedBox(width: 6),
              Text(
                'COMIC HOLD\'EM  |  #${_state.handNumber}  |  Blinds ${_state.smallBlind}/${_state.bigBlind}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white70),
              ),
            ],
          ),
          Flexible(
            child: Text(
              _state.statusMessage,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '내 족보: ${_getHeroHandHint()}',
            style: const TextStyle(
                color: Colors.lightGreenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPokerFelt(BoxConstraints constraints) {
    return Container(
      width: constraints.maxWidth * 0.74,
      height: constraints.maxHeight * 0.72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(200),
        gradient: const RadialGradient(
          colors: [Color(0xFF1E6B43), Color(0xFF0E3821)],
          radius: 0.9,
        ),
        border: Border.all(color: const Color(0xFF4A2E1B), width: 9),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 18, spreadRadius: 3),
        ],
      ),
    );
  }

  Widget _buildCenterBoard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.7)),
          ),
          child: Text(
            'TOTAL POT: ${_state.totalPotAmount} 칩',
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        if (_state.pots.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _state.pots
                  .asMap()
                  .entries
                  .map((e) =>
                      '${e.key == 0 ? "메인" : "사이드${e.key}"}: ${e.value.amount}')
                  .join(' | '),
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            if (index < _state.communityCards.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: FlippableCard(
                  key: ValueKey('comm_${index}_${_state.handNumber}'),
                  card: _state.communityCards[index],
                  isFaceUp: true,
                ),
              );
            }
            return Container(
              width: 44,
              height: 62,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24),
              ),
            );
          }),
        ),
      ],
    );
  }

  List<Widget> _buildAllSeats() {
    return _state.players.map((player) {
      final isTurn = _state.street != Street.showdown &&
          _state.currentTurnSeatIndex == player.seatIndex;
      final isDealer = _state.dealerSeatIndex == player.seatIndex;
      final isWinner = _state.winnerIds.contains(player.id);
      final showHoleCards = !player.isBot ||
          (_state.street == Street.showdown && player.isInHand);
      final mood = _resolvePlayerMood(player);

      return Align(
        alignment: _seatAlignments[player.seatIndex],
        child: _buildPlayerSeat(
          player: player,
          mood: mood,
          isTurn: isTurn,
          isDealer: isDealer,
          isWinner: isWinner,
          showHoleCards: showHoleCards,
        ),
      );
    }).toList();
  }

  Widget _buildPlayerSeat({
    required Player player,
    required CharacterMood mood,
    required bool isTurn,
    required bool isDealer,
    required bool isWinner,
    required bool showHoleCards,
  }) {
    final isFolded = player.status == PlayerStatus.folded;

    return Opacity(
      opacity: isFolded ? 0.55 : 1.0,
      child: Container(
        width: 195,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1B222E).withOpacity(0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isWinner
                ? Colors.greenAccent
                : (isTurn ? Colors.amberAccent : Colors.white24),
            width: (isTurn || isWinner) ? 2.4 : 1.0,
          ),
          boxShadow: isTurn
              ? [
                  BoxShadow(
                    color: Colors.amberAccent.withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ComicCharacterAvatar(
              seatIndex: player.seatIndex,
              mood: mood,
              actionText: player.lastActionText,
            ),
            const SizedBox(width: 6),
            Row(
              children: player.holeCards.isEmpty
                  ? [const SizedBox(width: 64, height: 46)]
                  : player.holeCards.asMap().entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: FlippableCard(
                          key: ValueKey(
                              'hole_${player.id}_${entry.key}_${_state.handNumber}'),
                          card: entry.value,
                          isFaceUp: showHoleCards,
                          small: true,
                        ),
                      );
                    }).toList(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isDealer)
                        Container(
                          margin: const EdgeInsets.only(right: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            'D',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          player.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${player.chips}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const Text(
                    'CHIPS',
                    style: TextStyle(fontSize: 8, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComicCutsceneOverlay(String bannerText) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD32F2F), Color(0xFFFF8F00)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.yellowAccent, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 16, spreadRadius: 4)
          ],
        ),
        child: Text(
          bannerText,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControlBar(bool isHeroTurn) {
    final hero = _state.players.first;
    final toCall = _state.callAmountForCurrentPlayer;
    final maxTotalBet = hero.currentRoundBet + hero.chips;
    final minRaiseTarget = min(_state.minRaiseTargetBet, maxTotalBet);
    final canRaise = maxTotalBet > _state.currentHighestBet;

    if (_state.street == Street.showdown) {
      return Container(
        height: 50,
        color: const Color(0xFF171E29),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              ),
              onPressed: _startNewHand,
              icon: const Icon(Icons.play_arrow),
              label: const Text(
                '다음 핸드 시작 (Next Hand)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 50,
      color: const Color(0xFF171E29),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: isHeroTurn
                ? () => _onPlayerAction(
                      const PlayerAction(
                          playerId: 'hero', type: ActionType.fold),
                    )
                : null,
            child: const Text('FOLD',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: isHeroTurn
                ? () => _onPlayerAction(
                      PlayerAction(
                        playerId: 'hero',
                        type: toCall == 0 ? ActionType.check : ActionType.call,
                      ),
                    )
                : null,
            child: Text(
              toCall == 0 ? 'CHECK' : 'CALL ($toCall)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          if (canRaise) ...[
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.amber,
                  thumbColor: Colors.amberAccent,
                ),
                child: Slider(
                  value: _raiseSliderValue.clamp(
                      minRaiseTarget.toDouble(), maxTotalBet.toDouble()),
                  min: minRaiseTarget.toDouble(),
                  max: max(minRaiseTarget.toDouble(), maxTotalBet.toDouble()),
                  divisions: max(1, maxTotalBet - minRaiseTarget),
                  onChanged: isHeroTurn
                      ? (v) => setState(() => _raiseSliderValue = v)
                      : null,
                ),
              ),
            ),
            TextButton(
              onPressed: isHeroTurn
                  ? () {
                      final halfPot = _state.currentHighestBet +
                          (_state.totalPotAmount ~/ 2);
                      setState(() {
                        _raiseSliderValue = halfPot
                            .clamp(minRaiseTarget, maxTotalBet)
                            .toDouble();
                      });
                    }
                  : null,
              child: const Text('1/2 POT', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: isHeroTurn
                  ? () {
                      final potBet =
                          _state.currentHighestBet + _state.totalPotAmount;
                      setState(() {
                        _raiseSliderValue = potBet
                            .clamp(minRaiseTarget, maxTotalBet)
                            .toDouble();
                      });
                    }
                  : null,
              child: const Text('POT', style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: isHeroTurn
                  ? () {
                      final target = _raiseSliderValue.round();
                      _onPlayerAction(
                        PlayerAction(
                          playerId: 'hero',
                          type: target >= maxTotalBet
                              ? ActionType.allIn
                              : ActionType.raise,
                          amount: target,
                        ),
                      );
                    }
                  : null,
              child: Text(
                _raiseSliderValue.round() >= maxTotalBet
                    ? 'ALL-IN ($maxTotalBet)'
                    : 'RAISE (${_raiseSliderValue.round()})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
