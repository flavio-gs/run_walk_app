import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/achievement_overlay.dart';

class AchievementService {
  static final AchievementService _instance = AchievementService._internal();
  factory AchievementService() => _instance;
  AchievementService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ============================================================
  // 🔰 LISTA DE CONQUISTAS (inclui corridas + territórios)
  // ============================================================
  final List<Map<String, dynamic>> _achievements = [
    // ---- Corridas (já existiam) ----
    {
      'id': 'first_run',
      'title': 'Primeira Corrida',
      'icon': '🎯',
      'condition': (data) => data['runCount'] >= 1,
    },
    {
      'id': '5k_runner',
      'title': 'Corredor 5K',
      'icon': '🥉',
      'condition': (data) => data['distance'] >= 5.0,
    },
    {
      'id': '10k_runner',
      'title': 'Corredor 10K',
      'icon': '🥈',
      'condition': (data) => data['distance'] >= 10.0,
    },
    {
      'id': 'night_owl',
      'title': 'Coruja Noturna',
      'icon': '🌙',
      'condition': (data) {
        final hour = DateTime.now().hour;
        return hour >= 20 || hour < 5;
      },
    },
    {
      'id': 'speed_boost',
      'title': 'Relâmpago',
      'icon': '⚡',
      'condition': (data) => data['pace'] < 5.0,
    },
    {
      'id': 'marathoner',
      'title': 'Maratonista',
      'icon': '🏅',
      'condition': (data) => data['totalDistance'] >= 42.0,
    },
    {
      'id': 'consistent_runner',
      'title': 'Constância',
      'icon': '📅',
      'condition': (data) => data['weeklyRuns'] >= 3,
    },
    {
      'id': 'streak_master',
      'title': 'Sequência de Vitórias',
      'icon': '🔥',
      'condition': (data) => data['streak'] >= 7,
    },
    {
      'id': 'first_week_run',
      'title': 'Primeira Semana',
      'icon': '📆',
      'condition': (data) {
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final runs = (data['runs'] as List<Map<String, dynamic>>?) ?? [];
        return runs.any((r) {
          final date = DateTime.tryParse(r['startTime'] ?? '');
          return date != null && date.isAfter(weekStart);
        });
      },
    },
    {
      'id': 'monthly_consistency',
      'title': 'Constância de 4 Semanas',
      'icon': '🔥📅',
      'condition': (data) {
        final runs = (data['runs'] as List<Map<String, dynamic>>?) ?? [];
        if (runs.isEmpty) return false;

        final weeks = runs
            .map((r) {
          final date = DateTime.tryParse(r['startTime'] ?? '');
          if (date == null) return null;
          final monday = date.subtract(Duration(days: date.weekday - 1));
          return DateTime(monday.year, monday.month, monday.day);
        })
            .whereType<DateTime>()
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

        if (weeks.length < 4) return false;
        for (int i = 0; i < 3; i++) {
          final diff = weeks[i].difference(weeks[i + 1]).inDays.abs();
          if (diff > 7) return false;
        }
        return true;
      },
    },

    // ---- Territórios (NOVOS) ----
    {
      'id': 'territory_conqueror',
      'title': 'Conquistador de Território',
      'icon': '🏰',
      'condition': (data) => (data['territoriesCaptured'] ?? 0) >= 1,
    },
    {
      'id': 'territory_warlord',
      'title': 'Senhor de Regiões',
      'icon': '🗺️',
      'condition': (data) => (data['territoriesCaptured'] ?? 0) >= 5,
    },
    {
      'id': 'territory_overlord',
      'title': 'Mestre do Mapa',
      'icon': '👑',
      'condition': (data) => (data['territoriesCaptured'] ?? 0) >= 10,
    },
    {
      'id': 'territory_keeper_24h',
      'title': 'Guardião 24h',
      'icon': '🛡️',
      'condition': (data) => (data['longestHoldHours'] ?? 0.0) >= 24.0,
    },
    {
      'id': 'territory_keeper_7d',
      'title': 'Fortaleza 7 dias',
      'icon': '🏯',
      'condition': (data) => (data['longestHoldHours'] ?? 0.0) >= 24.0 * 7,
    },
    {
      'id': 'territory_keeper_30d',
      'title': 'Inquebrável 30 dias',
      'icon': '🗿',
      'condition': (data) => (data['longestHoldHours'] ?? 0.0) >= 24.0 * 30,
    },
    {
      'id': 'territory_triple_hold',
      'title': 'Tríplice Coroa',
      'icon': '⚔️',
      'condition': (data) => (data['activeTerritories'] ?? 0) >= 3,
    },
  ];

  // ============================================================
  // 🏆 CONQUISTAS (corrida + territórios)
  // ============================================================
  Future<void> checkAchievements({
    required Map<String, dynamic> runData, // pode incluir chaves de território também
    BuildContext? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint("[Achievements] ⚠️ Nenhum usuário logado, abortando verificação.");
      return;
    }

    // Recupera insígnias já desbloqueadas
    final unlocked = prefs.getStringList('unlocked_achievements_${user.uid}') ?? [];

    // ---- Dados de corrida para composições antigas ----
    final query = await _firestore
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .get();

    final runCount = query.docs.length;
    final totalKm = query.docs.fold<double>(
      0,
          (sum, doc) => sum + ((doc['distance'] ?? 0.0) as num).toDouble() / 1000,
    );
    final runsList = query.docs.map((d) => d.data()).cast<Map<String, dynamic>>().toList();

    final currentDistanceKm = ((runData['distance'] ?? 0.0) as num).toDouble() / 1000;
    final pace = ((runData['pace'] ?? 0.0) as num).toDouble();

    // ---- Dados de território (podem vir do runData ou do Firestore agregados) ----
    // Preferência: valores passados pelo caller (run_tracker/motor de territórios)
    int territoriesCaptured = (runData['territoriesCaptured'] ?? 0).toInt();
    int activeTerritories = (runData['activeTerritories'] ?? 0).toInt();
    double longestHoldHours = ((runData['longestHoldHours'] ?? 0.0) as num).toDouble();

    // Se não veio nada no runData, tenta buscar agregados rápidos do Firestore
    if (territoriesCaptured == 0 || longestHoldHours == 0.0) {
      try {
        final agg = await _firestore.collection('users').doc(user.uid).get();
        final data = (agg.data() ?? {})['territories'] as Map<String, dynamic>?;

        if (data != null) {
          territoriesCaptured = territoriesCaptured == 0 ? (data['capturedCount'] ?? 0) : territoriesCaptured;
          activeTerritories = activeTerritories == 0 ? (data['activeCount'] ?? 0) : activeTerritories;
          final longestMs = (data['longestHoldMs'] ?? 0) as num;
          final hours = longestMs / (1000 * 60 * 60);
          if (longestHoldHours == 0.0 && hours > 0) longestHoldHours = hours.toDouble();
        }
      } catch (_) {}
    }

    debugPrint(
        "[Achievements] 🏃 runCount=$runCount | totalKm=${totalKm.toStringAsFixed(2)} | current=${currentDistanceKm.toStringAsFixed(2)} | pace=$pace"
            " || 🌐 territoriesCaptured=$territoriesCaptured | active=$activeTerritories | longestHoldHours=${longestHoldHours.toStringAsFixed(1)}");

    final newAchievements = <Map<String, dynamic>>[];

    for (var ach in _achievements) {
      final achId = ach['id'] as String;

      // já desbloqueada → ignora
      if (unlocked.contains(achId)) continue;

      // ⚙️ Travas antifalsos positivos (corridas)
      if (currentDistanceKm < 0.1 &&
          ['first_run', 'territory_conqueror', 'territory_warlord', 'territory_overlord', 'territory_keeper_24h', 'territory_keeper_7d', 'territory_keeper_30d', 'territory_triple_hold']
              .contains(achId) == false) {
        debugPrint("[Achievements] ⏩ Ignorando ${ach['title']} — corrida muito curta (${currentDistanceKm.toStringAsFixed(2)} km).");
        continue;
      }
      if (runCount == 1 && achId != 'first_run' &&
          !achId.startsWith('territory_')) {
        debugPrint("[Achievements] ⏩ Primeira corrida — só 'Primeira Corrida' pode ser desbloqueada agora (não afeta territórios).");
        continue;
      }

      // Garante condições realistas de corrida
      if (achId == '5k_runner' && totalKm < 5.0) continue;
      if (achId == '10k_runner' && totalKm < 10.0) continue;
      if (achId == 'marathoner' && totalKm < 42.0) continue;
      if (achId == 'night_owl' && currentDistanceKm < 1.0) continue;
      if (achId == 'speed_boost' && (pace <= 0 || pace > 5)) continue;

      // Monta dados unificados
      final data = {
        // corrida
        'runCount': runCount,
        'distance': currentDistanceKm,
        'pace': pace,
        'totalDistance': totalKm,
        'weeklyRuns': runData['weeklyRuns'] ?? 0,
        'streak': runData['streak'] ?? 0,
        'runs': runsList,

        // território
        'territoriesCaptured': territoriesCaptured,
        'activeTerritories': activeTerritories,
        'longestHoldHours': longestHoldHours,
      };

      final condition = (ach['condition'] as Function)(data);
      if (!condition) continue;

      // ✅ Desbloqueia
      newAchievements.add(ach);
      unlocked.add(achId);

      debugPrint("[Achievements] ✅ Desbloqueada: ${ach['title']} (${ach['icon']})");

      // Pop-up e feed
      if (context != null && context.mounted) {
        await showAchievementPopup(context, title: ach['title'], icon: ach['icon']);
        _showSnack(context, "${ach['icon']} Nova conquista: ${ach['title']}!");
      }

      await _postAchievementToFeed(
        user.uid,
        achId: achId,
        title: ach['title'],
        icon: ach['icon'],
      );
    }

    if (newAchievements.isEmpty) {
      debugPrint("[Achievements] Nenhuma nova conquista desbloqueada.");
      return;
    }

    // 🔄 Salva local e sincroniza
    await prefs.setStringList('unlocked_achievements_${user.uid}', unlocked);
    final connectivity = await Connectivity().checkConnectivity();

    if (connectivity != ConnectivityResult.none) {
      await _syncAchievements(user.uid, newAchievements);
    } else {
      final pending = prefs.getStringList('pending_achievements_${user.uid}') ?? [];
      pending.addAll(newAchievements.map((a) => jsonEncode(a)));
      await prefs.setStringList('pending_achievements_${user.uid}', pending);
      debugPrint("[Achievements] 🌐 Sem internet. Insígnias pendentes salvas localmente.");
    }
  }

  // ============================================================
  // ☁️ SINCRONIZAÇÃO DE CONQUISTAS (igual você já tinha)
  // ============================================================
  Future<void> syncNow({BuildContext? context}) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return;

    // conquistas pendentes
    final pendingAch = prefs.getStringList('pending_achievements_${user.uid}') ?? [];
    if (pendingAch.isNotEmpty) {
      final achievements = pendingAch.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
      await _syncAchievements(user.uid, achievements);
      await prefs.setStringList('pending_achievements_${user.uid}', []);
      debugPrint("[Achievements] ☁️ ${achievements.length} insígnias sincronizadas.");
    }

    // eventos de território pendentes
    final pendingTerr = prefs.getStringList('pending_territory_events_${user.uid}') ?? [];
    if (pendingTerr.isNotEmpty) {
      final events = pendingTerr.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
      await _syncTerritoryEvents(user.uid, events);
      await prefs.setStringList('pending_territory_events_${user.uid}', []);
      debugPrint("[Territory] ☁️ ${events.length} eventos sincronizados.");
    }

    _showSnack(context, "🏆 Conquistas e territórios sincronizados!");
  }

  Future<void> _syncAchievements(String userId, List<Map<String, dynamic>> achievements) async {
    final batch = _firestore.batch();
    final ref = _firestore.collection('users').doc(userId).collection('achievements');

    for (var ach in achievements) {
      final doc = ref.doc(ach['id']);
      batch.set(
        doc,
        {
          'title': ach['title'],
          'icon': ach['icon'],
          'timestamp': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    debugPrint("[Achievements] ✅ Insígnias salvas no Firestore para $userId");
  }

  void _showSnack(BuildContext? context, String message) {
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getUserAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return [];

    final unlocked = prefs.getStringList('unlocked_achievements_${user.uid}') ?? [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('achievements')
          .get();

      for (var doc in snapshot.docs) {
        if (!unlocked.contains(doc.id)) unlocked.add(doc.id);
      }
    } catch (e) {
      debugPrint("[Achievements] Erro ao buscar insígnias no Firestore: $e");
    }

    return _achievements.map((a) {
      final isUnlocked = unlocked.contains(a['id']);
      return {
        'id': a['id'],
        'title': a['title'],
        'icon': a['icon'],
        'unlocked': isUnlocked,
      };
    }).toList();
  }

  Future<void> _postAchievementToFeed(
      String userId, {
        required String achId,
        required String title,
        required String icon,
      }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      await _firestore.collection('posts').add({
        'type': 'achievement',
        'authorId': userId,
        'authorName': userData['displayName'] ?? 'Corredor',
        'authorPhoto': userData['photoURL'],
        'achievementId': achId,
        'title': title,
        'icon': icon,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'commentsCount': 0,
      });

      debugPrint("[Achievements] 📢 Postada no feed: $title ($icon)");
    } catch (e) {
      debugPrint("[Achievements] Falha ao postar conquista no feed: $e");
    }
  }

  // ============================================================
  // 🧠 SISTEMA DE LEVEL E XP
  // ============================================================
  Future<void> addXP(
      double xpGanho, {
        BuildContext? context,
        String source = 'run',
        String? description,
      }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    double totalXP = prefs.getDouble('total_xp_${user.uid}') ?? 0.0;

    totalXP += xpGanho;
    await prefs.setDouble('total_xp_${user.uid}', totalXP);

    final level = _calculateLevel(totalXP);

    final oldLevel = prefs.getInt('user_level_${user.uid}') ?? 0;
    if (level > oldLevel) {
      await prefs.setInt('user_level_${user.uid}', level);
      if (context != null && context.mounted) {
        await showLevelUpAnimation(context, level);
        await showAchievementPopup(context, title: 'Nível $level alcançado!', icon: '🚀');
        _showSnack(context, "🎉 Você subiu para o nível $level!");
      }
    }

    await _firestore.collection('users').doc(user.uid).set({
      'xp': totalXP,
      'level': level,
    }, SetOptions(merge: true));

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('xp_history')
        .add({
      'amount': xpGanho,
      'source': source,
      'description': description ?? _getSourceDescription(source),
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint("[XP] +$xpGanho XP por $source | Total: ${totalXP.toStringAsFixed(1)} | Nível: $level");
  }

  Future<void> removeXP(
      double xpPerdido, {
        BuildContext? context,
        String source = 'territory_loss',
        String? description,
      }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    double totalXP = prefs.getDouble('total_xp_${user.uid}') ?? 0.0;

    totalXP -= xpPerdido;
    if (totalXP < 0) totalXP = 0;
    await prefs.setDouble('total_xp_${user.uid}', totalXP);

    final newLevel = _calculateLevel(totalXP);
    final oldLevel = prefs.getInt('user_level_${user.uid}') ?? newLevel;

    if (newLevel < oldLevel) {
      await prefs.setInt('user_level_${user.uid}', newLevel);
      if (context != null && context.mounted) {
        await showAchievementPopup(context, title: 'Você foi rebaixado para o nível $newLevel 😞', icon: '⬇️');
        _showSnack(context, "⚠️ Você perdeu XP e caiu para o nível $newLevel.");
      }
    }

    await _firestore.collection('users').doc(user.uid).set({
      'xp': totalXP,
      'level': newLevel,
    }, SetOptions(merge: true));

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('xp_history')
        .add({
      'amount': -xpPerdido,
      'source': source,
      'description': description ?? "Perda de território dominado",
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint("[XP] 🔻 -$xpPerdido XP ($source) | Novo total: ${totalXP.toStringAsFixed(1)} | Nível: $newLevel");
  }

  String _getSourceDescription(String source) {
    switch (source) {
      case 'territory':
        return "Conquista de território";
      case 'achievement':
        return "Nova conquista desbloqueada";
      case 'challenge':
        return "Desafio completado";
      default:
        return "Atividade física registrada";
    }
  }

  int _calculateLevel(double xp) => (xp / 500).floor();

  Future<Map<String, dynamic>> getUserLevelData() async {
    final user = _auth.currentUser;
    if (user == null) return {'xp': 0.0, 'level': 0};

    final prefs = await SharedPreferences.getInstance();
    final xp = prefs.getDouble('total_xp_${user.uid}') ?? 0.0;
    final level = prefs.getInt('user_level_${user.uid}') ?? _calculateLevel(xp);

    return {'xp': xp, 'level': level};
  }

  // ============================================================
  // 🌍 TERRITÓRIOS — API p/ integrar no run_tracker
  // ============================================================

  /// Chame quando o usuário CAPTURAR um território.
  /// - Atualiza agregados do usuário (capturedCount, activeCount)
  /// - Gera evento (feed + histórico)
  /// - Ganha XP por captura
  Future<void> captureTerritory({
    required String territoryId,
    required String territoryName,
    double xpOnCapture = 25.0,
    BuildContext? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final connectivity = await Connectivity().checkConnectivity();

    final event = {
      'type': 'capture',
      'territoryId': territoryId,
      'territoryName': territoryName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Atualiza agregados locais (para conquistas instantâneas)
    final capturedKey = 'territories_captured_${user.uid}';
    final activeKey = 'territories_active_${user.uid}';
    final currentCaptured = prefs.getInt(capturedKey) ?? 0;
    final currentActive = prefs.getInt(activeKey) ?? 0;
    await prefs.setInt(capturedKey, currentCaptured + 1);
    await prefs.setInt(activeKey, currentActive + 1);

    // XP
    await addXP(xpOnCapture, context: context, source: 'territory', description: "Capturou $territoryName");

    // Post no feed (evento de território)
    await _postTerritoryEventToFeed(
      user.uid,
      title: "Capturou $territoryName",
      icon: '🏰',
      meta: {'territoryId': territoryId},
    );

    // Sincroniza ou enfileira
    if (connectivity != ConnectivityResult.none) {
      await _syncTerritoryEvents(user.uid, [event]);
      await _mergeUserTerritoryAggregates(
        userId: user.uid,
        incCaptured: 1,
        incActive: 1,
      );
    } else {
      await _enqueueTerritoryEventLocally(user.uid, event);
    }

    // Dispara checagem de conquistas focada em território
    await checkAchievements(
      runData: {
        'territoriesCaptured': (currentCaptured + 1),
        'activeTerritories': (currentActive + 1),
      },
      context: context,
    );
  }

  /// Chame quando o usuário PERDER um território que estava dominando.
  /// - Decrementa activeCount
  /// - Gera evento de perda (sem XP)
  Future<void> loseTerritory({
    required String territoryId,
    required String territoryName,
    BuildContext? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final connectivity = await Connectivity().checkConnectivity();

    final event = {
      'type': 'loss',
      'territoryId': territoryId,
      'territoryName': territoryName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Atualiza agregados locais
    final activeKey = 'territories_active_${user.uid}';
    final currentActive = prefs.getInt(activeKey) ?? 0;
    await prefs.setInt(activeKey, (currentActive - 1).clamp(0, 1 << 31));

    // Post opcional no feed (estilo "foi destronado")
    await _postTerritoryEventToFeed(
      user.uid,
      title: "Perdeu $territoryName",
      icon: '🧱',
      meta: {'territoryId': territoryId},
    );

    if (connectivity != ConnectivityResult.none) {
      await _syncTerritoryEvents(user.uid, [event]);
      await _mergeUserTerritoryAggregates(
        userId: user.uid,
        incActive: -1,
      );
    } else {
      await _enqueueTerritoryEventLocally(user.uid, event);
    }

    // Checa conquistas que dependem de activeTerritories
    await checkAchievements(
      runData: {
        'activeTerritories': (currentActive - 1).clamp(0, 1 << 31),
      },
      context: context,
    );
  }

  /// Chame quando UM DOMÍNIO TERMINAR (ex.: outro jogador tomou).
  /// Passe a DURAÇÃO (quanto tempo o usuário ficou com esse território).
  /// - Atualiza longestHoldMs se a duração for recorde
  /// - Gera histórico de domínio (hold)
  /// - Opcional: dá XP por tempo dominado (linear simples)
  Future<void> finalizeTerritoryHold({
    required String territoryId,
    required String territoryName,
    required Duration holdDuration,
    bool grantTimeXp = true,
    double xpPerHour = 5.0,
    BuildContext? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final connectivity = await Connectivity().checkConnectivity();

    final ms = holdDuration.inMilliseconds;
    final holdEvent = {
      'type': 'hold_finished',
      'territoryId': territoryId,
      'territoryName': territoryName,
      'holdMs': ms,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Atualiza recorde local
    final longestKey = 'territories_longest_ms_${user.uid}';
    final prevLongest = prefs.getInt(longestKey) ?? 0;
    if (ms > prevLongest) {
      await prefs.setInt(longestKey, ms);
    }

    // XP por tempo (opcional)
    if (grantTimeXp && ms > 0) {
      final hours = ms / (1000 * 60 * 60);
      final xp = hours * xpPerHour;
      if (xp > 0) {
        await addXP(xp, context: context, source: 'territory', description: "Domínio de ${hours.toStringAsFixed(1)}h em $territoryName");
      }
    }

    // Sincroniza ou enfileira
    if (connectivity != ConnectivityResult.none) {
      await _syncTerritoryEvents(user.uid, [holdEvent]);
      await _maybeUpdateLongestHoldOnServer(user.uid, ms);
    } else {
      await _enqueueTerritoryEventLocally(user.uid, holdEvent);
    }

    // Conquistas de "Maior tempo de domínio"
    final hoursNow = ms / (1000 * 60 * 60);
    final hoursBest = (ms > prevLongest ? hoursNow : (prevLongest / (1000 * 60 * 60)));
    await checkAchievements(
      runData: {
        'longestHoldHours': hoursBest,
      },
      context: context,
    );
  }

  // ============================================================
  // 🔗 Persistência de eventos/aggregates de territórios
  // ============================================================

  Future<void> _enqueueTerritoryEventLocally(String userId, Map<String, dynamic> event) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('pending_territory_events_$userId') ?? [];
    pending.add(jsonEncode(event));
    await prefs.setStringList('pending_territory_events_$userId', pending);
    debugPrint("[Territory] 📦 Evento enfileirado localmente: ${event['type']}");
  }

  Future<void> _syncTerritoryEvents(String userId, List<Map<String, dynamic>> events) async {
    final batch = _firestore.batch();
    final root = _firestore.collection('users').doc(userId);

    for (final e in events) {
      // salva no histórico do usuário
      final histRef = root.collection('territory_history').doc();
      batch.set(histRef, {
        ...e,
        'serverTimestamp': FieldValue.serverTimestamp(),
      });

      // index leve em /territories/{id}/ownership para futuras análises (opcional)
      if (e['territoryId'] != null) {
        final tRef = _firestore.collection('territories').doc(e['territoryId']).collection('ownership').doc();
        batch.set(tRef, {
          'userId': userId,
          'type': e['type'],
          'territoryName': e['territoryName'],
          'holdMs': e['holdMs'],
          'clientTimestamp': e['timestamp'],
          'serverTimestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  /// Atualiza agregados do usuário em users/{uid}.territories
  Future<void> _mergeUserTerritoryAggregates({
    required String userId,
    int? incCaptured,
    int? incActive,
    int? longestHoldMs, // se quiser forçar um valor (normalmente usamos o maybeUpdate)
  }) async {
    final doc = _firestore.collection('users').doc(userId);

    final update = <String, dynamic>{
      'territories.capturedCount': FieldValue.increment((incCaptured ?? 0).toDouble()),
      'territories.activeCount': FieldValue.increment((incActive ?? 0).toDouble()),
    };

    if (longestHoldMs != null) {
      update['territories.longestHoldMs'] = longestHoldMs;
    }

    await doc.set(update, SetOptions(merge: true));
  }

  /// Só atualiza longestHoldMs no servidor se o novo for maior
  Future<void> _maybeUpdateLongestHoldOnServer(String userId, int candidateMs) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final current = ((doc.data()?['territories'] ?? {}) as Map<String, dynamic>)['longestHoldMs'] ?? 0;
      final currentMs = (current as num).toInt();
      if (candidateMs > currentMs) {
        await _firestore.collection('users').doc(userId).set({
          'territories.longestHoldMs': candidateMs,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("[Territory] ⚠️ Falha ao atualizar longestHoldMs: $e");
    }
  }

  Future<void> _postTerritoryEventToFeed(
      String userId, {
        required String title,
        required String icon,
        Map<String, dynamic>? meta,
      }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      await _firestore.collection('posts').add({
        'type': 'territory',
        'authorId': userId,
        'authorName': userData['displayName'] ?? 'Jogador',
        'authorPhoto': userData['photoURL'],
        'title': title,
        'icon': icon,
        'meta': meta,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'commentsCount': 0,
      });

      debugPrint("[Territory] 📢 Post no feed: $title ($icon)");
    } catch (e) {
      debugPrint("[Territory] Falha ao postar no feed: $e");
    }
  }
}
