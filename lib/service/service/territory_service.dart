import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import '../../widgets/achievement_overlay.dart';

enum TerritoryBlockReason { protected, insufficientProgress }

class TerritoryBlockNotice {
  final String territoryId;
  final TerritoryBlockReason reason;
  final double progress;          // 0..1
  final double requiredThreshold; // 0..1
  final DateTime? protectionUntil;

  TerritoryBlockNotice({
    required this.territoryId,
    required this.reason,
    required this.progress,
    required this.requiredThreshold,
    this.protectionUntil,
  });
}

class TerritoryDominanceResult {
  final int capturedCount;
  final List<TerritoryBlockNotice> blocked;

  TerritoryDominanceResult({required this.capturedCount, required this.blocked});
}

class TerritoryService {
  final _firestore = FirebaseFirestore.instance;
  final _achievements = AchievementService();

  /// Raio máximo (m) para considerar que o jogador passou por um ponto
  static const double proximityThreshold = 30.0;

  /// Percentual mínimo de pontos do território para considerar domínio parcial
  static const double partialThreshold = 0.6;

  DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  /// Retorna until se o powerup existir, ativo, e ainda válido
  DateTime? _powerupUntil(Map<String, dynamic> powerups, String key) {
    final m = powerups[key];
    if (m is! Map) return null;
    if (m['active'] != true) return null;
    final until = _tsToDate(m['until']);
    if (until == null) return null;
    if (!until.isAfter(DateTime.now())) return null;
    return until;
  }

  bool _isPowerupActive(Map<String, dynamic> powerups, String key) {
    return _powerupUntil(powerups, key) != null;
  }

  /// Exemplo de aumento de dificuldade:
  /// +10% por nível extra (clamp até 0.95)
  double _applyDifficultyBoost({
    required double baseThreshold,
    required Map<String, dynamic> powerups,
  }) {
    final m = powerups['difficultyBoost'];
    if (m is! Map) return baseThreshold;

    final active = (m['active'] == true);
    final until = _tsToDate(m['until']);
    if (!active || until == null || !until.isAfter(DateTime.now())) return baseThreshold;

    final extra = (m['extraDifficulty'] is num) ? (m['extraDifficulty'] as num).toInt() : 0;

    final boosted = baseThreshold + (0.10 * extra);
    return boosted.clamp(baseThreshold, 0.95);
  }

  /// Verifica se o jogador dominou (total ou parcialmente) algum território durante a corrida
  Future<TerritoryDominanceResult> checkTerritoryDominance({
    required String userId,
    required double pace,
    required List<Map<String, double>> route,
    BuildContext? context,
    String? runId,
    double? distance,
    int? duration,
    int? calories,
    String? activeDisputeTerritoryId,
    Future<void> Function({
    required String territoryId,
    required String oldUserId,
    required String newUserId,
    required double progress,
    })? onTerritoryCaptured,
  }) async {
    final snapshot = await _firestore.collection('territorios').get();

    int capturedCount = 0;

    // ✅ lista de bloqueios (pra você mostrar a msg no _saveRun)
    final List<TerritoryBlockNotice> blocked = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final List points = data['points'] ?? [];
      if (points.isEmpty) continue;

      // 🔹 Conta quantos pontos foram percorridos
      final pointsPassed = points
          .where((p) => _passedNearPoint(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
        route,
        proximityThreshold,
      ))
          .length;

      final progress = pointsPassed / points.length;

      // powerups
      final powerupsRaw = data['powerups'];
      final powerups = (powerupsRaw is Map)
          ? Map<String, dynamic>.from(powerupsRaw as Map)
          : <String, dynamic>{};

      final requiredThreshold = _applyDifficultyBoost(
        baseThreshold: partialThreshold,
        powerups: powerups,
      );

      // ✅ Não bateu o threshold (já com boost)
      if (progress < requiredThreshold) {
        blocked.add(TerritoryBlockNotice(
          territoryId: doc.id,
          reason: TerritoryBlockReason.insufficientProgress,
          progress: progress,
          requiredThreshold: requiredThreshold,
        ));
        continue;
      }

      final oldUserId = (data['userId'] ?? '').toString();

      // ✅ Se existe disputa ativa, só permite capturar aquele território
      if (activeDisputeTerritoryId != null && doc.id != activeDisputeTerritoryId) {
        continue;
      }

      // ✅ Se já é seu, ignora
      if (oldUserId == userId) continue;

      // ✅ proteção (só bloqueia se tiver DONO)
      final protectionActive = _isPowerupActive(powerups, 'protection');
      final protectionUntil = _powerupUntil(powerups, 'protection');

      if (protectionActive && oldUserId.isNotEmpty) {
        blocked.add(TerritoryBlockNotice(
          territoryId: doc.id,
          reason: TerritoryBlockReason.protected,
          progress: progress,
          requiredThreshold: requiredThreshold,
          protectionUntil: protectionUntil,
        ));
        continue;
      }

      // ✅ TERRITÓRIO SEM DONO -> claim permitido mesmo com proteção
      if (oldUserId.isEmpty) {
        await _claimUnownedTerritory(
          territoryId: doc.id,
          newUserId: userId,
          progress: progress,
          context: context,
        );

        capturedCount++;

        if (onTerritoryCaptured != null) {
          await onTerritoryCaptured(
            territoryId: doc.id,
            oldUserId: '',
            newUserId: userId,
            progress: progress,
          );
        }

        continue;
      }

      // ✅ TERRITÓRIO COM DONO -> disputa por pace
      double oldUserPace = double.infinity;
      try {
        final oldUserDoc = await _firestore.collection('users').doc(oldUserId).get();
        final raw = oldUserDoc.data()?['bestPace'];
        oldUserPace = (raw is num) ? raw.toDouble() : double.infinity;
      } catch (_) {}

      // 🔥 Se for mais rápido, domina
      if (pace < oldUserPace) {
        await _transferTerritory(
          doc.id,
          oldUserId,
          userId,
          progress,
          context: context,
        );

        capturedCount++;

        if (onTerritoryCaptured != null) {
          await onTerritoryCaptured(
            territoryId: doc.id,
            oldUserId: oldUserId,
            newUserId: userId,
            progress: progress,
          );
        }
      }
    }

    // 🧩 Dispara conquistas após as capturas
    if (capturedCount > 0) {
      await _achievements.checkAchievements(
        runData: {
          'territoriesCaptured': capturedCount,
          'distance': 0.0,
          'pace': pace,
        },
        context: context,
      );
    }

    return TerritoryDominanceResult(capturedCount: capturedCount, blocked: blocked);
  }

  Future<bool> crossedAnyTerritory({
    required List<Map<String, double>> route,
    double threshold = partialThreshold,
  }) async {
    final snapshot = await _firestore.collection('territorios').get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final List points = data['points'] ?? [];
      if (points.isEmpty) continue;

      final pointsPassed = points
          .where((p) => _passedNearPoint(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
        route,
        proximityThreshold,
      ))
          .length;

      final progress = pointsPassed / points.length;
      if (progress >= threshold) return true;
    }

    return false;
  }

  // ============================================================
  // 🆕 Captura nova (território sem dono)
  // ============================================================

  Future<void> _claimUnownedTerritory({
    required String territoryId,
    required String newUserId,
    required double progress,
    BuildContext? context,
  }) async {
    final docRef = _firestore.collection('territorios').doc(territoryId);

    await docRef.set({
      'userId': newUserId,
      'capturedAt': FieldValue.serverTimestamp(),
      'lastProgress': progress,
      'dispute': FieldValue.delete(),
    }, SetOptions(merge: true));

    await docRef.collection('ownership').add({
      'previousOwner': null,
      'newOwner': newUserId,
      'progress': progress,
      'pace': 0,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'claim',
    });

    await _firestore.collection('users').doc(newUserId).set({
      'territories': {
        'capturedCount': FieldValue.increment(1),
        'activeCount': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));

    final xpGanho = (progress * 150).clamp(50, 150).toDouble();
    await _achievements.addXP(
      xpGanho,
      context: context,
      source: 'territory',
      description: progress < 1.0
          ? "Reivindicou novo território (${(progress * 100).toStringAsFixed(0)}%)"
          : "Reivindicou território completo",
    );

    await _postTerritoryToFeed(
      newUserId,
      oldUserId: '',
      title: progress < 1.0
          ? "Reivindicou novo território (${(progress * 100).toStringAsFixed(0)}%)"
          : "Reivindicou novo território completo",
      icon: progress < 1.0 ? "🗺️" : "🏰",
      territoryId: territoryId,
      progress: progress,
    );

    if (context != null && context.mounted) {
      await showAchievementPopup(
        context,
        title: "🆕 Território reivindicado!",
        icon: "📍",
      );
    }

    debugPrint("🆕 Território $territoryId reivindicado por $newUserId");
  }

  // ============================================================
  // ⚙️ Transferência
  // ============================================================

  Future<void> _transferTerritory(
      String territoryId,
      String oldUserId,
      String newUserId,
      double progress, {
        BuildContext? context,
      }) async {
    final docRef = _firestore.collection('territorios').doc(territoryId);
    final snap = await docRef.get();
    final data = snap.data();
    if (data == null) return;

    final now = DateTime.now();

    if (oldUserId.isNotEmpty && data['capturedAt'] != null) {
      final capturedAt = (data['capturedAt'] as Timestamp).toDate();
      final holdMs = now.difference(capturedAt).inMilliseconds;
      await _recordHoldDuration(oldUserId, territoryId, holdMs, context);
    }

    await docRef.update({
      'userId': newUserId,
      'capturedAt': Timestamp.fromDate(now),
      'lastProgress': progress,
      'dispute': FieldValue.delete(),
    });

    await docRef.collection('ownership').add({
      'previousOwner': oldUserId,
      'newOwner': newUserId,
      'progress': progress,
      'pace': data['pace'] ?? 0,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'transfer',
    });

    await _firestore.collection('users').doc(newUserId).set({
      'territories': {
        'capturedCount': FieldValue.increment(1),
        'activeCount': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));

    if (oldUserId.isNotEmpty && oldUserId != newUserId) {
      await _firestore.collection('users').doc(oldUserId).set({
        'territories': {'activeCount': FieldValue.increment(-1)}
      }, SetOptions(merge: true));
    }

    final xpGanho = (progress * 150).clamp(50, 150).toDouble();
    await _achievements.addXP(
      xpGanho,
      context: context,
      source: 'territory',
      description: progress < 1.0
          ? "Dominou parte de um território (${(progress * 100).toStringAsFixed(0)}%)"
          : "Conquistou território completo",
    );

    if (oldUserId.isNotEmpty) {
      await _achievements.removeXPForUser(
        oldUserId,
        xpGanho / 2,
        source: 'territory_loss',
        description: "Perdeu território ($territoryId)",
      );
    }

    await _postTerritoryToFeed(
      newUserId,
      oldUserId: oldUserId,
      title: progress < 1.0
          ? "Dominou parte de um território (${(progress * 100).toStringAsFixed(0)}%)"
          : "Conquistou território completo",
      icon: progress < 1.0 ? "🗺️" : "🏰",
      territoryId: territoryId,
      progress: progress,
    );

    if (context != null && context.mounted) {
      await showAchievementPopup(
        context,
        title: progress < 1.0 ? "🗺️ Domínio parcial!" : "🏆 Território conquistado!",
        icon: progress < 1.0 ? "🗺️" : "📍",
      );
    }

    debugPrint("🏆 Território $territoryId dominado (${(progress * 100).toStringAsFixed(1)}%) por $newUserId");
  }

  // ============================================================
  // 🕒 Hold
  // ============================================================

  Future<void> _recordHoldDuration(
      String oldUserId,
      String territoryId,
      int holdMs,
      BuildContext? context,
      ) async {
    await _achievements.finalizeTerritoryHold(
      territoryId: territoryId,
      territoryName: "Território anterior",
      holdDuration: Duration(milliseconds: holdMs),
      context: context,
    );

    await _firestore.collection('users').doc(oldUserId).collection('territory_history').add({
      'territoryId': territoryId,
      'holdMs': holdMs,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // 📍 Proximidade
  // ============================================================

  bool _passedNearPoint(
      double lat,
      double lng,
      List<Map<String, double>> route,
      double threshold,
      ) {
    for (final r in route) {
      final distance = _calculateDistance(lat, lng, r['lat']!, r['lng']!);
      if (distance <= threshold) return true;
    }
    return false;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * pi / 180;

  // ============================================================
  // 📢 Feed
  // ============================================================

  Future<void> _postTerritoryToFeed(
      String userId, {
        required String title,
        required String icon,
        required String territoryId,
        required String oldUserId,
        required double progress,
      }) async {
    try {
      final newOwnerDoc = await _firestore.collection('users').doc(userId).get();
      final newOwner = newOwnerDoc.data() ?? {};

      Map<String, dynamic> oldOwner = {};
      if (oldUserId.isNotEmpty) {
        final oldOwnerDoc = await _firestore.collection('users').doc(oldUserId).get();
        oldOwner = oldOwnerDoc.data() ?? {};
      }

      final winnerName = (newOwner['displayName'] ?? 'Jogador').toString();
      final winnerPhoto = (newOwner['photoURL'] ?? '').toString();

      final loserName = (oldOwner['displayName'] ?? 'Ninguém').toString();
      final loserPhoto = (oldOwner['photoURL'] ?? '').toString();

      final p = progress.clamp(0.0, 1.0);
      final percent = (p * 100).round();

      final battleTitle = oldUserId.isEmpty
          ? "📍 $winnerName reivindicou um novo território!"
          : (p < 1.0
          ? "⚔️ $winnerName dominou $loserName ($percent%)"
          : "🏰 $winnerName conquistou o território de $loserName!");

      await _firestore.collection('posts').add({
        'type': 'territory',
        'authorId': userId,
        'authorName': winnerName,
        'authorPhoto': winnerPhoto,
        'title': title,
        'icon': icon,
        'territoryId': territoryId,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'commentsCount': 0,
        'text': battleTitle,
        'progress': p,
        'winnerId': userId,
        'winnerName': winnerName,
        'winnerPhoto': winnerPhoto,
        'loserId': oldUserId,
        'loserName': loserName,
        'loserPhoto': loserPhoto,
        'battleTitle': battleTitle,
        'battleType': oldUserId.isEmpty ? 'claim' : (p < 1.0 ? 'partial' : 'full'),
      });

      debugPrint("[Feed] 📢 Postado territory battle: $battleTitle ($icon)");
    } catch (e) {
      debugPrint("[Feed] Falha ao postar território: $e");
    }
  }

  Future<void> showAchievementPopup(
      BuildContext context, {
        required String title,
        required String icon,
      }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => AchievementOverlay(title: title, icon: icon),
    );
  }

  Future<List<Map<String, double>>> extractOutsideRoute({
    required List<Map<String, double>> route,
    double threshold = proximityThreshold,
  }) async {
    final snap = await _firestore.collection('territorios').get();

    final List<Map<String, double>> allTerritoryPoints = [];
    for (final d in snap.docs) {
      final data = d.data();
      final pts = (data['points'] as List? ?? []);
      for (final p in pts) {
        final lat = (p['lat'] as num?)?.toDouble();
        final lng = (p['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          allTerritoryPoints.add({'lat': lat, 'lng': lng});
        }
      }
    }

    bool isNearAnyTerritoryPoint(Map<String, double> r) {
      final rLat = r['lat']!;
      final rLng = r['lng']!;
      for (final tp in allTerritoryPoints) {
        final d = _calculateDistance(rLat, rLng, tp['lat']!, tp['lng']!);
        if (d <= threshold) return true;
      }
      return false;
    }

    return route.where((r) => !isNearAnyTerritoryPoint(r)).toList();
  }
}
