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

  // Lista de conquistas disponíveis
  final List<Map<String, dynamic>> _achievements = [
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
        final runs = data['runs'] as List<Map<String, dynamic>>;
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
        final runs = data['runs'] as List<Map<String, dynamic>>;
        if (runs.isEmpty) return false;

        final weeks = runs.map((r) {
          final date = DateTime.tryParse(r['startTime'] ?? '');
          if (date == null) return null;
          final monday = date.subtract(Duration(days: date.weekday - 1));
          return DateTime(monday.year, monday.month, monday.day);
        }).whereType<DateTime>().toSet().toList()
          ..sort((a, b) => b.compareTo(a));

        if (weeks.length < 4) return false;

        for (int i = 0; i < 3; i++) {
          final diff = weeks[i].difference(weeks[i + 1]).inDays.abs();
          if (diff > 7) return false;
        }
        return true;
      },
    },
  ];

  /// Checa conquistas após uma corrida
  Future<void> checkAchievements({
    required Map<String, dynamic> runData,
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

    // Busca corridas do usuário para cálculo de contadores
    final query = await _firestore
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .get();

    final runCount = query.docs.length;
    final totalKm = query.docs.fold<double>(
        0, (sum, doc) => sum + ((doc['distance'] ?? 0.0) as num).toDouble() / 1000);

    final runsList = query.docs.map((d) => d.data()).toList(); // 👈 Adiciona isso

    final currentDistanceKm = ((runData['distance'] ?? 0.0) as num).toDouble() / 1000;
    final pace = (runData['pace'] ?? 0.0) as double;

    debugPrint("[Achievements] 🏃‍♀️ runCount=$runCount | totalKm=${totalKm.toStringAsFixed(2)} | current=${currentDistanceKm.toStringAsFixed(2)} | pace=$pace");

    final newAchievements = <Map<String, dynamic>>[];

    for (var ach in _achievements) {
      final achId = ach['id'] as String;

      // Já desbloqueada → ignora
      if (unlocked.contains(achId)) continue;

      // ⚙️ Travas antifalsos positivos
      if (currentDistanceKm < 0.1 && achId != 'first_run') {
        debugPrint("[Achievements] ⏩ Ignorando ${ach['title']} — corrida muito curta (${currentDistanceKm.toStringAsFixed(2)} km).");
        continue;
      }

      if (runCount == 1 && achId != 'first_run') {
        debugPrint("[Achievements] ⏩ Primeira corrida — só 'Primeira Corrida' pode ser desbloqueada agora.");
        continue;
      }

      // Garante condições realistas
      if (achId == '5k_runner' && totalKm < 5.0) continue;
      if (achId == '10k_runner' && totalKm < 10.0) continue;
      if (achId == 'marathoner' && totalKm < 42.0) continue;
      if (achId == 'night_owl' && currentDistanceKm < 1.0) continue;
      if (achId == 'speed_boost' && (pace <= 0 || pace > 5)) continue;

      // Monta dados
      final data = {
        'runCount': runCount,
        'distance': currentDistanceKm,
        'pace': pace,
        'totalDistance': totalKm,
        'weeklyRuns': runData['weeklyRuns'] ?? 0,
        'streak': runData['streak'] ?? 0,
        'runs': runsList,
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
      final pending =
          prefs.getStringList('pending_achievements_${user.uid}') ?? [];
      pending.addAll(newAchievements.map((a) => jsonEncode(a)));
      await prefs.setStringList('pending_achievements_${user.uid}', pending);
      debugPrint("[Achievements] 🌐 Sem internet. Insígnias pendentes salvas localmente.");
    }
  }


  /// Sincroniza insígnias locais com o Firestore
  Future<void> syncNow({BuildContext? context}) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return;

    final pending =
        prefs.getStringList('pending_achievements_${user.uid}') ?? [];
    if (pending.isEmpty) return;

    final achievements =
    pending.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();

    await _syncAchievements(user.uid, achievements);
    await prefs.setStringList('pending_achievements_${user.uid}', []);

    _showSnack(context, "🏆 Conquistas sincronizadas com sucesso!");
    debugPrint("[Achievements] ☁️ ${achievements.length} insígnias sincronizadas.");
  }

  /// Salva as conquistas no Firestore
  Future<void> _syncAchievements(
      String userId, List<Map<String, dynamic>> achievements) async {
    final batch = _firestore.batch();
    final ref =
    _firestore.collection('users').doc(userId).collection('achievements');

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

  /// Retorna a lista completa de insígnias, marcando as conquistadas
  Future<List<Map<String, dynamic>>> getUserAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return [];

    // Carrega insígnias desbloqueadas localmente
    final unlocked =
        prefs.getStringList('unlocked_achievements_${user.uid}') ?? [];

    // Combina com o Firestore (caso tenha sincronizado)
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

    // Retorna todas as insígnias, marcando as desbloqueadas
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

  /// Posta a conquista no feed público
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
}
