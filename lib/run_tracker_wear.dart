import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wear/health_wear_service.dart';

/// ============================================================================
/// 🎯 MODELOS E STORAGE LOCAL
/// ============================================================================
class WearRunPoint {
  final double lat;
  final double lng;
  final DateTime t;

  WearRunPoint({required this.lat, required this.lng, required this.t});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 't': t.toIso8601String()};
  static WearRunPoint fromJson(Map<String, dynamic> j) =>
      WearRunPoint(lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble(), t: DateTime.parse(j['t'] as String));
}

class WearRun {
  final String localId;
  final int durationSec;
  final double distanceM;
  final double kcal;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<WearRunPoint> path;

  WearRun({
    required this.localId,
    required this.durationSec,
    required this.distanceM,
    required this.kcal,
    required this.startedAt,
    required this.endedAt,
    required this.path,
  });

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'durationSec': durationSec,
    'distanceM': distanceM,
    'kcal': kcal,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'path': path.map((p) => p.toJson()).toList(),
  };

  static WearRun fromJson(Map<String, dynamic> j) => WearRun(
    localId: j['localId'],
    durationSec: (j['durationSec'] as num).toInt(),
    distanceM: (j['distanceM'] as num).toDouble(),
    kcal: (j['kcal'] as num).toDouble(),
    startedAt: DateTime.parse(j['startedAt']),
    endedAt: DateTime.parse(j['endedAt']),
    path: (j['path'] as List)
        .map((e) => WearRunPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class WearLocalStore {
  static const _kPendingKey = 'wear_pending_runs';
  static const _kCurrentKey = 'wear_current_run';

  static Future<void> queueRun(WearRun run) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingKey);
    final list = raw != null ? (jsonDecode(raw) as List) : <dynamic>[];
    list.add(run.toJson());
    await prefs.setString(_kPendingKey, jsonEncode(list));
  }

  static Future<List<WearRun>> getPendingRuns() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => WearRun.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> removePending(String localId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .where((e) => (e as Map)['localId'] != localId)
        .toList();
    await prefs.setString(_kPendingKey, jsonEncode(list));
  }

  static Future<void> saveCurrentRunDraft(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentKey, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> loadCurrentRunDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCurrentKey);
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  static Future<void> clearCurrentRunDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentKey);
  }
}

/// ============================================================================
/// 🔌 FIREBASE
/// ============================================================================
Future<void> _ensureFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      debugPrint('⌚ [Wear] Firebase inicializado.');
    }
  } catch (e) {
    debugPrint('⌚ [Wear] Erro Firebase: $e');
  }
}

/// ============================================================================
/// 🏃 PÁGINA PRINCIPAL
/// ============================================================================
class RunTrackerWearPage extends StatefulWidget {
  const RunTrackerWearPage({super.key});

  @override
  State<RunTrackerWearPage> createState() => _RunTrackerWearPageState();
}

class _RunTrackerWearPageState extends State<RunTrackerWearPage>
    with SingleTickerProviderStateMixin {
  bool isRunning = false;
  bool _usingWHS = false;
  Timer? _timer;
  DateTime? _startTime;
  Duration elapsed = Duration.zero;
  double totalDistance = 0.0;
  double totalCalories = 0.0;
  int? heartBpm;
  StreamSubscription? _whsSub;
  Position? lastPosition;
  final List<WearRunPoint> _path = [];

  late final AnimationController _progressController;
  final PageController _pageController = PageController();
  final NumberFormat _two = NumberFormat('00');
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _progressController =
    AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();

    _restoreDraft();
    _refreshPendingCount();
  }

  @override
  void dispose() {
    _whsSub?.cancel();
    _timer?.cancel();
    _progressController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleRun() => isRunning ? _stopRun() : _startRun();

  Future<void> _startRun() async {
    setState(() {
      isRunning = true;
      _startTime = DateTime.now();
      elapsed = Duration.zero;
      totalDistance = 0;
      totalCalories = 0;
      heartBpm = null;
    });

    final available = await HealthWearService.isAvailable();
    if (available) {
      final started = await HealthWearService.start();
      if (started) {
        _usingWHS = true;
        _whsSub?.cancel();
        _whsSub = HealthWearService.metricsStream().listen((event) {
          final kind = event['kind'];
          if (kind == 'metrics') {
            final data = Map<String, dynamic>.from(event['data'] ?? {});
            if (data['distance'] != null) totalDistance = (data['distance'] as num).toDouble();
            if (data['calories'] != null) totalCalories = (data['calories'] as num).toDouble();
            if (data['bpm'] != null) heartBpm = (data['bpm'] as num).round();
            if (mounted) setState(() {});
          }
        });
      }
    }

    if (!_usingWHS) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tickFallback());
    }
  }

  Future<void> _tickFallback() async {
    elapsed = DateTime.now().difference(_startTime!);
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      if (lastPosition != null) {
        final d = Geolocator.distanceBetween(
          lastPosition!.latitude,
          lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (d > 3) totalDistance += d;
      }
      lastPosition = pos;
    } catch (_) {
      totalDistance += 5;
    }
    totalCalories = totalDistance / 15.0;
    if (mounted) setState(() {});
    _saveDraft();
  }

  Future<void> _stopRun() async {
    _whsSub?.cancel();
    if (_usingWHS) await HealthWearService.stop();
    _timer?.cancel();
    setState(() => isRunning = false);

    final run = WearRun(
      localId: 'wear_${DateTime.now().millisecondsSinceEpoch}',
      durationSec: elapsed.inSeconds,
      distanceM: totalDistance,
      kcal: totalCalories,
      startedAt: _startTime ?? DateTime.now(),
      endedAt: DateTime.now(),
      path: List.of(_path),
    );
    await WearLocalStore.queueRun(run);
    await WearLocalStore.clearCurrentRunDraft();
    await _refreshPendingCount();
    await _trySync('stopRun');
  }

  Future<void> _saveDraft() async {
    if (!isRunning) return;
    final draft = {
      'start': _startTime!.toIso8601String(),
      'elapsedSec': elapsed.inSeconds,
      'distanceM': totalDistance,
      'kcal': totalCalories,
      'path': _path.map((e) => e.toJson()).toList(),
    };
    await WearLocalStore.saveCurrentRunDraft(draft);
  }

  Future<void> _restoreDraft() async {
    final draft = await WearLocalStore.loadCurrentRunDraft();
    if (draft == null) return;
    try {
      _startTime = DateTime.parse(draft['start']);
      elapsed = Duration(seconds: (draft['elapsedSec'] as num).toInt());
      totalDistance = (draft['distanceM'] as num).toDouble();
      totalCalories = (draft['kcal'] as num).toDouble();
      setState(() => isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tickFallback());
    } catch (_) {
      await WearLocalStore.clearCurrentRunDraft();
    }
  }

  Future<void> _refreshPendingCount() async {
    final runs = await WearLocalStore.getPendingRuns();
    setState(() => _pendingCount = runs.length);
  }

  Future<void> _trySync(String reason) async {
    debugPrint('⌚ [Wear] Tentando sync ($reason)');
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;
    await _ensureFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final pendentes = await WearLocalStore.getPendingRuns();
    if (pendentes.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance.collection('corridas');
    for (final r in pendentes) {
      final doc = col.doc();
      batch.set(doc, {
        'userId': user.uid,
        'distancia_m': r.distanceM,
        'tempo_s': r.durationSec,
        'kcal': r.kcal,
        'data': r.endedAt,
        'path': r.path.map((p) => p.toJson()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'wear',
      });
    }
    await batch.commit();
    for (final r in pendentes) {
      await WearLocalStore.removePending(r.localId);
    }
    await _refreshPendingCount();
    debugPrint('⌚ [Wear] Sync concluído.');
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _two.format(elapsed.inMinutes.remainder(60));
    final seconds = _two.format(elapsed.inSeconds.remainder(60));
    final km = (totalDistance / 1000).toStringAsFixed(2);
    final pace = totalDistance > 0
        ? (elapsed.inMinutes / (totalDistance / 1000)).toStringAsFixed(1)
        : '--';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          children: [
            // Tela principal
            Center(
              child: GestureDetector(
                onTap: _toggleRun,
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (_, __) => CustomPaint(
                    painter: _CircularRingPainter(
                        progress: _progressController.value, isRunning: isRunning),
                    child: Container(
                      width: 160,
                      height: 160,
                      alignment: Alignment.center,
                      child: Icon(
                        isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 96,
                        color: isRunning ? Colors.redAccent : Colors.orangeAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Tela de métricas
            Padding(
              padding: const EdgeInsets.all(10),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_pendingCount > 0)
                      Text("⏫ $_pendingCount pendente(s)",
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 6),
                    Text(
                      isRunning ? "🏃 Correndo..." : "⏸️ Parado",
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Text("$minutes:$seconds",
                        style: const TextStyle(color: Colors.white, fontSize: 36)),
                    const SizedBox(height: 6),
                    Text("$km km",
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 22)),
                    const SizedBox(height: 6),
                    Text("🔥 ${totalCalories.toStringAsFixed(0)} kcal",
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    if (heartBpm != null)
                      Text("💓 $heartBpm bpm",
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text("🏁 Pace: $pace min/km",
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(_usingWHS ? "🩺 WHS ativo" : "📡 GPS/Simulação",
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () => _trySync('manual'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                          side: const BorderSide(color: Colors.orangeAccent)),
                      child: const Text('Sincronizar agora'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// 🎨 ANEL ANIMADO
/// ============================================================================
class _CircularRingPainter extends CustomPainter {
  final double progress;
  final bool isRunning;
  _CircularRingPainter({required this.progress, required this.isRunning});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final base = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final ring = Paint()
      ..shader = SweepGradient(
        colors: const [Colors.orangeAccent, Colors.amberAccent, Colors.deepOrangeAccent],
        startAngle: 0,
        endAngle: 2 * pi,
      ).createShader(Rect.fromCircle(center: center, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;
    canvas.drawCircle(center, r, base);
    if (isRunning) {
      final sweep = 2 * pi * progress;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r),
          -pi / 2, sweep, false, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularRingPainter old) =>
      old.progress != progress || old.isRunning != isRunning;
}
