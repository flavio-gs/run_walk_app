import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import '../achievement_service.dart';

class GamificationService {
  static final GamificationService _instance = GamificationService._internal();
  factory GamificationService() => _instance;
  GamificationService._internal();
  bool _bonusDadoHoje = false;


  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// ===========================================================
  /// ⚙️  FUNÇÕES PRINCIPAIS
  /// ===========================================================

  /// Calcula o level e o progresso com base no XP total
  Map<String, dynamic> _levelFromXp(int xp) {
    int level = 1;
    while (xp >= (level * level * 100)) {
      level++;
    }
    level = level > 1 ? level - 1 : 1;
    final int currentLevelXp = level * level * 100;
    final int nextLevelXp = (level + 1) * (level + 1) * 100;
    final double progress = (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);
    return {'level': level, 'progress': progress.clamp(0.0, 1.0), 'nextXp': nextLevelXp};
  }

  /// ===========================================================
  /// 🏆  CÁLCULO AUTOMÁTICO DE PONTOS
  /// ===========================================================

  /// Retorna pontos com base na distância (km)
  int pontosPorCorrida(double km) {
    if (km < 1) return 10;
    if (km < 5) return 25;
    if (km < 10) return 50;
    return 100;
  }

  /// Pontos fixos por tipo de evento
  int pontosPorEvento(String tipo) {
    switch (tipo) {
      case 'login_diario':
        return 5;
      case 'desafio':
        return 100;
      case 'conquista':
        return 200;
      case 'compartilhar':
        return 10;
      default:
        return 0;
    }
  }

  /// Multiplicador para usuários Pro
  Future<double> _getMultiplicadorPro() async {
    final user = _auth.currentUser;
    if (user == null) return 1.0;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    final isPro = (doc.data()?['isPro'] ?? false) as bool;
    return isPro ? 1.2 : 1.0; // +20% de bônus para Pro Runner
  }

  /// ===========================================================
  /// ⚡ ADIÇÃO DE PONTOS (GERAL)
  /// ===========================================================

  Future<void> addPoints({
    required int points,
    required String source, // "Corrida", "Desafio", etc.
    String? description,
    Map<String, dynamic>? meta,
    BuildContext? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    int localPoints = prefs.getInt('pending_points') ?? 0;
    localPoints += points;
    await prefs.setInt('pending_points', localPoints);

    _showSnack(context, "💾 +$points pontos adicionados (offline)");

    // registra no histórico local -> sincroniza depois
    await _savePendingHistory(points, source, description, meta);

    await _trySync(context: context);
  }

  /// ===========================================================
  /// 🏃  CÁLCULO AUTOMÁTICO PARA CORRIDA
  /// ===========================================================

  Future<void> registrarCorrida({
    required double distanciaKm,
    required double calorias,
    required Duration duracao,
    BuildContext? context,
  }) async {
    final pontosBase = pontosPorCorrida(distanciaKm);
    final mult = await _getMultiplicadorPro();
    final pontosFinais = (pontosBase * mult).round();

    final desc = "${distanciaKm.toStringAsFixed(2)} km em ${duracao.inMinutes} min";

    await addPoints(
      points: pontosFinais,
      source: "Corrida",
      description: desc,
      meta: {
        'distanciaKm': distanciaKm,
        'calorias': calorias,
        'duracaoMin': duracao.inMinutes,
      },
      context: context,
    );
  }

  /// ===========================================================
  /// ☁️ SINCRONIZAÇÃO COM FIRESTORE
  /// ===========================================================

  Future<void> _trySync({BuildContext? context}) async {
    debugPrint("🔍 Tentando sincronizar pontos pendentes...");
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    final prefs = await SharedPreferences.getInstance();
    int pendingPoints = prefs.getInt('pending_points') ?? 0;
    if (pendingPoints <= 0) return;

    final user = _auth.currentUser;
    if (user == null) return;
    final userRef = _firestore.collection('users').doc(user.uid);

    try {
      final snap = await userRef.get();
      if (!snap.exists) {
        await userRef.set({
          'totalPoints': 0,
          'xp': 0,
          'level': 1,
          'levelProgress': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // incrementa pontos + xp
      await userRef.set({
        'totalPoints': FieldValue.increment(pendingPoints),
        'xp': FieldValue.increment(pendingPoints),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // recalcula level
      final updated = await userRef.get();
      final int xp = (updated.data()?['xp'] ?? 0) as int;
      final levelInfo = _levelFromXp(xp);

      await userRef.set({
        'level': levelInfo['level'],
        'levelProgress': levelInfo['progress'],
        'nextXp': levelInfo['nextXp'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await prefs.setInt('pending_points', 0);

      _showSnack(context, "✅ Pontos/XP sincronizados (+$pendingPoints)!");
    } catch (e) {
      debugPrint("Erro ao sincronizar pontos/xp: $e");
    }
    debugPrint("💰 Sincronizando +$pendingPoints pontos (pending_points detectado).");

  }

  /// ===========================================================
  /// 🔥 COMBO DIÁRIO (STREAK)
  /// ===========================================================

  /// Registra um bônus diário (login ou corrida)
  Future<void> registrarBonusDiario({BuildContext? context}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // ✅ Proteção global em memória — impede rodar de novo até reiniciar o app
    if (_bonusDadoHoje) {
      debugPrint("⚠️ Bônus diário já processado nesta sessão (proteção de memória).");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString('last_daily_bonus');
    final today = DateTime.now();

    DateTime? lastDate;
    if (lastDateStr != null) {
      try {
        lastDate = DateTime.parse(lastDateStr);
      } catch (_) {}
    }

    int streak = prefs.getInt('daily_streak') ?? 0;
    bool ganhouHoje = false;

    if (lastDate != null) {
      final diff = today.difference(lastDate).inDays;

      if (diff == 0) {
        // já ganhou hoje
        ganhouHoje = true;
      } else if (diff == 1) {
        // manteve sequência
        streak++;
      } else {
        // perdeu sequência
        streak = 1;
      }
    } else {
      streak = 1;
    }

    if (ganhouHoje) {
      _bonusDadoHoje = true; // 🔒 trava em memória
      debugPrint("⏳ Bônus diário já concedido hoje");
      return;
    }

// Proteção extra: evita duplicar bônus no mesmo minuto (ex: hot reload)
    final lastGivenStr = prefs.getString('last_bonus_timestamp');
    if (lastGivenStr != null) {
      final lastGiven = DateTime.tryParse(lastGivenStr);
      if (lastGiven != null &&
          DateTime.now().difference(lastGiven).inSeconds < 60) {
        debugPrint("⚠️ Ignorando repetição de bônus em menos de 60s (possível hot reload)");
        return;
      }
    }
    await prefs.setString('last_bonus_timestamp', DateTime.now().toIso8601String());




    // salva o último dia
    await prefs.setString('last_daily_bonus', today.toIso8601String());
    _bonusDadoHoje = true; // ✅ garante que não será repetido enquanto o app estiver aberto
    await prefs.setInt('daily_streak', streak);

    // calcula bônus baseado no streak
    int pontosBase;
    if (streak >= 5) {
      pontosBase = 25;
    } else {
      pontosBase = 5 * streak;
    }

    // aplica multiplicador se for Pro
    final mult = await _getMultiplicadorPro();
    final pontosFinais = (pontosBase * mult).round();

    final desc = "Dia $streak de sequência diária";

    await addPoints(
      points: pontosFinais,
      source: "Login Diário",
      description: desc,
      context: context,
    );

    // 🏆 Após conceder o bônus, verifica conquistas de streak
    try {
      await AchievementService().checkAchievements(
        runData: {'streak': streak},
        context: context,
      );
    } catch (e) {
      debugPrint("[Gamification] Erro ao checar conquistas de streak: $e");
    }

    _showSnack(
      context,
      "🔥 Combo diário ${streak}x! +$pontosFinais pontos",
    );

  }

  /// Retorna o status atual da sequência
  Future<Map<String, dynamic>> getStatusStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString('last_daily_bonus');
    final streak = prefs.getInt('daily_streak') ?? 0;

    DateTime? lastDate;
    if (lastDateStr != null) {
      try {
        lastDate = DateTime.parse(lastDateStr);
      } catch (_) {}
    }

    return {
      'streak': streak,
      'lastDate': lastDate,
      'isToday': lastDate != null &&
          DateTime.now().difference(lastDate).inDays == 0,
    };
  }


  /// ===========================================================
  /// 🧾 HISTÓRICO DE PONTOS
  /// ===========================================================

  Future<void> _savePendingHistory(
      int points, String source, String? description, Map<String, dynamic>? meta) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingHistory = prefs.getStringList('pending_history') ?? [];

    final entry = jsonEncode({
      'points': points,
      'source': source,
      'description': description,
      'meta': meta,
      'createdAt': DateTime.now().toIso8601String(),
    });

    pendingHistory.add(entry);
    await prefs.setStringList('pending_history', pendingHistory);

    await _syncHistory(); // tenta enviar
  }

  Future<void> _syncHistory() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    final prefs = await SharedPreferences.getInstance();
    final pendingHistory = prefs.getStringList('pending_history') ?? [];
    if (pendingHistory.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;
    final ref = _firestore.collection('users').doc(user.uid).collection('pointsHistory');

    for (final h in pendingHistory) {
      try {
        final data = jsonDecode(h);
        await ref.add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("Erro ao salvar histórico: $e");
      }
    }

    await prefs.setStringList('pending_history', []);
  }

  /// Retorna histórico
  Future<List<Map<String, dynamic>>> getPointsHistory({
    String? userId,
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null) return [];

    Query q = _firestore
        .collection('users')
        .doc(uid)
        .collection('pointsHistory')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      q = (q as Query<Map<String, dynamic>>).startAfterDocument(startAfter);
    }

    final snap = await q.get();

    return snap.docs.map((d) {
      final raw = d.data();
      if (raw == null) return <String, dynamic>{};
      final m = Map<String, dynamic>.from(raw as Map);
      m['id'] = d.id;
      return m;
    }).toList();
  }

  /// ===========================================================
  /// 🔸 UTILITÁRIOS
  /// ===========================================================

  Future<int> getTotalPoints({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getInt('pending_points') ?? 0;
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null) return pending;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();

      if (data == null) return pending;

      // 🔹 Lê como num e converte para int de forma segura
      final num total = (data['totalPoints'] ?? 0);
      final int totalPoints = total.toInt();

      final isCurrent = uid == _auth.currentUser?.uid;
      return totalPoints + (isCurrent ? pending : 0);
    } catch (e) {
      debugPrint("⚠️ Erro ao carregar totalPoints: $e");
      return (uid == _auth.currentUser?.uid) ? pending : 0;
    }
  }


  Future<void> syncNow({BuildContext? context}) async => await _trySync(context: context);

  void _showSnack(BuildContext? context, String message) {
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
