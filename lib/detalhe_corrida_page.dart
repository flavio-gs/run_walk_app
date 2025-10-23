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
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';



class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
  final List<String> backgrounds = [
    'https://images.unsplash.com/photo-1508609349937-5ec4ae374ebf?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
    'https://images.unsplash.com/photo-1505678261036-a3fcc5e884ee?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
    'https://images.unsplash.com/photo-1605296867304-46d5465a13f1?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
  ];

  VideoPlayerController? _videoController;
  bool isVideo = false;


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

    // 🖼️ Fundo (detecta URL ou arquivo local)
    ui.Image bgImage;
    if (backgroundUrl.startsWith('http')) {
      final imageData =
      (await NetworkAssetBundle(Uri.parse(backgroundUrl)).load("")).buffer.asUint8List();
      final codec =
      await ui.instantiateImageCodec(imageData, targetWidth: width, targetHeight: height);
      final frame = await codec.getNextFrame();
      bgImage = frame.image;
    } else {
      final fileData = await File(backgroundUrl).readAsBytes();
      final codec =
      await ui.instantiateImageCodec(fileData, targetWidth: width, targetHeight: height);
      final frame = await codec.getNextFrame();
      bgImage = frame.image;
    }
    canvas.drawImage(bgImage, Offset.zero, Paint());

    // 🌫️ Fundo branco translúcido na parte inferior (mesmo do preview)
    final overlayRect = Rect.fromLTWH(0, height - 450, width.toDouble(), 450);
    canvas.drawRect(
      overlayRect,
      Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.40),
    );


    // ✍️ Helper para texto
    void drawText(
        String text,
        double size,
        Offset offset, {
          FontWeight weight = FontWeight.w600,
          Color color = Colors.black,
        }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            fontFamily: 'Poppins',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, offset);
    }

    // 🧩 Carrega logo Runner branca (local asset)
    final logoData = await rootBundle.load('assets/icon/logo_principal.png');
    final logoCodec = await ui.instantiateImageCodec(logoData.buffer.asUint8List(),
        targetWidth: 280); // tamanho ajustado
    final logoFrame = await logoCodec.getNextFrame();
    final logo = logoFrame.image;

    // 🏁 Cabeçalho (logo no topo direito)
    final logoOffset = Offset(width - 350, 120);
    canvas.drawImage(logo, logoOffset, Paint());

    // 🔹 Título principal
    drawText("CORRIDA", 58, Offset(60, height - 400),
        weight: FontWeight.w700, color: Colors.deepOrange);

    // 🔹 Cálculos
    final dist = "${(corrida.distance / 1000).toStringAsFixed(2)} km";
    final duracao = _formatDuration(corrida.duration);
    final ritmo = _calcularRitmo(corrida.distance, corrida.duration);

    final colY = height - 280.0;
    final labelColor = Colors.deepOrange;

    // 📊 Colunas de dados
    drawText(dist, 50, Offset(60, colY), weight: FontWeight.bold);
    drawText("Distância", 28, Offset(60, colY + 60), color: labelColor);

    drawText(duracao, 50, Offset(width / 3 + 10, colY), weight: FontWeight.bold);
    drawText("Duração", 28, Offset(width / 3 + 10, colY + 60), color: labelColor);

    drawText(ritmo, 50, Offset(width / 1.7 + 60, colY - 10),
        weight: FontWeight.bold);
    drawText("Ritmo Médio", 28, Offset(width / 1.7 + 60, colY + 50),
        color: labelColor);

// 🗺️ Traçado da rota (laranja Runner) — ajustado para não sobrepor o texto
    final double routeSize = 240;
    final double routeRightMargin = 100;
    final double routeBottomMargin = 600;

    final routeRect = Rect.fromLTWH(
      width - routeSize - routeRightMargin,
      height - routeSize - routeBottomMargin,
      routeSize,
      routeSize,
    );

// calcula o centro da rota (lat/lng médios)
    final centerLat = corrida.route.map((p) => p['lat']!).reduce((a, b) => a + b) / corrida.route.length;
    final centerLng = corrida.route.map((p) => p['lng']!).reduce((a, b) => a + b) / corrida.route.length;

// gera o mapa estático real (Yandex Maps — leve, sem API key)
    final mapUrl =
        "https://static-maps.yandex.ru/1.x/?ll=$centerLng,$centerLat&z=15&size=450,450&l=map";

    try {
      final mapBytes = (await NetworkAssetBundle(Uri.parse(mapUrl)).load("")).buffer.asUint8List();
      final mapCodec = await ui.instantiateImageCodec(
        mapBytes,
        targetWidth: routeRect.width.toInt(),
        targetHeight: routeRect.height.toInt(),
      );
      final mapFrame = await mapCodec.getNextFrame();
      final mapImage = mapFrame.image;

      // cria máscara radial para fade (bordas suaves)
      final fadeShader = ui.Gradient.radial(
        routeRect.center,
        routeRect.width / 1.1,
        [
          Colors.white.withOpacity(1.0),
          Colors.white.withOpacity(0.0),
        ],
        [0.75, 1.0],
      );

      // salva camada para aplicar blend
      canvas.saveLayer(routeRect, Paint());

      // desenha mapa real
      canvas.drawImageRect(
        mapImage,
        Rect.fromLTWH(0, 0, mapImage.width.toDouble(), mapImage.height.toDouble()),
        routeRect,
        Paint(),
      );

      // aplica fade radial
      canvas.drawRect(
        routeRect,
        Paint()
          ..shader = fadeShader
          ..blendMode = BlendMode.dstIn,
      );

      canvas.restore();

      // === 💫 EFEITO LENTE 3D ===
      // cria gradiente elíptico na parte inferior (brilho e sombra)
      final lensShader = ui.Gradient.linear(
        Offset(routeRect.left, routeRect.bottom - 10),
        Offset(routeRect.right, routeRect.bottom),
        [
          Colors.white.withOpacity(0.25), // brilho inferior esquerdo
          Colors.black.withOpacity(0.15), // sombra inferior direita
        ],
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(routeRect.inflate(8), const Radius.circular(20)),
        Paint()
          ..shader = lensShader
          ..blendMode = BlendMode.overlay,
      );

      // borda e sombra suave externa
      canvas.drawRRect(
        RRect.fromRectAndRadius(routeRect.inflate(12), const Radius.circular(22)),
        Paint()
          ..color = Colors.black.withOpacity(0.08)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
      );

      // traçado Runner laranja
      _drawRoute(canvas, corrida.route, routeRect, color: const Color(0xFFFF6D00));
    } catch (e) {
      debugPrint("⚠️ Erro ao carregar mapa estático: $e");
    }



    // 📅 Data da corrida
    drawText("🏁 ${_formatarData(corrida.date)}", 32, Offset(60, height - 100),
        color: Colors.black54);

    // 🖼️ Finaliza
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }




  void _drawRoute(Canvas canvas, List<Map<String, double>> route, Rect rect,
      {Color color = Colors.black}) {
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                  Text(
                    "Criar Imagem",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black, // <- texto preto
                    ),
                  ),
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
                    // 🖼️ Preview com proporção variável (foto ou vídeo)
                    AspectRatio(
                      aspectRatio: ratio,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 🎥 Fundo — vídeo ou imagem
                            if (isVideo && _videoController != null && _videoController!.value.isInitialized)
                              FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoController!.value.size.width,
                                  height: _videoController!.value.size.height,
                                  child: VideoPlayer(_videoController!),
                                ),
                              )
                            else
                            // 📸 Fundo — imagem padrão
                              Container(
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: selectedBackground.startsWith('http')
                                        ? NetworkImage(selectedBackground)
                                        : FileImage(File(selectedBackground)) as ImageProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),

                            // 🔸 Container translúcido para legibilidade
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 260,
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ),

                            // 🔹 Conteúdo textual + dados
                            Positioned(
                              bottom: 50,
                              left: 20,
                              right: 20,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "CORRIDA",
                                    style: GoogleFonts.poppins(
                                      color: const Color(0xFFFF6D00),
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _infoItem("Distância",
                                          "${(corrida.distance / 1000).toStringAsFixed(2)} km"),
                                      _infoItem("Duração", _formatDuration(corrida.duration)),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          _infoItem("Ritmo Médio",
                                              _calcularRitmo(corrida.distance, corrida.duration)),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: 80,
                                            height: 80,
                                            child: CustomPaint(
                                              painter: _RoutePreviewPainter(corrida.route),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
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

                    // 🖼️ Seleção de fundos + botão de câmera (em primeiro lugar)
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: backgrounds.length + 1, // +1 para incluir o botão da câmera
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          // 📸 O primeiro item agora é o botão de adicionar imagem
                          if (i == 0) {
                            return GestureDetector(
                              onTap: _selecionarImagemPersonalizada,
                              child: Container(
                                width: 90,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFFF6D00), width: 2),
                                ),
                                child: const Center(
                                  child: Icon(Icons.add_a_photo, color: Color(0xFFFF6D00), size: 30),
                                ),
                              ),
                            );
                          }

                          // 🎨 Demais itens são as imagens padrão
                          final img = backgrounds[i - 1];
                          final selected = img == selectedBackground;
                          return GestureDetector(
                            onTap: () => setState(() => selectedBackground = img),
                            child: Container(
                              width: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? const Color(0xFFFF6D00) : Colors.transparent,
                                  width: 2,
                                ),
                                image: DecorationImage(
                                  image: NetworkImage(img),
                                  fit: BoxFit.cover,
                                ),
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
                border: const Border(
                  top: BorderSide(color: Colors.black12, width: 0.5),
                ),
              ),
              child: GestureDetector(
                onTap: sharing ? null : _compartilhar,
                child: Column(
                  children: [
                    Container(
                      height: 60,
                      width: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sharing ? Colors.grey[300] : const Color(0xFFFF6D00),
                      ),
                      child: const Icon(Icons.share, color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Compartilhar",
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600),
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

  String _calcularRitmo(double distanciaMetros, int duracaoSegundos) {
    if (distanciaMetros == 0 || duracaoSegundos == 0) return "--:--";
    final distanciaKm = distanciaMetros / 1000;
    final minutos = duracaoSegundos / 60;
    final ritmo = minutos / distanciaKm;
    final min = ritmo.floor();
    final seg = ((ritmo - min) * 60).round();
    return "${min.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')} min/km";
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.deepOrange,
            fontSize: 13,
          ),
        ),
      ],
    );
  }




  Future<void> _selecionarImagemPersonalizada() async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_camera_back, color: Colors.white),
                title: const Text("Gravar vídeo (10s)", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? video =
                  await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 10));
                  if (video != null) {
                    _videoController = VideoPlayerController.file(File(video.path))
                      ..initialize().then((_) {
                        setState(() {
                          selectedBackground = video.path;
                          isVideo = true;
                          _videoController!.setLooping(true);
                          _videoController!.play();
                        });
                      });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text("Tirar foto", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? foto = await picker.pickImage(source: ImageSource.camera);
                  if (foto != null) {
                    setState(() {
                      selectedBackground = foto.path;
                      isVideo = false;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text("Escolher da galeria", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? arquivo = await picker.pickMedia();
                  if (arquivo != null) {
                    final ext = arquivo.path.split('.').last.toLowerCase();
                    if (['mp4', 'mov', 'm4v'].contains(ext)) {
                      _videoController = VideoPlayerController.file(File(arquivo.path))
                        ..initialize().then((_) {
                          setState(() {
                            selectedBackground = arquivo.path;
                            isVideo = true;
                            _videoController!.setLooping(true);
                            _videoController!.play();
                          });
                        });
                    } else {
                      setState(() {
                        selectedBackground = arquivo.path;
                        isVideo = false;
                      });
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
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
