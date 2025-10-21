import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'model/run_model.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';


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

  final GlobalKey _repaintKey = GlobalKey();

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

  // 📸 Função para capturar o widget e compartilhar
  Future<void> _compartilharCorrida() async {
    try {
      // Captura o widget
      RenderRepaintBoundary boundary =
      _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Salva a imagem temporariamente
      final directory = await Directory.systemTemp.createTemp();
      final file = File("${directory.path}/corrida_${DateTime.now().millisecondsSinceEpoch}.png");
      await file.writeAsBytes(pngBytes);

      // Compartilha
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
        "🏃 Corrida concluída!\n${(widget.corrida.distance / 1000).toStringAsFixed(2)} km em ${_formatDuration(widget.corrida.duration)} 🏁\n#RunnerApp",
        subject: "Minha corrida no Runner",
      );
    } catch (e) {
      debugPrint("Erro ao capturar ou compartilhar: $e");
    }
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: SafeArea(
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 🔙 Voltar
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
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // 📤 Compartilhar
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _compartilharCorrida,
                    child: Container(
                      height: 44,
                      width: 44,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.35),
                      ),
                      child: const Icon(
                        Icons.ios_share,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // 🏁 Título
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Detalhes da Corrida",
                    style: GoogleFonts.russoOne(
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // 🌈 Corpo que será capturado
      body: RepaintBoundary(
        key: _repaintKey,
        child: Stack(
          children: [
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
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
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
                        _infoItem(
                            "Tempo", _formatDuration(corrida.duration)),
                        _infoItem("Ritmo",
                            _calcularRitmo(corrida.distance, corrida.duration)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "🏁 Feito com Runner App",
                      style: GoogleFonts.orbitron(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
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
