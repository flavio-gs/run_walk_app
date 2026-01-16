import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PointsService {
  final _db = FirebaseFirestore.instance;

  Future<String> _uid() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado');
    return uid;
  }

  /// Debita pontos do user (transacional). Retorna true se debitou.
  Future<bool> spend(
      int amount, {
        required String reason,
        Map<String, dynamic>? meta,
      }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado');

    try {
      await _db.runTransaction((tx) async {
        final userRef = _db.collection('users').doc(uid);
        final userSnap = await tx.get(userRef);
        final data = userSnap.data() ?? {};

        final current = (data['totalPoints'] is num)
            ? (data['totalPoints'] as num).toInt()
            : 0;

        if (current < amount) {
          throw Exception('Pontos insuficientes');
        }

        tx.update(userRef, {
          'totalPoints': current - amount,
          'pointsUpdatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(_db.collection('points_history').doc(), {
          'userId': uid,
          'amount': -amount,
          'reason': reason,
          'meta': meta ?? {},
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      return true;
    } catch (e) {
      return false;
    }
  }


  /// Proteção do território por X horas
  Future<bool> buyProtection({
    required String territoryId,
    required int hours,
    required int cost,
  }) async {
    final uid = await _uid();

    final ok = await spend(
      cost,
      reason: 'territory_protection',
      meta: {'territoryId': territoryId, 'hours': hours},
    );
    if (!ok) return false;

    final until = DateTime.now().add(Duration(hours: hours));

    await _db.collection('territorios').doc(territoryId).set({
      'powerups': {
        'protection': {
          'active': true,
          'until': Timestamp.fromDate(until),
          'byUserId': uid,
          'hours': hours,
        }
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return true;
  }

  /// Aumenta dificuldade por X horas (ex: +1 nível temporário)
  Future<bool> buyDifficultyBoost({
    required String territoryId,
    required int hours,
    required int extraDifficulty,
    required int cost,
  }) async {
    final uid = await _uid();

    final ok = await spend(
      cost,
      reason: 'territory_difficulty_boost',
      meta: {'territoryId': territoryId, 'hours': hours, 'extra': extraDifficulty},
    );
    if (!ok) return false;

    final until = DateTime.now().add(Duration(hours: hours));

    await _db.collection('territorios').doc(territoryId).set({
      'powerups': {
        'difficultyBoost': {
          'active': true,
          'until': Timestamp.fromDate(until),
          'byUserId': uid,
          'extraDifficulty': extraDifficulty,
          'hours': hours,
        }
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return true;
  }
}
