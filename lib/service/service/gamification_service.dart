import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class GamificationService {
  static final GamificationService _instance = GamificationService._internal();
  factory GamificationService() => _instance;
  GamificationService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Calcula o level a partir do XP total
  Map<String, dynamic> _levelFromXp(int xp) {
    int level = 1;
    while (xp >= (level * level * 100)) {
      level++;
    }
    // level atual é um acima do necessário: volta um
    level = level > 1 ? level - 1 : 1;
    final int currentLevelXp = level * level * 100;
    final int nextLevelXp = (level + 1) * (level + 1) * 100;
    final double progress = (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);
    return {'level': level, 'progress': progress.clamp(0.0, 1.0), 'nextXp': nextLevelXp};
  }

  /// Adiciona pontos localmente e tenta sincronizar com o Firestore
  Future<void> addPoints(int points, {BuildContext? context}) async {
    final prefs = await SharedPreferences.getInstance();
    int localPoints = prefs.getInt('pending_points') ?? 0;
    localPoints += points;
    await prefs.setInt('pending_points', localPoints);

    // 💬 feedback offline
    _showSnack(context, "💾 Pontos/XP salvos localmente: +$points (sem conexão)");

    // tenta sincronizar
    await _trySync(context: context);
  }

  /// Tenta enviar os pontos pendentes ao Firestore
  Future<void> _trySync({BuildContext? context}) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    final prefs = await SharedPreferences.getInstance();
    int pendingPoints = prefs.getInt('pending_points') ?? 0;
    if (pendingPoints <= 0) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final userRef = _firestore.collection('users').doc(user.uid);

    try {
      // 1) Garante que o doc existe
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

      // 2) Incrementa totalPoints e xp de forma atômica
      await userRef.set({
        'totalPoints': FieldValue.increment(pendingPoints),
        'xp': FieldValue.increment(pendingPoints),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3) Recalcula nível localmente e persiste
      final updated = await userRef.get();
      final int xp = (updated.data()?['xp'] ?? 0) as int;
      final levelInfo = _levelFromXp(xp);

      await userRef.set({
        'level': levelInfo['level'],
        'levelProgress': levelInfo['progress'],
        'nextXp': levelInfo['nextXp'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 4) Zera pendência local só após sucesso
      await prefs.setInt('pending_points', 0);

      _showSnack(context, "✅ Pontos/XP sincronizados (+$pendingPoints)!");
    } catch (e) {
      debugPrint("Erro ao sincronizar pontos/xp: $e");
      // Não zera o pending_points aqui — tenta de novo depois.
    }
  }


  /// Retorna total (online + offline)
  Future<int> getTotalPoints() async {
    final prefs = await SharedPreferences.getInstance();
    int pending = prefs.getInt('pending_points') ?? 0;
    final user = _auth.currentUser;
    if (user == null) return pending;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final onlinePoints = doc.data()?['totalPoints'] ?? 0;
      return onlinePoints + pending;
    } catch (_) {
      return pending;
    }
  }

  /// Sincronização manual
  Future<void> syncNow({BuildContext? context}) async =>
      await _trySync(context: context);

  /// Mostra um snackbar de forma segura
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
