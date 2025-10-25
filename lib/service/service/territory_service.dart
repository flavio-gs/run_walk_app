import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import '../../widgets/achievement_overlay.dart';

class TerritoryService {
  final _firestore = FirebaseFirestore.instance;

  /// Raio máximo de tolerância (em metros) para considerar que passou por um ponto
  static const double proximityThreshold = 30.0;

  /// Verifica se o jogador dominou algum território durante a corrida
  Future<void> checkTerritoryDominance({
    required String userId,
    required double pace,
    required List<Map<String, double>> route,
    BuildContext? context,
  }) async {
    final snapshot = await _firestore.collection('territorios').get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final List points = data['points'] ?? [];
      if (points.isEmpty) continue;

      // ✅ Verifica se passou por todos os pontos
      bool passedAllPoints = points.every((p) =>
          _passedNearPoint(p['lat'], p['lng'], route, proximityThreshold));

      if (!passedAllPoints) continue;

      // ✅ Verifica se o pace é melhor que o do dono atual
      final oldUserId = data['userId'];
      if (oldUserId == userId) continue; // já é dono, ignora

      double oldUserPace = double.infinity;
      try {
        final oldUserDoc =
        await _firestore.collection('users').doc(oldUserId).get();
        oldUserPace =
        (oldUserDoc.data()?['bestPace'] ?? double.infinity) as double;
      } catch (_) {}

      // 🔥 Domina se for mais rápido (menor pace)
      if (pace < oldUserPace) {
        await _transferTerritory(
          doc.id,
          oldUserId,
          userId,
          context: context,
        );
      }
    }
  }

  /// Verifica se um ponto da corrida passou próximo de outro ponto (dentro do raio)
  bool _passedNearPoint(
      double lat, double lng, List<Map<String, double>> route, double threshold) {
    for (final r in route) {
      final distance = _calculateDistance(lat, lng, r['lat']!, r['lng']!);
      if (distance <= threshold) return true;
    }
    return false;
  }

  /// Fórmula de Haversine (distância entre dois pontos em metros)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
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

  /// Faz a transferência de domínio entre jogadores
  Future<void> _transferTerritory(
      String territoryId,
      String oldUserId,
      String newUserId, {
        BuildContext? context,
      }) async {
    final doc =
    await _firestore.collection('territorios').doc(territoryId).get();
    final data = doc.data();
    if (data == null) return;

    // 🗑️ Remove o antigo território
    await _firestore.collection('territorios').doc(territoryId).delete();

    // 🆕 Cria o novo território com o novo dono
    await _firestore.collection('territorios').add({
      'points': data['points'],
      'userId': newUserId,
      'capturedAt': FieldValue.serverTimestamp(),
    });

    // 🧩 Atualiza XP
    final achievements = AchievementService();

    // Novo dono ganha XP
    await achievements.addXP(
      150,
      context: context,
      source: 'territory',
      description: "Conquistou território",
    );

    // Antigo dono perde XP
    await achievements.removeXP(
      150,
      source: 'territory_loss',
      description: "Perdeu território",
    );

    // 🎉 Feedback visual
    if (context != null && context.mounted) {
      await showAchievementPopup(
        context,
        title: "🏆 Território conquistado!",
        icon: "📍",
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Você dominou um novo território!"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }

    debugPrint("🏆 Território $territoryId dominado por $newUserId!");
  }
}

/// Exibe popup animado de conquista
Future<void> showAchievementPopup(BuildContext context,
    {required String title, required String icon}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (_) => AchievementOverlay(title: title, icon: icon),
  );
}
