import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/share_run.dart';
import 'model/run_model.dart';
import 'mais_detalhes_page.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';


class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
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

  // ─────────────────────────────
  // UI
  // ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final corrida = widget.corrida;
    final bool isOwner = user?.uid == corrida.userId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isOwner ? (user?.displayName?.toUpperCase() ?? 'MINHA CORRIDA') : 'CORRIDA',
          style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.ios_share_outlined, color: Colors.black),
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
              icon: const Icon(Icons.more_horiz, color: Colors.black),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) async {
                if (value == 'archive') {
                  // ✅ Melhor: arquivar por ID quando disponível
                  if (widget.corrida.id != null) {
                    try {
                      await FirebaseFirestore.instance
                          .collection('corridas')
                          .doc(widget.corrida.id!)
                          .update({'isArchived': true});

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📦 Corrida arquivada com sucesso!'),
                            backgroundColor: Colors.blueGrey,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao arquivar: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                    return;
                  }

                  // fallback antigo (sem id)
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text("Arquivar corrida"),
                      content: const Text(
                        "Deseja arquivar esta corrida?\n"
                            "Ela será ocultada do seu feed e estatísticas públicas, "
                            "mas permanecerá salva no seu histórico pessoal.",
                      ),
                      actions: [
                        TextButton(
                          child: const Text("Cancelar"),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                          child: const Text("Arquivar"),
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      final query = await FirebaseFirestore.instance
                          .collection('corridas')
                          .where('userId', isEqualTo: widget.corrida.userId)
                          .where('createdAt', isEqualTo: Timestamp.fromDate(widget.corrida.date))
                          .get();

                      if (query.docs.isEmpty) {
                        throw Exception('Corrida não encontrada.');
                      }

                      for (var doc in query.docs) {
                        await doc.reference.update({'isArchived': true});
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📦 Corrida arquivada com sucesso!'),
                            backgroundColor: Colors.blueGrey,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao arquivar: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, color: Colors.blueGrey),
                      SizedBox(width: 8),
                      Text("Arquivar corrida"),
                    ],
                  ),
                ),
              ],
            )
        ],
      ),

      // ✅ Se tiver id, puxa métricas “oficiais” do Firestore
      body: (widget.corrida.id == null)
          ? SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _content(context, corrida, null),
      )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _runDocStream(widget.corrida.id!),
        builder: (context, snap) {
          final data = snap.data?.data();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: _content(context, corrida, data),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, RunModel corrida, Map<String, dynamic>? runData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CORRIDA', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 24)),
        const SizedBox(height: 4),
        Text(_formatDate(corrida.date), style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14)),
        const SizedBox(height: 16),

        _weatherInfo(runData),
        const SizedBox(height: 16),

        _mapPreview(corrida),
        const SizedBox(height: 24),

        _statsGrid(corrida, runData),
        const SizedBox(height: 18),

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
    final w = runData?['weather'];
    final weather = (w is Map) ? w : null;

    final int? code = weather?['code'] as int?;
    final String condition = (weather?['condition'] ?? 'Tempo indisponível').toString();
    final double? temp = weather?['tempC'] is num ? (weather!['tempC'] as num).toDouble() : null;

    final icon = (code != null)
        ? WeatherIconHelper.iconFromCode(code)
        : Icons.help_outline;

    final color = (code != null)
        ? WeatherIconHelper.colorFromCode(code)
        : Colors.grey;

    final tempText = temp != null ? "${temp.toStringAsFixed(0)} °C" : "— °C";

    return Row(
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 8),
        Text(
          "$condition $tempText",
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700]),
        ),
        const SizedBox(width: 6),
        Text(
          'Tempo',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }



  Widget _moreDetailsButton(String runId) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        icon: const Icon(Icons.insights_outlined),
        label: Text('Mais detalhes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaisDetalhesPage(runId: runId), // ✅ passa id pra ler samples
            ),
          );
        },
      ),
    );
  }

  Widget _samplesCard(String runId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _samplesStream(runId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              "📊 Samples ainda não disponíveis.",
              style: GoogleFonts.poppins(color: Colors.grey[700]),
            ),
          );
        }

        final last = docs.last.data();
        final lastSpeed = (_asDouble(last['speedKmh']) ?? 0.0);
        final lastAlt = (_asDouble(last['alt']) ?? 0.0);
        final lastT = (last['t'] as int?) ?? (last['t'] as num?)?.toInt() ?? 0;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              const Icon(Icons.timeline, color: Colors.black87),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Samples: ${docs.length}  •  Último t=$lastT s  •  Vel ${_formatNum1(lastSpeed)} km/h  •  Alt ${_formatNum0(lastAlt)} m",
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
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
    if (corrida.route.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          "Sem dados de rota",
          style: GoogleFonts.poppins(color: Colors.grey[600]),
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
          return const Center(child: CircularProgressIndicator());
        }

        final mapStyle = snapshot.data!;
        final bounds = _calculateBounds(routePoints);

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
                  color: Colors.blueAccent,
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
  // STATS GRID (todas as métricas novas)
  // ─────────────────────────────
  Widget _statsGrid(RunModel corrida, Map<String, dynamic>? runData) {
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
      childAspectRatio: 2.4,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _StatTile(
          icon: Icons.map_outlined,
          value: (corrida.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
          unit: 'km',
          label: 'Distância',
        ),
        _StatTile(
          icon: Icons.timer_outlined,
          value: _formatDuration(corrida.duration),
          label: 'Duração',
        ),
        _StatTile(
          icon: Icons.speed_outlined,
          value: _formatPace(corrida.pace ?? 0),
          unit: 'min/km',
          label: 'Ritmo médio',
        ),
        _StatTile(
          icon: Icons.local_fire_department_outlined,
          value: corrida.calories?.toStringAsFixed(0) ?? '0',
          unit: 'kcal',
          label: 'Calorias',
        ),

        _StatTile(
          icon: Icons.trending_up_outlined,
          value: (avgSpeedKmh != null) ? _formatNum1(avgSpeedKmh) : _calculateSpeed(corrida.distance, corrida.duration),
          unit: 'km/h',
          label: 'Velocidade média',
        ),
        _StatTile(
          icon: Icons.sports_motorsports_outlined,
          value: (currentSpeedKmh != null) ? _formatNum1(currentSpeedKmh) : '0,0',
          unit: 'km/h',
          label: 'Velocidade final',
        ),

        _StatTile(
          icon: Icons.terrain_outlined,
          value: _formatNum0(elevationGain ?? 0.0),
          unit: 'm',
          label: 'Ganho elevação',
        ),
        _StatTile(
          icon: Icons.height_outlined,
          value: "${_formatNum0(minElevation ?? 0.0)} / ${_formatNum0(maxElevation ?? 0.0)}",
          unit: 'm',
          label: 'Alt (min/max)',
        ),

        _StatTile(
          icon: Icons.water_drop_outlined,
          value: _calculateDehydration(corrida.duration),
          unit: 'ml',
          label: 'Desidratação',
        ),
        _StatTile(
          icon: Icons.favorite_border,
          value: (heartRate != null) ? _formatNum0(heartRate) : '—',
          unit: 'bpm',
          label: 'FC média',
        ),

        _StatTile(
          icon: Icons.directions_run_outlined,
          value: (cadence != null) ? _formatNum0(cadence) : '—',
          unit: 'spm',
          label: 'Cadência',
        ),
        _StatTile(
          icon: Icons.straighten_outlined,
          value: (stride != null) ? _formatNum1(stride) : '—',
          unit: 'm',
          label: 'Passada média',
        ),

        _StatTile(
          icon: Icons.timer_sharp,
          value: (gct != null) ? _formatNum0(gct) : '—',
          unit: 'ms',
          label: 'Contato solo',
        ),
        _StatTile(
          icon: Icons.swap_vert,
          value: (vo != null) ? _formatNum1(vo) : '—',
          unit: 'cm',
          label: 'Oscilação',
        ),

        _StatTile(
          icon: Icons.local_activity_outlined,
          value: (vo2 != null) ? _formatNum1(vo2) : '—',
          unit: 'VO2',
          label: 'VO2 Max',
        ),
        _StatTile(
          icon: Icons.bolt_outlined,
          value: (power != null) ? _formatNum0(power) : '—',
          unit: 'W',
          label: 'Potência',
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? unit;
  final String label;

  const _StatTile({
    required this.icon,
    required this.value,
    this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: Colors.black87),
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
                      style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (unit != null) const SizedBox(width: 6),
                  if (unit != null)
                    Text(
                      unit!,
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
              Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
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

  static Color colorFromCode(int code) {
    if (code == 0) return Colors.orangeAccent;
    if (code >= 1 && code <= 3) return Colors.blueGrey;
    if (code >= 51 && code <= 67) return Colors.blueAccent;
    if (code == 95 || code == 96 || code == 99) return Colors.deepPurple;
    return Colors.grey;
  }
}

