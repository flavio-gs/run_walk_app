import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/service/achievement_service.dart';

/// 🔹 Serviço responsável por armazenar e sincronizar corridas e XP offline no Wear OS.
class WearOfflineSyncService {
  static const String _pendingRunsKey = 'pending_runs_wear';
  static const String _pendingXpKey = 'pending_xp_wear';

  /// 🔸 Salva corrida localmente (modo offline)
  static Future<void> saveRunOffline({
    required double distance,
    required double calories,
    required int timeSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final runs = prefs.getStringList(_pendingRunsKey) ?? [];

    final run = jsonEncode({
      'distancia_m': distance,
      'tempo_s': timeSeconds,
      'kcal': calories,
      'data': DateTime.now().toIso8601String(),
    });

    runs.add(run);
    await prefs.setStringList(_pendingRunsKey, runs);

    // 🔹 Salva XP estimado localmente (1 XP a cada 100 m percorridos)
    final totalXp = prefs.getDouble(_pendingXpKey) ?? 0.0;
    final double xpEarned = distance / 100;
    await prefs.setDouble(_pendingXpKey, totalXp + xpEarned);

    // Log local
    print("⌚ Corrida salva offline (${(distance / 1000).toStringAsFixed(2)} km)");
  }

  /// 🔸 Sincroniza corridas e XP quando estiver online
  static Future<void> syncPendingData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("⚠️ Nenhum usuário logado — adiando sincronização Wear.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final List<String> runs = prefs.getStringList(_pendingRunsKey) ?? [];

    // 🔹 Sincroniza corridas armazenadas
    if (runs.isNotEmpty) {
      print("⌚ Sincronizando ${runs.length} corrida(s) do Wear...");
      for (final runStr in runs) {
        try {
          final run = jsonDecode(runStr);

          final double distanciaM = (run['distancia_m'] ?? 0.0).toDouble();
          final double distanciaKm = distanciaM / 1000;
          final double calorias = (run['kcal'] ?? 0.0).toDouble();
          final int tempoS = (run['tempo_s'] ?? 0).toInt();

          // 🔹 Salva no Firestore (corridas)
          await FirebaseFirestore.instance.collection('corridas').add({
            'userId': user.uid,
            'distancia_m': distanciaM,
            'tempo_s': tempoS,
            'kcal': calorias,
            'data': run['data'],
            'createdAt': FieldValue.serverTimestamp(),
            'source': 'wear',
          });

          // 🔹 Adiciona pontos/XP ao sistema de gamificação
          await GamificationService().registrarCorrida(
            distanciaKm: distanciaKm,
            calorias: calorias,
            duracao: Duration(seconds: tempoS),
          );
        } catch (e) {
          print("❌ Erro ao sincronizar corrida offline: $e");
        }
      }

      await prefs.remove(_pendingRunsKey);
    }

    // 🔹 Sincroniza XP acumulado separadamente
    await _syncPendingXp();

    // 🔹 Recalcula conquistas e níveis
    try {
      await AchievementService().syncNow();
      await GamificationService().syncNow();
    } catch (e) {
      print("⚠️ Erro ao recalcular conquistas/pontos: $e");
    }

    print("✅ Sincronização offline (Wear) concluída!");
  }

  /// 🔸 Envia XP acumulado offline (caso não haja corridas pendentes)
  static Future<void> _syncPendingXp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final double pendingXp = prefs.getDouble(_pendingXpKey) ?? 0.0;
    if (pendingXp == 0) return;

    final double distanciaEquivalenteKm = pendingXp / 10; // proporcional
    print("⌚ Sincronizando XP acumulado do Wear: +${pendingXp.toStringAsFixed(1)} XP");

    await GamificationService().addPoints(
      points: pendingXp.round(),
      source: "Wear Offline",
      description:
      "XP acumulado offline no relógio (${distanciaEquivalenteKm.toStringAsFixed(2)} km)",
    );

    await prefs.remove(_pendingXpKey);
  }
}
