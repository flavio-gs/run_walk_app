import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/share_run.dart';
import 'model/run_model.dart';
import 'mais_detalhes_page.dart'; // Importa a nova tela
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
  // --- HELPERS ---
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
    return "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  String _calculateSpeed(double distanceMeters, int durationSeconds) {
    if (durationSeconds == 0) return "0,0";
    final double distanceKm = distanceMeters / 1000;
    final double durationHours = durationSeconds / 3600;
    final double speedKmh = distanceKm / durationHours;
    return speedKmh.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _calculateDehydration(int durationSeconds) {
    final double ml = (durationSeconds / 60) * 10;
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

  // --- WIDGETS ---
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
                          .where('createdAt',
                          isEqualTo: Timestamp.fromDate(widget.corrida.date))
                          .get();

                      if (query.docs.isEmpty) {
                        throw Exception('Corrida não encontrada.');
                      }

                      for (var doc in query.docs) {
                        await doc.reference.update({'isArchived': true});
                      }

                      if (context.mounted) {
                        Navigator.pop(context); // Fecha a tela atual
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CORRIDA', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 24)),
            const SizedBox(height: 4),
            Text(_formatDate(corrida.date), style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 16),
            _weatherInfo(),
            const SizedBox(height: 16),
            _mapPreview(corrida),
            const SizedBox(height: 24),
            _statsGrid(corrida),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _weatherInfo() {
    return Row(
      children: [
        Icon(Icons.wb_cloudy_outlined, color: Colors.grey[700], size: 24),
        const SizedBox(width: 8),
        Text('Nublado 23 °C', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700])),
        const SizedBox(width: 4),
        Text('Tempo', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }

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

    final List<LatLng> routePoints = corrida.route
        .map((p) => LatLng(p['lat']!, p['lng']!))
        .toList();

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
                target: routePoints.isNotEmpty
                    ? routePoints.first
                    : const LatLng(0, 0),
                zoom: 15,
              ),
              onMapCreated: (GoogleMapController controller) {
                controller.setMapStyle(mapStyle);
                Future.delayed(const Duration(milliseconds: 300), () {
                  controller.animateCamera(
                    CameraUpdate.newLatLngBounds(bounds, 50),
                  );
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
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                ),
                Marker(
                  markerId: const MarkerId('fim'),
                  position: end,
                  infoWindow: const InfoWindow(title: 'Fim'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed),
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


  Widget _statsGrid(RunModel corrida) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.5,
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
          value: _calculateSpeed(corrida.distance, corrida.duration),
          unit: 'km/h',
          label: 'Velocidade média',
        ),
        _StatTile(
          icon: Icons.water_drop_outlined,
          value: _calculateDehydration(corrida.duration),
          unit: 'ml',
          label: 'Desidratação',
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

  const _StatTile({required this.icon, required this.value, this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: Colors.black87),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
                if (unit != null) const SizedBox(width: 4),
                if (unit != null)
                  Text(unit!, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}
