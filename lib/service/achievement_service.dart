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
      'condition': (data) => data['runCount'] == 1,
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
  ];

  /// Checa conquistas após uma corrida
  Future<void> checkAchievements({
    required Map<String, dynamic> runData,
    BuildContext? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return;

    // Recupera insígnias já desbloqueadas
    final unlocked =
        prefs.getStringList('unlocked_achievements_${user.uid}') ?? [];

    // Prepara dados úteis para checagem
    final query = await _firestore
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .get();

    final runCount = query.docs.length;
    final totalDistance = query.docs.fold<double>(
        0, (sum, doc) => sum + (doc['distance'] ?? 0.0));

    final newAchievements = <Map<String, dynamic>>[];

    for (var ach in _achievements) {
      if (unlocked.contains(ach['id'])) continue;

      final data = {
        'runCount': runCount,
        'distance': runData['distance'],
        'pace': runData['pace'],
        'totalDistance': totalDistance,
        'weeklyRuns': runData['weeklyRuns'] ?? 0,
        'streak': runData['streak'] ?? 0,
      };

      if ((ach['condition'] as Function)(data)) {
        newAchievements.add(ach);
        unlocked.add(ach['id']);

        // 🎉 Pop-up de conquista
        await showAchievementPopup(context!, title: ach['title'], icon: ach['icon']);

        // 📰 Compartilha no feed automaticamente
        await _postAchievementToFeed(
          user.uid,
          achId: ach['id'],
          title: ach['title'],
          icon: ach['icon'],
        );

        _showSnack(context, "${ach['icon']} Nova conquista: ${ach['title']}!");
      }

    }

    if (newAchievements.isEmpty) return;

    await prefs.setStringList('unlocked_achievements_${user.uid}', unlocked);

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      await _syncAchievements(user.uid, newAchievements);
    } else {
      final pending =
          prefs.getStringList('pending_achievements_${user.uid}') ?? [];
      pending.addAll(newAchievements.map((a) => jsonEncode(a)));
      await prefs.setStringList('pending_achievements_${user.uid}', pending);
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
  }

  /// Salva as conquistas no Firestore
  Future<void> _syncAchievements(
      String userId, List<Map<String, dynamic>> achievements) async {
    final batch = _firestore.batch();
    final ref = _firestore.collection('users').doc(userId).collection('achievements');

    for (var ach in achievements) {
      final doc = ref.doc(ach['id']);
      batch.set(doc, {
        'title': ach['title'],
        'icon': ach['icon'],
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
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
    } catch (_) {}

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

  Future<void> _postAchievementToFeed(String userId,
      {required String achId, required String title, required String icon}) async {
    try {
      // pega dados do usuário (displayName, photo, etc.)
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      await _firestore.collection('posts').add({
        'type': 'achievement',
        'userId': userId,
        'userName': userData['displayName'] ?? 'Corredor',
        'userPhoto': userData['photoURL'],
        'achievementId': achId,
        'title': title,
        'icon': icon,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'commentsCount': 0,
      });
    } catch (e) {
      debugPrint("Falha ao postar conquista no feed: $e");
    }
  }


}
