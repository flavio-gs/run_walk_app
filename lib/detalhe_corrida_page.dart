import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'model/run_model.dart';

class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;

  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
  final Completer<GoogleMapController> _controller = Completer();

  final Set<Polyline> _polylines = {};
  final Set<Polygon> _polygons = {};

  @override
  void initState() {
    super.initState();
    _montarMapa();
  }

  void _montarMapa() {
    final route = widget.corrida.route;
    if (route.isEmpty) return;

    final points =
    route.map((p) => LatLng(p['lat']!, p['lng']!)).toList();

    // Linha principal (trajeto)
    _polylines.add(Polyline(
      polylineId: const PolylineId('trajeto'),
      color: const Color(0xFFFF6D00),
      width: 5,
      points: points,
    ));

    // Polígono verde leve (território dominado)
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _polygons.add(Polygon(
      polygonId: const PolygonId('territorio'),
      points: [
        LatLng(minLat, minLng),
        LatLng(minLat, maxLng),
        LatLng(maxLat, maxLng),
        LatLng(maxLat, minLng),
      ],
      strokeWidth: 2,
      strokeColor: const Color(0xFF00C853).withOpacity(0.7),
      fillColor: const Color(0xFF00C853).withOpacity(0.15),
    ));
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final corrida = widget.corrida;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Detalhes da Corrida"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 🗺️ Mapa
          GoogleMap(
            mapType: MapType.normal,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylines,
            polygons: _polygons,
            initialCameraPosition: CameraPosition(
              target: _polylines.isNotEmpty
                  ? _polylines.first.points.first
                  : const LatLng(0, 0),
              zoom: 16,
            ),
            onMapCreated: (controller) => _controller.complete(controller),
          ),

          // Painel inferior
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Corrida em ${corrida.date.toLocal().toString().substring(0, 16)}",
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _infoItem("Distância",
                          "${(corrida.distance / 1000).toStringAsFixed(2)} km"),
                      _infoItem("Tempo", _formatDuration(corrida.duration)),
                      _infoItem("Ritmo",
                          _calcularRitmo(corrida.distance, corrida.duration)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 4,
                    width: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _calcularRitmo(double distancia, int duracao) {
    if (distancia == 0 || duracao == 0) return "--";
    final minutos = duracao / 60;
    final km = distancia / 1000;
    final ritmo = minutos / km;
    final min = ritmo.floor();
    final seg = ((ritmo - min) * 60).round();
    return "${min}m${seg.toString().padLeft(2, '0')}/km";
  }

  Widget _infoItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
