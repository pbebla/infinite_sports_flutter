import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Where prediction data lives for the match being rendered: a tournament
/// (Tournaments/{tid}/...) or a league season ({sport}/{season}/...).
/// The reused prediction widgets (PredictTab, PredictionRoomPage, the
/// MatchFactsTab teaser) call through this seam, so league matches reuse
/// them without forking (League Experience P3, P2 adapt-then-reuse).
abstract class PredictionScope {
  const PredictionScope();

  /// Tournament-wide / season-wide default questions.
  Stream<List<PredictionQuestion>> watchDefaultQuestions();

  /// Extra questions attached to this one match.
  Stream<List<PredictionQuestion>> watchMatchQuestions(TournamentMatch match);

  /// Owner-resolved results for custom questions: {qid: optionId}.
  Stream<Map<String, String>> watchMatchResults(TournamentMatch match);

  /// The signed-in fan's answers for this match: {qid: answer}.
  Stream<Map<String, QuestionAnswer>> watchMyMatchAnswers(
      TournamentMatch match, String uid);

  Future<void> submitAnswer(TournamentMatch match, String uid, String qid,
      String value, int nowMs);

  Stream<List<LeaderboardEntry>> watchLeaderboard();
}

/// Today's behavior, unchanged: delegates to the TournamentService statics
/// with match.id as the storage key.
class TournamentPredictionScope extends PredictionScope {
  final String tournamentId;
  const TournamentPredictionScope(this.tournamentId);

  @override
  Stream<List<PredictionQuestion>> watchDefaultQuestions() =>
      TournamentService.watchTournamentQuestions(tournamentId);

  @override
  Stream<List<PredictionQuestion>> watchMatchQuestions(TournamentMatch match) =>
      TournamentService.watchMatchQuestions(tournamentId, match.id);

  @override
  Stream<Map<String, String>> watchMatchResults(TournamentMatch match) =>
      TournamentService.watchMatchResults(tournamentId, match.id);

  @override
  Stream<Map<String, QuestionAnswer>> watchMyMatchAnswers(
          TournamentMatch match, String uid) =>
      TournamentService.watchMyMatchAnswers(tournamentId, match.id, uid);

  @override
  Future<void> submitAnswer(TournamentMatch match, String uid, String qid,
          String value, int nowMs) =>
      TournamentService.submitAnswer(
          tournamentId, match.id, uid, qid, value, nowMs);

  @override
  Stream<List<LeaderboardEntry>> watchLeaderboard() =>
      TournamentService.watchLeaderboard(tournamentId);
}

/// League matches: the adapted TournamentMatch carries the league game id
/// '{dateKey}#{index}' — mapped here onto the league RTDB paths. Malformed
/// ids (never expected from the P2 adapters) degrade to empty streams and
/// a no-op submit, so the widgets render but never write garbage.
class LeaguePredictionScope extends PredictionScope {
  final String sport;
  final String season;
  const LeaguePredictionScope({required this.sport, required this.season});

  ({String dateKey, int index})? _ref(TournamentMatch match) =>
      parseLeagueGameId(match.id);

  @override
  Stream<List<PredictionQuestion>> watchDefaultQuestions() =>
      LeagueService.watchSeasonQuestions(sport, season);

  @override
  Stream<List<PredictionQuestion>> watchMatchQuestions(TournamentMatch match) {
    final ref = _ref(match);
    if (ref == null) return Stream.value(const <PredictionQuestion>[]);
    return LeagueService.watchGameQuestions(
        sport, season, ref.dateKey, ref.index);
  }

  @override
  Stream<Map<String, String>> watchMatchResults(TournamentMatch match) {
    final ref = _ref(match);
    if (ref == null) return Stream.value(const <String, String>{});
    return LeagueService.watchGameResults(sport, season, ref.dateKey, ref.index);
  }

  @override
  Stream<Map<String, QuestionAnswer>> watchMyMatchAnswers(
      TournamentMatch match, String uid) {
    final ref = _ref(match);
    if (ref == null) return Stream.value(const <String, QuestionAnswer>{});
    return LeagueService.watchMyGameAnswers(
        sport, season, ref.dateKey, ref.index, uid);
  }

  @override
  Future<void> submitAnswer(TournamentMatch match, String uid, String qid,
      String value, int nowMs) {
    final ref = _ref(match);
    if (ref == null) return Future.value();
    return LeagueService.submitAnswer(
        sport, season, ref.dateKey, ref.index, uid, qid, value, nowMs);
  }

  @override
  Stream<List<LeaderboardEntry>> watchLeaderboard() =>
      LeagueService.watchLeaderboard(sport, season);
}
