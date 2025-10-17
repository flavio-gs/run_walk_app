import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'model/run_model.dart';
import 'package:flutter/services.dart';
import 'dart:ui';



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

    final points = route.map((p) => LatLng(p['lat']!, p['lng']!)).toList();

    _polylines.add(Polyline(
      polylineId: const PolylineId('trajeto'),
      color: const Color(0xFFFF6D00),
      width: 6,
      points: points,
    ));

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
      strokeColor: const Color(0xFF00C853).withOpacity(0.8),
      fillColor: const Color(0xFF00C853).withOpacity(0.2),
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
      backgroundColor: Colors.black,
      // 🌈 APPBAR MINIMALISTA + EFEITO GLASS PREMIUM
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80), // altura ligeiramente maior
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), // mais espaçamento interno
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 🔮 Fundo translúcido com efeito "glass"
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      height: 55, // altura do painel de vidro
                      color: Colors.black.withOpacity(0.28),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),

                // 🔙 Botão flutuante de voltar
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      HapticFeedback.selectionClick();
                    },
                    child: Container(
                      height: 44,
                      width: 44,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.35),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00C853).withOpacity(0.35),
                            blurRadius: 10,
                            spreadRadius: -2,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: const Color(0xFFFF6D00).withOpacity(0.35),
                            blurRadius: 10,
                            spreadRadius: -2,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),

                // 🏁 Título centralizado com respiro e brilho leve
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Detalhes da Corrida",
                    style: GoogleFonts.russoOne(
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        shadows: [
                          Shadow(
                            blurRadius: 5,
                            color: Colors.black54,
                            offset: Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

          // 🔮 Gradiente sutil de fundo para contraste
          IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromARGB(80, 0, 200, 83),
                    Color.fromARGB(40, 255, 109, 0),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),

          // Painel inferior
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF00C853).withOpacity(0.4), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C853).withOpacity(0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Corrida em ${_formatarData(corrida.date)}",
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 12),
                  Container(
                    height: 4,
                    width: 110,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
                      ),
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

  String _formatarData(DateTime date) {
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    final ano = date.year.toString();
    final hora = date.hour.toString().padLeft(2, '0');
    final minuto = date.minute.toString().padLeft(2, '0');
    return "$dia/$mes/$ano $hora:$minuto";
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
          style: GoogleFonts.orbitron(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 1.1,
            shadows: [
              const Shadow(
                  blurRadius: 8, color: Color(0xFF00C853), offset: Offset(0, 0))
            ],
          ),
        ),
        const SizedBox(height: 3),
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
