import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/service/ad_service.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/share_run.dart';
import 'model/run_model.dart';
import 'mais_detalhes_page.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
  bool _isAdLoading = false;

  @override
  void initState() {
    super.initState();
    RewardedAdService().loadRewardedAd();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _runDocStream(String runId) {
    return FirebaseFirestore.instance.collection('corridas').doc(runId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _samplesStream(String runId) {
    return FirebaseFirestore.instance
        .collection('corridas')
        .doc(runId)
        .collection('samples')
        .orderBy('t')
        .snapshots();
  }

  // ─────────────────────────────
  // HELPERS
  // ─────────────────────────────
  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  String _formatPace(double pace) {
    if (pace.isInfinite || pace.isNaN) return "00:00";
    final int min = pace.floor();
    final int sec = ((pace - min) * 60).round();
    final safeSec = sec >= 60 ? 59 : sec;
    return "${min.toString().padLeft(2, '0')}:${safeSec.toString().padLeft(2, '0')}";
  }

  String _formatNum1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  String _formatNum0(double v) => v.toStringAsFixed(0).replaceAll('.', ',');

  String _calculateSpeed(double distanceMeters, int durationSeconds) {
    if (durationSeconds <= 0) return "0,0";
    final double km = distanceMeters / 1000.0;
    final double h = durationSeconds / 3600.0;
    if (h <= 0) return "0,0";
    return (km / h).toStringAsFixed(1).replaceAll('.', ',');
  }

  String _calculateDehydration(int durationSeconds) {
    // placeholder gamer: 10ml/min
    final double ml = (durationSeconds / 60.0) * 10.0;
    return ml.toStringAsFixed(0);
  }

  String _formatDate(DateTime date) {
    const meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final dia = date.day;
    final mes = meses[date.month - 1];
    final ano = date.year;
    final hora = date.hour.toString().padLeft(2, '0');
    final minuto = date.minute.toString().padLeft(2, '0');
    return "$dia de $mes. de $ano, $hora:$minuto";
  }

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  Future<void> _toggleArchive({
    required bool archived,
    required RunModel corrida,
  }) async {
    final theme = SeasonThemeScope.of(context);

    final isArchiving = !archived;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.card,
        surfaceTintColor: theme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isArchiving ? "Arquivar corrida" : "Desarquivar corrida",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          isArchiving
              ? "Deseja arquivar esta corrida?\n"
              "Ela ficará oculta do seu feed e estatísticas públicas, "
              "mas permanecerá salva no seu histórico pessoal."
              : "Deseja desarquivar esta corrida?\n"
              "Ela voltará a aparecer no seu feed e estatísticas públicas.",
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isArchiving ? "Arquivar" : "Desarquivar", style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // ✅ Preferencial: por ID
      if (corrida.id != null) {
        await FirebaseFirestore.instance.collection('corridas').doc(corrida.id!).update({'isArchived': isArchiving});
      } else {
        // fallback (sem id)
        final query = await FirebaseFirestore.instance
            .collection('corridas')
            .where('userId', isEqualTo: corrida.userId)
            .where('createdAt', isEqualTo: Timestamp.fromDate(corrida.date))
            .get();

        if (query.docs.isEmpty) {
          throw Exception('Corrida não encontrada.');
        }

        for (var doc in query.docs) {
          await doc.reference.update({'isArchived': isArchiving});
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArchiving ? '📦 Corrida arquivada com sucesso!' : '✅ Corrida desarquivada com sucesso!',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: theme.card,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e', style: const TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: theme.destructive,
        ),
      );
    }
  }

  // ─────────────────────────────
  // UI
  // ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final corrida = widget.corrida;
    final bool isOwner = user?.uid == corrida.userId;

    // ✅ Sem ID: não tem como saber o status em tempo real aqui, assume false
    if (corrida.id == null) {
      return _buildScaffold(
        context: context,
        corrida: corrida,
        isOwner: isOwner,
        runData: null,
        archived: false,
      );
    }

    // ✅ Com ID: lê o doc e usa o status real do Firestore para trocar o menu
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _runDocStream(corrida.id!),
      builder: (context, snap) {
        final data = snap.data?.data();
        final bool archived = (data?['isArchived'] == true);

        return _buildScaffold(
          context: context,
          corrida: corrida,
          isOwner: isOwner,
          runData: data,
          archived: archived,
        );
      },
    );
  }

  Scaffold _buildScaffold({
    required BuildContext context,
    required RunModel corrida,
    required bool isOwner,
    required Map<String, dynamic>? runData,
    required bool archived,
  }) {
    final theme = SeasonThemeScope.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.background,
        surfaceTintColor: theme.background,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.foreground),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isOwner ? (user?.displayName?.toUpperCase() ?? 'MINHA CORRIDA') : 'CORRIDA',
          style: GoogleFonts.poppins(
            color: theme.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          if (isOwner)
            IconButton(
              icon: Icon(Icons.ios_share_outlined, color: theme.foreground),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetalheCorridaPageShare(corrida: corrida),
                  ),
                );
              },
            ),
          if (isOwner)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: theme.foreground),
              color: theme.popover,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) async {
                if (value == 'toggleArchive') {
                  await _toggleArchive(archived: archived, corrida: corrida);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggleArchive',
                  child: Row(
                    children: [
                      Icon(
                        archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                        color: theme.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        archived ? "Desarquivar corrida" : "Arquivar corrida",
                        style: TextStyle(color: theme.popoverForeground, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _content(context, corrida, runData, isOwner),
      ),
    );
  }

  Widget _content(BuildContext context, RunModel corrida, Map<String, dynamic>? runData, bool isOwner) {
    final theme = SeasonThemeScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CORRIDA',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: theme.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatDate(corrida.date),
          style: GoogleFonts.poppins(
            color: theme.mutedForeground,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),

        _weatherInfo(runData),
        const SizedBox(height: 16),

        _mapPreview(corrida),
        const SizedBox(height: 24),

        _statsGrid(corrida, runData),
        const SizedBox(height: 18),

        if (isOwner && runData != null && runData['xpEarned'] != null && runData['rewardDoubled'] != true)
          _doubleRewardButton(runData),

        if (corrida.id != null) ...[
          _samplesCard(corrida.id!),
          const SizedBox(height: 18),
          _moreDetailsButton(corrida.id!),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _weatherInfo(Map<String, dynamic>? runData) {
    final theme = SeasonThemeScope.of(context);

    final w = runData?['weather'];
    final weather = (w is Map) ? w : null;

    final int? code = weather?['code'] as int?;
    final String condition = (weather?['condition'] ?? 'Tempo indisponível').toString();
    final double? temp = weather?['tempC'] is num ? (weather!['tempC'] as num).toDouble() : null;

    final icon = (code != null) ? WeatherIconHelper.iconFromCode(code) : Icons.help_outline;

    // cores do helper são "neutras", mas a UI usa o theme
    final tempText = temp != null ? "${temp.toStringAsFixed(0)} °C" : "— °C";

    return _Card(
      child: Row(
        children: [
          Icon(icon, color: theme.accent, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$condition • $tempText",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: theme.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Tempo',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: theme.mutedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moreDetailsButton(String runId) {
    final theme = SeasonThemeScope.of(context);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: theme.accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        icon: const Icon(Icons.insights_outlined),
        label: Text('Mais detalhes', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaisDetalhesPage(runId: runId),
            ),
          );
        },
      ),
    );
  }

  Widget _doubleRewardButton(Map<String, dynamic> runData) {
    final theme = SeasonThemeScope.of(context);
    final xpEarned = (runData['xpEarned'] as num).toInt();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orangeAccent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: _isAdLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              )
            : const Icon(Icons.video_library),
        label: Text(
          _isAdLoading ? 'Carregando anúncio...' : 'Dobrar XP e Pontos (+$xpEarned XP)',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        onPressed: _isAdLoading ? null : () => _showAdAndDoubleReward(xpEarned, widget.corrida.id!),
      ),
    );
  }

  Future<void> _showAdAndDoubleReward(int xp, String runId) async {
    if (!RewardedAdService().isAdLoaded) {
      setState(() => _isAdLoading = true);
      RewardedAdService().loadRewardedAd();
      await Future.delayed(const Duration(seconds: 2));
      setState(() => _isAdLoading = false);

      if (!RewardedAdService().isAdLoaded) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anúncio não disponível no momento. Tente novamente.')),
          );
        }
        return;
      }
    }

    RewardedAdService().showRewardedAd(
      onUserEarnedReward: (ad, reward) async {
        await GamificationService().addPoints(
          points: xp,
          source: "Recompensa de Vídeo",
          description: "Bônus por assistir anúncio na corrida $runId",
          context: context,
        );

        await FirebaseFirestore.instance.collection('corridas').doc(runId).update({
          'rewardDoubled': true,
          'xpEarned': FieldValue.increment(xp),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Recompensa dobrada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
    );
  }

  Widget _samplesCard(String runId) {
    final theme = SeasonThemeScope.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _samplesStream(runId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _Card(
            child: Text(
              "📊 Samples ainda não disponíveis.",
              style: GoogleFonts.poppins(color: theme.mutedForeground, fontWeight: FontWeight.w700),
            ),
          );
        }

        final last = docs.last.data();
        final lastSpeed = (_asDouble(last['speedKmh']) ?? 0.0);
        final lastAlt = (_asDouble(last['alt']) ?? 0.0);
        final lastT = (last['t'] as int?) ?? (last['t'] as num?)?.toInt() ?? 0;

        return _Card(
          child: Row(
            children: [
              Icon(Icons.timeline, color: theme.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Samples: ${docs.length}  •  Último t=$lastT s  •  Vel ${_formatNum1(lastSpeed)} km/h  •  Alt ${_formatNum0(lastAlt)} m",
                  style: GoogleFonts.poppins(fontSize: 13, color: theme.foreground, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────
  // MAP
  // ─────────────────────────────
  Widget _mapPreview(RunModel corrida) {
    final theme = SeasonThemeScope.of(context);

    if (corrida.route.isEmpty) {
      return _Card(
        padding: 0,
        child: SizedBox(
          height: 220,
          child: Center(
            child: Text(
              "Sem dados de rota",
              style: GoogleFonts.poppins(color: theme.mutedForeground, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    final List<LatLng> routePoints = corrida.route.map((p) => LatLng(p['lat']!, p['lng']!)).toList();
    final LatLng start = routePoints.first;
    final LatLng end = routePoints.last;

    return FutureBuilder<String>(
      future: rootBundle.loadString('assets/map_style.json'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: theme.accent));
        }

        final mapStyle = snapshot.data!;
        final bounds = _calculateBounds(routePoints);

        return _Card(
          padding: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 250,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: routePoints.isNotEmpty ? routePoints.first : const LatLng(0, 0),
                  zoom: 15,
                ),
                onMapCreated: (GoogleMapController controller) {
                  controller.setMapStyle(mapStyle);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
                  });
                },
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('rota_corrida'),
                    color: theme.accent,
                    width: 5,
                    points: routePoints,
                  ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('inicio'),
                    position: start,
                    infoWindow: const InfoWindow(title: 'Início'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                  ),
                  Marker(
                    markerId: const MarkerId('fim'),
                    position: end,
                    infoWindow: const InfoWindow(title: 'Fim'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  ),
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
              ),
            ),
          ),
        );
      },
    );
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // ─────────────────────────────
  // STATS GRID
  // ─────────────────────────────
  Widget _statsGrid(RunModel corrida, Map<String, dynamic>? runData) {
    final theme = SeasonThemeScope.of(context);

    final avgSpeedKmh = _asDouble(runData?['avgSpeedKmh']);
    final currentSpeedKmh = _asDouble(runData?['currentSpeedKmh']);

    final elevationGain = _asDouble(runData?['elevationGain']);
    final minElevation = _asDouble(runData?['minElevation']);
    final maxElevation = _asDouble(runData?['maxElevation']);

    // placeholders para futuro (sensores)
    final heartRate = _asDouble(runData?['heartRateAvg']); // bpm
    final cadence = _asDouble(runData?['cadenceAvg']); // spm
    final stride = _asDouble(runData?['strideLengthAvg']); // m
    final gct = _asDouble(runData?['gctAvg']); // ms
    final vo = _asDouble(runData?['verticalOscillationAvg']); // cm
    final vo2 = _asDouble(runData?['vo2Max']); // ml/kg/min
    final power = _asDouble(runData?['runningPowerAvg']); // W

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.35,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _StatTile(
          icon: Icons.map_outlined,
          value: (corrida.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
          unit: 'km',
          label: 'Distância',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.timer_outlined,
          value: _formatDuration(corrida.duration),
          label: 'Duração',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.speed_outlined,
          value: _formatPace(corrida.pace ?? 0),
          unit: 'min/km',
          label: 'Ritmo médio',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.local_fire_department_outlined,
          value: corrida.calories?.toStringAsFixed(0) ?? '0',
          unit: 'kcal',
          label: 'Calorias',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.trending_up_outlined,
          value: (avgSpeedKmh != null) ? _formatNum1(avgSpeedKmh) : _calculateSpeed(corrida.distance, corrida.duration),
          unit: 'km/h',
          label: 'Velocidade média',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.sports_motorsports_outlined,
          value: (currentSpeedKmh != null) ? _formatNum1(currentSpeedKmh) : '0,0',
          unit: 'km/h',
          label: 'Velocidade final',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.terrain_outlined,
          value: _formatNum0(elevationGain ?? 0.0),
          unit: 'm',
          label: 'Ganho elevação',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.height_outlined,
          value: "${_formatNum0(minElevation ?? 0.0)} / ${_formatNum0(maxElevation ?? 0.0)}",
          unit: 'm',
          label: 'Alt (min/max)',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.water_drop_outlined,
          value: _calculateDehydration(corrida.duration),
          unit: 'ml',
          label: 'Desidratação',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.favorite_border,
          value: (heartRate != null) ? _formatNum0(heartRate) : '—',
          unit: 'bpm',
          label: 'FC média',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.directions_run_outlined,
          value: (cadence != null) ? _formatNum0(cadence) : '—',
          unit: 'spm',
          label: 'Cadência',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.straighten_outlined,
          value: (stride != null) ? _formatNum1(stride) : '—',
          unit: 'm',
          label: 'Passada média',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.timer_sharp,
          value: (gct != null) ? _formatNum0(gct) : '—',
          unit: 'ms',
          label: 'Contato solo',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.swap_vert,
          value: (vo != null) ? _formatNum1(vo) : '—',
          unit: 'cm',
          label: 'Oscilação',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.local_activity_outlined,
          value: (vo2 != null) ? _formatNum1(vo2) : '—',
          unit: 'VO2',
          label: 'VO2 Max',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
        _StatTile(
          icon: Icons.bolt_outlined,
          value: (power != null) ? _formatNum0(power) : '—',
          unit: 'W',
          label: 'Potência',
          accent: theme.accent,
          fg: theme.foreground,
          muted: theme.mutedForeground,
          card: theme.card,
          border: theme.border,
        ),
      ],
    );
  }
}

// ─────────────────────────────
// UI helpers
// ─────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final double padding;

  const _Card({required this.child, this.padding = 14});

  @override
  Widget build(BuildContext context) {
    final theme = SeasonThemeScope.of(context);

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? unit;
  final String label;

  // theme tokens (evita ficar chamando scope em excesso dentro do Grid)
  final Color accent;
  final Color fg;
  final Color muted;
  final Color card;
  final Color border;

  const _StatTile({
    required this.icon,
    required this.value,
    this.unit,
    required this.label,
    required this.accent,
    required this.fg,
    required this.muted,
    required this.card,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: fg,
                        ),
                      ),
                    ),
                    if (unit != null) const SizedBox(width: 6),
                    if (unit != null)
                      Text(
                        unit!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WeatherIconHelper {
  static IconData iconFromCode(int code) {
    // Open-Meteo weather codes
    if (code == 0) return Icons.wb_sunny_outlined;
    if (code >= 1 && code <= 3) return Icons.wb_cloudy_outlined;
    if (code == 45 || code == 48) return Icons.cloud_outlined; // neblina
    if (code >= 51 && code <= 57) return Icons.grain; // garoa
    if (code >= 61 && code <= 67) return Icons.umbrella_outlined; // chuva
    if (code >= 71 && code <= 77) return Icons.ac_unit_outlined; // neve
    if (code >= 80 && code <= 82) return Icons.beach_access_outlined; // pancadas
    if (code == 95) return Icons.thunderstorm_outlined;
    if (code == 96 || code == 99) return Icons.flash_on_outlined; // granizo
    return Icons.help_outline;
  }
}
