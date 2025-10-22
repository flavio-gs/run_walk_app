import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'model/run_model.dart';

class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
  final List<String> backgrounds = [
    // 🏃 Mulher correndo ao nascer do sol
    'https://images.unsplash.com/photo-1599058917212-d750089bc07d?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🌅 Homem correndo em estrada ao pôr do sol
    'https://images.unsplash.com/photo-1508609349937-5ec4ae374ebf?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🌇 Corrida urbana noturna
    'https://images.unsplash.com/photo-1579758629939-037fdd6b2a12?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🌄 Trilha em montanha (natureza)
    'https://images.unsplash.com/photo-1505678261036-a3fcc5e884ee?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🛣️ Estrada reta (minimalista)
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🏙️ Skyline urbano ao entardecer
    'https://images.unsplash.com/photo-1605296867304-46d5465a13f1?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🌌 Corrida noturna com iluminação azul
    'https://images.unsplash.com/photo-1571019613918-721f80be263d?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',

    // 🌳 Pista arborizada (verde e natural)
    'https://images.unsplash.com/photo-1558981359-219d6364c9c8?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
  ];

  late String selectedBackground;
  bool sharing = false;
  bool storyMode = false; // false = Feed, true = Story

  @override
  void initState() {
    super.initState();
    selectedBackground = backgrounds[Random().nextInt(backgrounds.length)];
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  String _formatarData(DateTime date) {
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    final ano = date.year.toString();
    return "$dia/$mes/$ano";
  }

  Future<void> _compartilhar() async {
    setState(() => sharing = true);

    try {
      final bytes =
      await _gerarImagemCompartilhamento(widget.corrida, selectedBackground, storyMode);
      final dir = await Directory.systemTemp.createTemp();
      final file = File("${dir.path}/runner_share.png");
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)],
          text:
          "🏃 Corrida concluída!\n${(widget.corrida.distance / 1000).toStringAsFixed(2)} km em ${_formatDuration(widget.corrida.duration)} 🏁\n#RunnerApp");
    } catch (e) {
      debugPrint("Erro ao compartilhar: $e");
    }

    setState(() => sharing = false);
  }

  Future<Uint8List> _gerarImagemCompartilhamento(
      RunModel corrida, String backgroundUrl, bool story) async {
    final width = 1080;
    final height = story ? 1920 : 1350;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // 🔹 Fundo
    final imageData = (await NetworkAssetBundle(Uri.parse(backgroundUrl)).load(""))
        .buffer
        .asUint8List();
    final codec = await ui.instantiateImageCodec(imageData, targetWidth: width, targetHeight: height);
    final frame = await codec.getNextFrame();
    canvas.drawImage(frame.image, Offset.zero, Paint());

    // 🔹 Escurece o fundo
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = Colors.black.withOpacity(0.35));

    // 🔹 Texto helper
    void drawText(String text, double size, Offset offset,
        {FontWeight weight = FontWeight.w600, TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              fontWeight: weight,
              fontFamily: 'Poppins',
            )),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout(maxWidth: width - 120);
      tp.paint(canvas, offset);
    }

    // 🔹 Cabeçalho
    drawText("RUNNER", 46, const Offset(60, 100), weight: FontWeight.bold);
    drawText("CORRIDA", 30, const Offset(60, 180), weight: FontWeight.w700);

    // 🔹 Dados
    final dist = "${(corrida.distance / 1000).toStringAsFixed(2)} km";
    final duracao = _formatDuration(corrida.duration);
    final calorias = "${((corrida.distance / 1000) * 60).toStringAsFixed(0)} kcal";

    drawText(dist, 70, const Offset(60, 260), weight: FontWeight.bold);
    drawText("Duração  $duracao", 34, const Offset(60, 400));
    drawText("Calorias  $calorias", 34, const Offset(60, 460));

    // 🔹 Mini mapa (pequeno canto inferior direito)
    final routeRect = story
        ? Rect.fromLTWH(width - 250, height - 350, 180, 180)
        : Rect.fromLTWH(width - 250, height - 250, 180, 180);
    _drawRoute(canvas, corrida.route, routeRect, color: const Color(0xFFFF6D00));

    // 🔹 Rodapé
    drawText("🏁 ${_formatarData(corrida.date)}", 32, Offset(60, height - 120));

    final pic = recorder.endRecording();
    final img = await pic.toImage(width, height);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  void _drawRoute(Canvas canvas, List<Map<String, double>> route, Rect rect,
      {Color color = Colors.white}) {
    if (route.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double minLat = route.first['lat']!;
    double maxLat = route.first['lat']!;
    double minLng = route.first['lng']!;
    double maxLng = route.first['lng']!;

    for (final p in route) {
      minLat = min(minLat, p['lat']!);
      maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!);
      maxLng = max(maxLng, p['lng']!);
    }

    final latRange = maxLat - minLat == 0 ? 0.0001 : maxLat - minLat;
    final lngRange = maxLng - minLng == 0 ? 0.0001 : maxLng - minLng;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final latNorm = (route[i]['lat']! - minLat) / latRange;
      final lngNorm = (route[i]['lng']! - minLng) / lngRange;
      final dx = rect.left + (lngNorm * rect.width);
      final dy = rect.bottom - (latNorm * rect.height);
      if (i == 0) path.moveTo(dx, dy);
      else path.lineTo(dx, dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  @override
  Widget build(BuildContext context) {
    final corrida = widget.corrida;
    final ratio = storyMode ? (9 / 16) : (4 / 5);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 🔙 Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                  Text("Criar Imagem",
                      style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            // 🔹 Conteúdo com rolagem (preview + seleção de fundo)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    // 🖼️ Preview com proporção variável
                    AspectRatio(
                      aspectRatio: ratio,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          image: DecorationImage(
                            image: NetworkImage(selectedBackground),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.black.withOpacity(0.25),
                              ),
                            ),

                            // 📊 Dados da corrida
                            Positioned(
                              left: 20,
                              bottom: 40,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "CORRIDA",
                                    style: GoogleFonts.poppins(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white),
                                  ),
                                  Text(
                                    "${(corrida.distance / 1000).toStringAsFixed(2)} km  •  ${_formatDuration(corrida.duration)}  •  ${((corrida.distance / 1000) * 60).toStringAsFixed(0)} kcal",
                                    style: GoogleFonts.poppins(
                                        color: Colors.white70, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),

                            // 🟠 Mini mapa canto inferior direito
                            Positioned(
                              right: 25,
                              bottom: 30,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: CustomPaint(
                                  painter: _RoutePreviewPainter(corrida.route),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 🔘 Alternar modo
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _toggleButton("Feed", !storyMode, () {
                            setState(() => storyMode = false);
                          }),
                          const SizedBox(width: 12),
                          _toggleButton("Story", storyMode, () {
                            setState(() => storyMode = true);
                          }),
                        ],
                      ),
                    ),

                    // 🖼️ Seleção de fundos
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: backgrounds.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final img = backgrounds[i];
                          final selected = img == selectedBackground;
                          return GestureDetector(
                            onTap: () => setState(() => selectedBackground = img),
                            child: Container(
                              width: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: selected
                                        ? Colors.blueAccent
                                        : Colors.transparent,
                                    width: 2),
                                image: DecorationImage(
                                    image: NetworkImage(img), fit: BoxFit.cover),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 🔘 Botão fixo de compartilhar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                border: const Border(
                  top: BorderSide(color: Colors.white24, width: 0.5),
                ),
              ),
              child: _shareButton(Icons.share, "Compartilhar", _compartilhar),
            ),
          ],
        ),
      ),
    );
  }


  Widget _toggleButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.blueAccent : Colors.grey[800],
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        width: 44,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.black),
      ),
    );
  }

  Widget _shareButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: sharing ? null : onTap,
      child: Column(
        children: [
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sharing ? Colors.grey : Colors.white,
            ),
            child: Icon(icon, color: Colors.black, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withOpacity(0.9))),
        ],
      ),
    );
  }
}

// 🎨 Desenha o traçado da corrida (preview)
class _RoutePreviewPainter extends CustomPainter {
  final List<Map<String, double>> route;
  _RoutePreviewPainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double minLat = route.first['lat']!;
    double maxLat = route.first['lat']!;
    double minLng = route.first['lng']!;
    double maxLng = route.first['lng']!;

    for (final p in route) {
      minLat = min(minLat, p['lat']!);
      maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!);
      maxLng = max(maxLng, p['lng']!);
    }

    final latRange = maxLat - minLat == 0 ? 0.0001 : maxLat - minLat;
    final lngRange = maxLng - minLng == 0 ? 0.0001 : maxLng - minLng;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final latNorm = (route[i]['lat']! - minLat) / latRange;
      final lngNorm = (route[i]['lng']! - minLng) / lngRange;
      final dx = lngNorm * size.width;
      final dy = size.height - (latNorm * size.height);
      if (i == 0) path.moveTo(dx, dy);
      else path.lineTo(dx, dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) =>
      oldDelegate.route != route;
}
