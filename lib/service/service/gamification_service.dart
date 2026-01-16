import 'dart:convert';
import 'dart:math';
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
    debugPrint("🧨 [addPoints] +$points source=$source desc=$description");
    debugPrint(StackTrace.current.toString());
    final prefs = await SharedPreferences.getInstance();
    // ✅ evita duplicar o mesmo evento em poucos segundos (hot reload / chamadas repetidas)
    final now = DateTime.now().millisecondsSinceEpoch;
    final dedupeKey = "dedupe_${source}_${description ?? ''}_${points}".hashCode.toString();

    final lastKey = prefs.getString('last_points_key');
    final lastAt = prefs.getInt('last_points_at') ?? 0;

    if (lastKey == dedupeKey && (now - lastAt) < 3000) {
      debugPrint("🛑 [addPoints] Ignorado duplicado (hot reload) key=$dedupeKey");
      return;
    }

    await prefs.setString('last_points_key', dedupeKey);
    await prefs.setInt('last_points_at', now);
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

    // ✅ Atualiza progresso de desafios (runs/km/xp)
    await updateChallengesAfterRun(
      distanciaKm: distanciaKm,
      xpGanho: pontosFinais,
      runCreatedAt: DateTime.now(),
      context: context,
    );

  }


  /// ===========================================================
  /// DESAFIOS DA COMUNIDADE
  /// ===========================================================

  // ✅ PUBLICO (pode chamar do _saveRun)
  Future<void> updateChallengesAfterRun({
    required double distanciaKm,
    required int xpGanho,
    DateTime? runCreatedAt,
    BuildContext? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      debugPrint("📴 Offline: desafio não atualizado agora.");
      return;
    }

    final now = Timestamp.now();

    final snap = await _firestore
        .collection('challenges')
        .where('participants', arrayContains: user.uid)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();

      final Timestamp? start = data['startDate'];
      final Timestamp? end = data['endDate'];

      if (start != null && start.compareTo(now) > 0) continue;
      if (end != null && end.compareTo(now) < 0) continue;

      final List goalsRaw = (data['goals'] as List?) ?? [];
      if (goalsRaw.isEmpty) continue;

      final progressRef = doc.reference.collection('progress').doc(user.uid);

      await _firestore.runTransaction((tx) async {
        final progressSnap = await tx.get(progressRef);

        // ✅ se não tem progress => não entrou no desafio => não conta
        if (!progressSnap.exists) {
          debugPrint("🚫 Ignorando desafio ${doc.id}: progress inexistente.");
          return;
        }

        final progress = Map<String, dynamic>.from(progressSnap.data() as Map);

        // ✅ joinedAt (server) ou joinedAtLocal (fallback)
        Timestamp? joinedAt;
        final j = progress['joinedAt'];
        final jl = progress['joinedAtLocal'];
        if (j is Timestamp) joinedAt = j;
        else if (jl is Timestamp) joinedAt = jl;

        if (joinedAt == null) return;

        // ✅ regra: só conta corridas após entrar
        if (runCreatedAt != null && runCreatedAt.isBefore(joinedAt.toDate())) return;

        final double currentKm = ((progress['km'] as num?) ?? 0).toDouble();
        final int currentRuns = ((progress['runs'] as num?) ?? 0).toInt();
        final int currentXp = ((progress['xp'] as num?) ?? 0).toInt();

        final completedGoalIndexesRaw = (progress['completedGoalIndexes'] as List?) ?? [];
        final completedGoalIndexes = completedGoalIndexesRaw.map((e) => (e as num).toInt()).toSet();

        final newRuns = currentRuns + 1;
        final newKm = currentKm + distanciaKm;
        final newXp = currentXp + xpGanho;

        // ✅ SEM FieldValue dentro do map (use Timestamp)
        final Map<String, dynamic> completedAt =
        Map<String, dynamic>.from((progress['completedAt'] as Map?) ?? {});
        final List<int> newlyCompleted = [];

        final Timestamp stamp = runCreatedAt != null
            ? Timestamp.fromDate(runCreatedAt)
            : Timestamp.now();

        for (int i = 0; i < goalsRaw.length; i++) {
          if (completedGoalIndexes.contains(i)) continue;

          final g = Map<String, dynamic>.from(goalsRaw[i] as Map);
          final metric = (g['metric'] ?? '').toString().toLowerCase();
          final target = ((g['target'] as num?) ?? 0).toDouble();

          bool done = false;
          if (metric == 'runs') done = newRuns >= target;
          else if (metric == 'km') done = newKm >= target;
          else if (metric == 'xp') done = newXp >= target;

          if (done) {
            newlyCompleted.add(i);
            completedGoalIndexes.add(i);
            completedAt[i.toString()] = stamp;
          }
        }

        final bool allDone = completedGoalIndexes.length == goalsRaw.length;

        tx.set(progressRef, {
          'runs': newRuns,
          'km': newKm,
          'xp': newXp,
          'completedGoalIndexes': completedGoalIndexes.toList()..sort(),
          'completedAt': completedAt,
          'isCompleted': allDone,
          'completedAtAll': allDone ? stamp : null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (newlyCompleted.isNotEmpty) {
          debugPrint("🏁 Challenge ${doc.id}: goals concluídas=$newlyCompleted");
        }
      });

      _showSnack(context, "🏁 Progresso de desafio atualizado (+1 corrida)");
    }
  }




  /// ===========================================================
  /// ☁️ SINCRONIZAÇÃO COM FIRESTORE
  /// ===========================================================

  bool _syncing = false;

  Future<void> _trySync({BuildContext? context}) async {
    if (_syncing) {
      debugPrint("⏳ _trySync ignorado (já está sincronizando).");
      return;
    }
    _syncing = true;

    int pendingPoints = 0;
    try {
      debugPrint("🔍 Tentando sincronizar pontos pendentes...");

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) return;

      final prefs = await SharedPreferences.getInstance();
      pendingPoints = prefs.getInt('pending_points') ?? 0;
      if (pendingPoints <= 0) return;

      final user = _auth.currentUser;
      if (user == null) return;
      final userRef = _firestore.collection('users').doc(user.uid);

      // ✅ ZERA ANTES para evitar duplicar em hot reload / chamadas repetidas
      await prefs.setInt('pending_points', 0);

      // ✅ (Opcional mas recomendado) trava de sync por timestamp (debug)
      await prefs.setString('last_sync_attempt', DateTime.now().toIso8601String());

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
      final data = updated.data() ?? {};

      final int xp = ((data['xp'] as num?) ?? 0).toInt();
      final levelInfo = _levelFromXp(xp);


      await userRef.set({
        'level': levelInfo['level'],
        'levelProgress': levelInfo['progress'],
        'nextXp': levelInfo['nextXp'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack(context, "✅ Pontos/XP sincronizados (+$pendingPoints)!");
      debugPrint("💰 Sincronizado +$pendingPoints pontos (pending_points capturado).");
    } catch (e, st) {
      debugPrint("❌ Erro ao sincronizar pontos/xp: ${e.toString()}");
      debugPrint("📌 Stack: $st");

      // ✅ Se falhar, devolve os pontos pro pending para não perder
      if (pendingPoints > 0) {
        final prefs = await SharedPreferences.getInstance();
        final current = prefs.getInt('pending_points') ?? 0;
        await prefs.setInt('pending_points', current + pendingPoints);
        debugPrint("🧯 pending_points restaurado (+$pendingPoints).");
      }
    } finally {
      _syncing = false;
    }
  }


  /// ===========================================================
  /// 🔥 COMBO DIÁRIO (STREAK)
  /// ===========================================================

  /// Registra um bônus diário (login ou corrida)
  Future<void> registrarBonusDiario({BuildContext? context}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // ✅ Proteção em memória (sessão atual)
    if (_bonusDadoHoje) {
      debugPrint("⚠️ Bônus diário já processado nesta sessão (memória).");
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // ✅ Trava por DIA (YYYY-MM-DD) — À PROVA DE HOT RELOAD
    final today = DateTime.now();
    final todayKey = "${today.year.toString().padLeft(4, '0')}-"
        "${today.month.toString().padLeft(2, '0')}-"
        "${today.day.toString().padLeft(2, '0')}";

    final lastAwardedDay = prefs.getString('daily_bonus_day');
    if (lastAwardedDay == todayKey) {
      debugPrint("⏳ Bônus diário já concedido hoje (daily_bonus_day=$todayKey).");
      _bonusDadoHoje = true;
      return;
    }

    // ------------------------------------------------------------
    // ✅ Lógica de streak (por dia do calendário)
    // ------------------------------------------------------------
    final lastDateStr = prefs.getString('last_daily_bonus_day'); // agora guardamos só yyyy-mm-dd
    DateTime? lastDate;

    if (lastDateStr != null) {
      try {
        // reconstrói como data local (00:00)
        final parts = lastDateStr.split('-');
        if (parts.length == 3) {
          lastDate = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
      } catch (_) {}
    }

    int streak = prefs.getInt('daily_streak') ?? 0;

    if (lastDate == null) {
      streak = 1;
    } else {
      final lastKey = "${lastDate.year.toString().padLeft(4, '0')}-"
          "${lastDate.month.toString().padLeft(2, '0')}-"
          "${lastDate.day.toString().padLeft(2, '0')}";

      if (lastKey == todayKey) {
        // já ganhou hoje (redundante com daily_bonus_day, mas seguro)
        _bonusDadoHoje = true;
        debugPrint("⏳ Bônus diário já concedido hoje (last_daily_bonus_day).");
        return;
      }

      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayKey = "${yesterday.year.toString().padLeft(4, '0')}-"
          "${yesterday.month.toString().padLeft(2, '0')}-"
          "${yesterday.day.toString().padLeft(2, '0')}";

      if (lastKey == yesterdayKey) {
        streak = max(1, streak + 1);
      } else {
        streak = 1;
      }
    }

    // ✅ Marca ANTES de dar pontos (idempotência total)
    await prefs.setString('daily_bonus_day', todayKey);
    await prefs.setString('last_daily_bonus_day', todayKey);
    await prefs.setInt('daily_streak', streak);
    _bonusDadoHoje = true;

    // ------------------------------------------------------------
    // ✅ Calcula pontos
    // ------------------------------------------------------------
    int pontosBase = (streak >= 5) ? 25 : (5 * streak);

    final mult = await _getMultiplicadorPro();
    final pontosFinais = (pontosBase * mult).round();

    final desc = "Dia $streak de sequência diária";

    await addPoints(
      points: pontosFinais,
      source: "Login Diário",
      description: desc,
      context: context,
    );

    // 🏆 checa conquistas
    try {
      await AchievementService().checkAchievements(
        runData: {'streak': streak},
        context: context,
      );
    } catch (e) {
      debugPrint("[Gamification] Erro ao checar conquistas de streak: $e");
    }

    _showSnack(context, "🔥 Combo diário usuário PRO ${streak}x! +$pontosFinais pontos");
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
