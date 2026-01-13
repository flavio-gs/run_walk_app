import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import '../../widgets/achievement_overlay.dart';

class TerritoryService {
  final _firestore = FirebaseFirestore.instance;
  final _achievements = AchievementService();

  /// Raio máximo (m) para considerar que o jogador passou por um ponto
  static const double proximityThreshold = 30.0;

  /// Percentual mínimo de pontos do território para considerar domínio parcial
  static const double partialThreshold = 0.6;

  /// Verifica se o jogador dominou (total ou parcialmente) algum território durante a corrida
  Future<int> checkTerritoryDominance({
    required String userId,
    required double pace,
    required List<Map<String, double>> route,
    BuildContext? context,
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
      if (progress < partialThreshold) continue;

      final oldUserId = (data['userId'] ?? '').toString();

      // ✅ Se existe disputa ativa, só permite capturar aquele território
      if (activeDisputeTerritoryId != null && doc.id != activeDisputeTerritoryId) {
        continue;
      }

      // ✅ Se já é seu, ignora
      if (oldUserId == userId) continue;

      // ✅ TERRITÓRIO SEM DONO -> captura nova (claim)
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
          'territoriesCaptured': capturedCount, // ✅ agora vai certo
          'distance': 0.0,
          'pace': pace,
        },
        context: context,
      );
    }

    return capturedCount;
  }

  Future<bool> crossedAnyTerritory({
    required List<Map<String, double>> route,
    double threshold = partialThreshold, // 0.6
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
      if (progress >= threshold) {
        return true; // ✅ cruzou território existente o bastante
      }
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

    // ✅ seta dono (merge pra não perder pontos/area/etc)
    await docRef.set({
      'userId': newUserId,
      'capturedAt': FieldValue.serverTimestamp(),
      'lastProgress': progress,
      'dispute': FieldValue.delete(),
    }, SetOptions(merge: true));

    // ✅ histórico (sem previousOwner)
    await docRef.collection('ownership').add({
      'previousOwner': null,
      'newOwner': newUserId,
      'progress': progress,
      'pace': 0,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'claim',
    });

    // ✅ agrega pro novo dono (cria territories se não existir)
    await _firestore.collection('users').doc(newUserId).set({
      'territories': {
        'capturedCount': FieldValue.increment(1),
        'activeCount': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));

    // 🧩 XP dinâmico
    final xpGanho = (progress * 150).clamp(50, 150).toDouble();
    await _achievements.addXP(
      xpGanho,
      context: context,
      source: 'territory',
      description: progress < 1.0
          ? "Reivindicou novo território (${(progress * 100).toStringAsFixed(0)}%)"
          : "Reivindicou território completo",
    );

    // 📢 Feed público (sem loser)
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

    // 🎉 Pop-up visual
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
  // ⚙️ Lógica de domínio e transferência
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

    // 🕒 Calcula duração do domínio anterior (só se tiver capturedAt e oldUserId válido)
    if (oldUserId.isNotEmpty && data['capturedAt'] != null) {
      final capturedAt = (data['capturedAt'] as Timestamp).toDate();
      final holdMs = now.difference(capturedAt).inMilliseconds;
      await _recordHoldDuration(oldUserId, territoryId, holdMs, context);
    }

    // 🔹 Atualiza o território sem deletar (preserva histórico)
    await docRef.update({
      'userId': newUserId,
      'capturedAt': Timestamp.fromDate(now),
      'lastProgress': progress,
      'dispute': FieldValue.delete(), // ✅ encerra a disputa global
    });

    // 🔹 Adiciona registro ao histórico de ownership
    await docRef.collection('ownership').add({
      'previousOwner': oldUserId,
      'newOwner': newUserId,
      'progress': progress,
      'pace': data['pace'] ?? 0,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'transfer',
    });

    // ✅ agrega pro novo dono
    await _firestore.collection('users').doc(newUserId).set({
      'territories': {
        'capturedCount': FieldValue.increment(1),
        'activeCount': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));

    // ✅ reduz do antigo dono (activeCount)
    if (oldUserId.isNotEmpty && oldUserId != newUserId) {
      await _firestore.collection('users').doc(oldUserId).set({
        'territories': {
          'activeCount': FieldValue.increment(-1),
        }
      }, SetOptions(merge: true));
    }

    // 🧩 XP dinâmico conforme domínio parcial
    final xpGanho = (progress * 150).clamp(50, 150).toDouble();
    await _achievements.addXP(
      xpGanho,
      context: context,
      source: 'territory',
      description: progress < 1.0
          ? "Dominou parte de um território (${(progress * 100).toStringAsFixed(0)}%)"
          : "Conquistou território completo",
    );

    // ✅ só remove XP se houver oldUserId
    if (oldUserId.isNotEmpty) {
      await _achievements.removeXPForUser(
        oldUserId,
        xpGanho / 2,
        source: 'territory_loss',
        description: "Perdeu território ($territoryId)",
      );
    }

    // 📢 Feed público
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

    // 🎉 Pop-up visual
    if (context != null && context.mounted) {
      await showAchievementPopup(
        context,
        title: progress < 1.0 ? "🗺️ Domínio parcial!" : "🏆 Território conquistado!",
        icon: progress < 1.0 ? "🗺️" : "📍",
      );
    }

    debugPrint(
      "🏆 Território $territoryId dominado (${(progress * 100).toStringAsFixed(1)}%) por $newUserId",
    );
  }

  // ============================================================
  // 🕒 Controle de tempo de domínio
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
  // 📍 Verificação de proximidade (Haversine)
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
    const R = 6371000; // raio da Terra em metros
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * pi / 180;

  // ============================================================
  // 📢 Feed público de territórios
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
      // winner (novo dono)
      final newOwnerDoc = await _firestore.collection('users').doc(userId).get();
      final newOwner = newOwnerDoc.data() ?? {};

      // loser (antigo dono) — ✅ se oldUserId vazio, não busca
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

      // 🎮 Texto gamer
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

  /// Popup de conquista visual
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

    // carrega todos os pontos de todos territórios
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

    // retorna somente os pontos “fora”
    return route.where((r) => !isNearAnyTerritoryPoint(r)).toList();
  }
}



