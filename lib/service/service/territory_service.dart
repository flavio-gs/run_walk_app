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
      final pointsPassed = points.where((p) =>
          _passedNearPoint(p['lat'], p['lng'], route, proximityThreshold)
      ).length;

      final progress = pointsPassed / points.length;
      if (progress < partialThreshold) continue;

      final oldUserId = (data['userId'] ?? '') as String;
      if (oldUserId.isEmpty) continue;
      if (oldUserId == userId) continue;

      double oldUserPace = double.infinity;
      try {
        final oldUserDoc = await _firestore
            .collection('users')
            .doc(oldUserId)
            .get();
        final raw = oldUserDoc.data()?['bestPace'];
        oldUserPace = (raw is num) ? raw.toDouble() : double.infinity;
      } catch (_) {}

      // ✅ Se existe disputa ativa, só permite capturar aquele território
      if (activeDisputeTerritoryId != null &&
          doc.id != activeDisputeTerritoryId) {
        continue;
      }

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
          'territoriesCaptured': 0,
          // força buscar users/{uid}.territories.capturedCount
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

      final pointsPassed = points.where((p) =>
          _passedNearPoint(p['lat'], p['lng'], route, proximityThreshold)
      ).length;

      final progress = pointsPassed / points.length;
      if (progress >= threshold) {
        return true; // ✅ cruzou território existente o bastante
      }
    }

    return false;
  }


  // ============================================================
  // ⚙️ Lógica de domínio e transferência
  // ============================================================

  Future<void> _transferTerritory(String territoryId,
      String oldUserId,
      String newUserId,
      double progress, {
        BuildContext? context,
      }) async {
    final docRef = _firestore.collection('territorios').doc(territoryId);
    final data = (await docRef.get()).data();
    if (data == null) return;

    final now = DateTime.now();

    // 🕒 Calcula duração do domínio anterior
    DateTime? capturedAt;
    if (data['capturedAt'] != null) {
      capturedAt = (data['capturedAt'] as Timestamp).toDate();
    }

    int holdMs = 0;
    if (capturedAt != null) {
      holdMs = now
          .difference(capturedAt)
          .inMilliseconds;
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
    });

    // ✅ agrega pro novo dono
    await _firestore.collection('users').doc(newUserId).set({
      'territories': {
        'capturedCount': FieldValue.increment(1),
        'activeCount': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));

// ✅ reduz do antigo dono (activeCount)
    await _firestore.collection('users').doc(oldUserId).set({
      'territories': {
        'activeCount': FieldValue.increment(-1),
      }
    }, SetOptions(merge: true));


    // 🧩 XP dinâmico conforme domínio parcial
    final xpGanho = (progress * 150)
        .clamp(50, 150)
        .toDouble(); // entre 50 e 150 XP
    await _achievements.addXP(
      xpGanho,
      context: context,
      source: 'territory',
      description: progress < 1.0
          ? "Dominou parte de um território (${(progress * 100).toStringAsFixed(
          0)}%)"
          : "Conquistou território completo",
    );


    await _achievements.removeXPForUser(
      oldUserId,
      xpGanho / 2,
      source: 'territory_loss',
      description: "Perdeu território ($territoryId)",
      // context NÃO passa aqui porque é o usuário logado (newOwner), não o oldOwner
    );


    // 📢 Feed público
    await _postTerritoryToFeed(
      newUserId,
      oldUserId: oldUserId,
      title: progress < 1.0
          ? "Dominou parte de um território (${(progress * 100).toStringAsFixed(
          0)}%)"
          : "Conquistou território completo",
      icon: progress < 1.0 ? "🗺️" : "🏰",
      territoryId: territoryId,
      progress: progress,
    );


    // 🎉 Pop-up visual
    if (context != null && context.mounted) {
      await showAchievementPopup(
        context,
        title: progress < 1.0
            ? "🗺️ Domínio parcial!"
            : "🏆 Território conquistado!",
        icon: progress < 1.0 ? "🗺️" : "📍",
      );
    }

    debugPrint(
      "🏆 Território $territoryId dominado (${(progress * 100).toStringAsFixed(
          1)}%) por $newUserId",
    );
  }

  // ============================================================
  // 🕒 Controle de tempo de domínio
  // ============================================================

  Future<void> _recordHoldDuration(String oldUserId,
      String territoryId,
      int holdMs,
      BuildContext? context,) async {
    // 🔹 Atualiza recorde global do usuário
    await _achievements.finalizeTerritoryHold(
      territoryId: territoryId,
      territoryName: "Território anterior",
      holdDuration: Duration(milliseconds: holdMs),
      context: context,
    );

    // 🔹 Salva duração no histórico
    await _firestore
        .collection('users')
        .doc(oldUserId)
        .collection('territory_history')
        .add({
      'territoryId': territoryId,
      'holdMs': holdMs,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // 📍 Verificação de proximidade (Haversine)
  // ============================================================

  bool _passedNearPoint(double lat, double lng, List<Map<String, double>> route,
      double threshold) {
    for (final r in route) {
      final distance = _calculateDistance(lat, lng, r['lat']!, r['lng']!);
      if (distance <= threshold) return true;
    }
    return false;
  }

  double _calculateDistance(double lat1, double lon1, double lat2,
      double lon2) {
    const R = 6371000; // raio da Terra em metros
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * pi / 180;

  // ============================================================
  // 📢 Feed público de territórios
  // ============================================================

  // ============================================================
// 📢 Feed público de territórios (com winner/loser e text)
// ============================================================
  Future<void> _postTerritoryToFeed(String userId, {
    required String title,
    required String icon,
    required String territoryId,

    // ✅ NOVO
    required String oldUserId,
    required double progress,
  }) async {
    try {
      // winner (novo dono)
      final newOwnerDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get();
      final newOwner = newOwnerDoc.data() ?? {};

      // loser (antigo dono)
      final oldOwnerDoc = await _firestore
          .collection('users')
          .doc(oldUserId)
          .get();
      final oldOwner = oldOwnerDoc.data() ?? {};

      final winnerName = (newOwner['displayName'] ?? 'Jogador').toString();
      final winnerPhoto = (newOwner['photoURL'] ?? '').toString();

      final loserName = (oldOwner['displayName'] ?? 'Jogador').toString();
      final loserPhoto = (oldOwner['photoURL'] ?? '').toString();

      final p = progress.clamp(0.0, 1.0);
      final percent = (p * 100).round();

      // 🎮 Texto gamer “VS”
      final battleTitle = p < 1.0
          ? "⚔️ $winnerName dominou $loserName ($percent%)"
          : "🏰 $winnerName conquistou o território de $loserName!";

      await _firestore.collection('posts').add({
        // mantém o type atual pra já aparecer no seu feed
        'type': 'territory',

        // ✅ campos padrão do seu feed
        'authorId': userId,
        'authorName': winnerName,
        'authorPhoto': winnerPhoto,

        'title': title,
        'icon': icon,
        'territoryId': territoryId,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'commentsCount': 0,

        // ✅ MUITO IMPORTANTE: evita post “sem nada escrito”
        // seu card usa caption: data['text']
        'text': battleTitle,

        // ✅ extras pro card VS futuramente
        'progress': p,
        'winnerId': userId,
        'winnerName': winnerName,
        'winnerPhoto': winnerPhoto,

        'loserId': oldUserId,
        'loserName': loserName,
        'loserPhoto': loserPhoto,

        // opcional: se quiser usar no layout
        'battleTitle': battleTitle,
        'battleType': p < 1.0 ? 'partial' : 'full',
      });

      debugPrint("[Feed] 📢 Postado territory battle: $battleTitle ($icon)");
    } catch (e) {
      debugPrint("[Feed] Falha ao postar território: $e");
    }
  }


  /// Popup de conquista visual
  Future<void> showAchievementPopup(BuildContext context,
      {required String title, required String icon}) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => AchievementOverlay(title: title, icon: icon),
    );
  }
}
