import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

import 'model/run_model.dart';
import 'run_share_overlay_editor.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class DetalheCorridaPageShare extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPageShare({super.key, required this.corrida});

  @override
  State<DetalheCorridaPageShare> createState() => _DetalheCorridaPageShareState();
}

class _DetalheCorridaPageShareState extends State<DetalheCorridaPageShare> {
  final List<String> backgrounds = const [
    'https://images.unsplash.com/photo-1508609349937-5ec4ae374ebf?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
    'https://images.unsplash.com/photo-1505678261036-a3fcc5e884ee?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
    'https://images.unsplash.com/photo-1605296867304-46d5465a13f1?crop=entropy&cs=tinysrgb&w=1080&h=1920&fit=crop',
  ];

  VideoPlayerController? _videoController;
  bool isVideo = false;

  late String selectedBackground;
  bool sharing = false;
  bool storyMode = false; // false = Feed (4:5), true = Story (9:16)

  @override
  void initState() {
    super.initState();
    selectedBackground = backgrounds[Random().nextInt(backgrounds.length)];
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
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

  // ✅ loader robusto pra URL (sem depender de NetworkAssetBundle.load(""))
  Future<Uint8List> _downloadUrlBytes(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'RunnerApp/1.0');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(res);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _salvarImagem() async {
    if (sharing) return;
    setState(() => sharing = true);

    try {
      final bytes = await _gerarImagemCompartilhamento(
        widget.corrida,
        selectedBackground,
        storyMode,
      );
      
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/runner_${DateTime.now().millisecondsSinceEpoch}.png");
      await file.writeAsBytes(bytes);

      final box = context.findRenderObject() as RenderBox?;
      final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      await Share.shareXFiles(
        [XFile(file.path, name: "corrida_runner.png")],
        sharePositionOrigin: rect,
      );
    } catch (e) {
      _mostrarErro("Erro ao salvar: $e");
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  Future<void> _compartilhar() async {
    if (sharing) return;
    setState(() => sharing = true);

    try {
      final bytes = await _gerarImagemCompartilhamento(
        widget.corrida,
        selectedBackground,
        storyMode,
      );
      
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/share_run.png");
      await file.writeAsBytes(bytes);

      final text = "🏃 Corrida concluída!\n"
                   "📏 ${(widget.corrida.distance / 1000).toStringAsFixed(2)} km\n"
                   "⏱️ ${_formatDuration(widget.corrida.duration)}\n"
                   "⚡ Ritmo: ${_calcularRitmo(widget.corrida.distance, widget.corrida.duration)}\n\n"
                   "#RunnerApp #CorridadeRua #Workout #Fitness";

      final box = context.findRenderObject() as RenderBox?;
      final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        subject: 'Minha Corrida no Runner App',
        sharePositionOrigin: rect,
      );
    } catch (e) {
      debugPrint("Erro ao compartilhar: $e");
      _mostrarErro("Erro ao compartilhar: $e");
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  void _mostrarErro(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Uint8List> _gerarImagemCompartilhamento(
      RunModel corrida,
      String backgroundUrl,
      bool story,
      ) async {
    final width = 1080;
    final height = story ? 1920 : 1350;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // 🖼️ Fundo (URL ou arquivo local)
    ui.Image bgImage;
    if (backgroundUrl.startsWith('http')) {
      final imageData = await _downloadUrlBytes(backgroundUrl);
      final codec = await ui.instantiateImageCodec(
        imageData,
        targetWidth: width,
        targetHeight: height,
      );
      final frame = await codec.getNextFrame();
      bgImage = frame.image;
    } else {
      final fileData = await File(backgroundUrl).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        fileData,
        targetWidth: width,
        targetHeight: height,
      );
      final frame = await codec.getNextFrame();
      bgImage = frame.image;
    }
    canvas.drawImage(bgImage, Offset.zero, Paint());

    // 🌫️ Faixa translúcida inferior
    final overlayRect = Rect.fromLTWH(0, height - 450, width.toDouble(), 450);
    canvas.drawRect(
      overlayRect,
      Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.40),
    );

    // ✍️ Helper de texto
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

    // 🧩 Logo
    final logoData = await rootBundle.load('assets/icon/logo_principal.png');
    final logoCodec = await ui.instantiateImageCodec(
      logoData.buffer.asUint8List(),
      targetWidth: 280,
    );
    final logoFrame = await logoCodec.getNextFrame();
    final logo = logoFrame.image;
    canvas.drawImage(logo, const Offset(1080 - 350, 120), Paint());

    // 🔹 Título
    drawText(
      "CORRIDA",
      58,
      Offset(60, height - 400),
      weight: FontWeight.w700,
      color: const Color(0xFFFF6D00),
    );

    // 🔹 Dados
    final dist = "${(corrida.distance / 1000).toStringAsFixed(2)} km";
    final duracao = _formatDuration(corrida.duration);
    final ritmo = _calcularRitmo(corrida.distance, corrida.duration);

    final colY = height - 280.0;
    const labelColor = Color(0xFFFF6D00);

    drawText(dist, 50, Offset(60, colY), weight: FontWeight.bold);
    drawText("Distância", 28, Offset(60, colY + 60), color: labelColor);

    drawText(duracao, 50, Offset(width / 3 + 10, colY), weight: FontWeight.bold);
    drawText("Duração", 28, Offset(width / 3 + 10, colY + 60), color: labelColor);

    drawText(ritmo, 50, Offset(width / 1.7 + 60, colY - 10), weight: FontWeight.bold);
    drawText("Ritmo Médio", 28, Offset(width / 1.7 + 60, colY + 50), color: labelColor);

    // 🗺️ Mini mapa + rota (só se tiver route)
    if (corrida.route.isNotEmpty) {
      final double routeSize = 240;
      final double routeRightMargin = 100;
      final double routeBottomMargin = 600;

      final routeRect = Rect.fromLTWH(
        width - routeSize - routeRightMargin,
        height - routeSize - routeBottomMargin,
        routeSize,
        routeSize,
      );

      final centerLat =
          corrida.route.map((p) => p['lat']!).reduce((a, b) => a + b) / corrida.route.length;
      final centerLng =
          corrida.route.map((p) => p['lng']!).reduce((a, b) => a + b) / corrida.route.length;

      final mapUrl =
          "https://static-maps.yandex.ru/1.x/?ll=$centerLng,$centerLat&z=15&size=450,450&l=map";

      try {
        final mapBytes = await _downloadUrlBytes(mapUrl);
        final mapCodec = await ui.instantiateImageCodec(
          mapBytes,
          targetWidth: routeRect.width.toInt(),
          targetHeight: routeRect.height.toInt(),
        );
        final mapFrame = await mapCodec.getNextFrame();
        final mapImage = mapFrame.image;

        final fadeShader = ui.Gradient.radial(
          routeRect.center,
          routeRect.width / 1.1,
          [Colors.white.withOpacity(1.0), Colors.white.withOpacity(0.0)],
          [0.75, 1.0],
        );

        canvas.saveLayer(routeRect, Paint());

        canvas.drawImageRect(
          mapImage,
          Rect.fromLTWH(0, 0, mapImage.width.toDouble(), mapImage.height.toDouble()),
          routeRect,
          Paint(),
        );

        canvas.drawRect(
          routeRect,
          Paint()
            ..shader = fadeShader
            ..blendMode = BlendMode.dstIn,
        );

        canvas.restore();

        final lensShader = ui.Gradient.linear(
          Offset(routeRect.left, routeRect.bottom - 10),
          Offset(routeRect.right, routeRect.bottom),
          [Colors.white.withOpacity(0.25), Colors.black.withOpacity(0.15)],
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(routeRect.inflate(8), const Radius.circular(20)),
          Paint()
            ..shader = lensShader
            ..blendMode = BlendMode.overlay,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(routeRect.inflate(12), const Radius.circular(22)),
          Paint()
            ..color = Colors.black.withOpacity(0.08)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
        );

        _drawRoute(canvas, corrida.route, routeRect, color: const Color(0xFFFF6D00));
      } catch (e) {
        debugPrint("⚠️ Erro ao carregar mapa estático: $e");
      }
    }

    // 📅 Data
    drawText(
      "🏁 ${_formatarData(corrida.date)}",
      32,
      Offset(60, height - 100),
      color: Colors.black54,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }

  void _drawRoute(Canvas canvas, List<Map<String, double>> route, Rect rect, {Color color = Colors.black}) {
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

    final latRange = (maxLat - minLat == 0) ? 0.0001 : (maxLat - minLat);
    final lngRange = (maxLng - minLng == 0) ? 0.0001 : (maxLng - minLng);

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
  Widget build(BuildContext context) {
    final theme = SeasonThemeScope.of(context);
    final corrida = widget.corrida;

    final ratio = storyMode ? (9 / 16) : (4 / 5);

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleButton(theme, Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                  Text(
                    "Criar Imagem",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: theme.foreground,
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: ratio,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: theme.card,
                          border: Border.all(color: theme.border.withOpacity(0.35)),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
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

                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 260,
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                            ),

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
                                      color: theme.accent,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _infoItem("Distância", "${(corrida.distance / 1000).toStringAsFixed(2)} km"),
                                      _infoItem("Duração", _formatDuration(corrida.duration)),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          _infoItem("Ritmo Médio", _calcularRitmo(corrida.distance, corrida.duration)),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: 80,
                                            height: 80,
                                            child: CustomPaint(
                                              painter: _RoutePreviewPainter(corrida.route, color: theme.accent),
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

                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _toggleButton(theme, "Feed", !storyMode, () => setState(() => storyMode = false)),
                          const SizedBox(width: 12),
                          _toggleButton(theme, "Story", storyMode, () => setState(() => storyMode = true)),
                        ],
                      ),
                    ),

                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: backgrounds.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return GestureDetector(
                              onTap: _selecionarImagemPersonalizada,
                              child: Container(
                                width: 90,
                                decoration: BoxDecoration(
                                  color: theme.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.accent, width: 2),
                                ),
                                child: Center(
                                  child: Icon(Icons.add_a_photo, color: theme.accent, size: 30),
                                ),
                              ),
                            );
                          }

                          final img = backgrounds[i - 1];
                          final selected = img == selectedBackground;

                          return GestureDetector(
                            onTap: () => setState(() {
                              selectedBackground = img;
                              isVideo = false;
                              _videoController?.dispose();
                              _videoController = null;
                            }),
                            child: Container(
                              width: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? theme.accent : Colors.transparent,
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

            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: theme.background,
                border: Border(top: BorderSide(color: theme.border.withOpacity(0.35), width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _bigAction(
                    theme,
                    icon: Icons.download_rounded,
                    label: "Salvar",
                    color: theme.primary,
                    fg: theme.primaryForeground,
                    onTap: sharing ? null : _salvarImagem,
                  ),
                  const SizedBox(width: 18),
                  _bigAction(
                    theme,
                    icon: Icons.share,
                    label: "Compartilhar",
                    color: theme.accent,
                    fg: theme.accentForeground,
                    onTap: sharing ? null : _compartilhar,
                  ),
                  const SizedBox(width: 18),
                  _bigAction(
                    theme,
                    icon: Icons.tune,
                    label: "Transparência\nCustomizada",
                    color: theme.secondary,
                    fg: theme.secondaryForeground,
                    onTap: sharing
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RunShareOverlayEditor(corrida: widget.corrida),
                        ),
                      );
                    },
                  ),
                ],
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
    final safeSeg = seg >= 60 ? 59 : seg;
    return "${min.toString().padLeft(2, '0')}:${safeSeg.toString().padLeft(2, '0')} min/km";
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
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: const Color(0xFFFF6D00),
            fontSize: 13,
            fontWeight: FontWeight.w700,
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
                  final XFile? video = await picker.pickVideo(
                    source: ImageSource.camera,
                    maxDuration: const Duration(seconds: 10),
                  );
                  if (video != null) {
                    _videoController?.dispose();
                    _videoController = VideoPlayerController.file(File(video.path));
                    await _videoController!.initialize();

                    if (!mounted) return;
                    setState(() {
                      selectedBackground = video.path;
                      isVideo = true;
                      _videoController!.setLooping(true);
                      _videoController!.play();
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
                    _videoController?.dispose();
                    _videoController = null;
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
                      _videoController?.dispose();
                      _videoController = VideoPlayerController.file(File(arquivo.path));
                      await _videoController!.initialize();

                      if (!mounted) return;
                      setState(() {
                        selectedBackground = arquivo.path;
                        isVideo = true;
                        _videoController!.setLooping(true);
                        _videoController!.play();
                      });
                    } else {
                      _videoController?.dispose();
                      _videoController = null;
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

  Widget _toggleButton(SeasonTheme theme, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? theme.accent : theme.card,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: theme.border.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: active ? theme.accentForeground : theme.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _circleButton(SeasonTheme theme, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: theme.card,
          shape: BoxShape.circle,
          border: Border.all(color: theme.border.withOpacity(0.35)),
        ),
        child: Icon(icon, color: theme.foreground),
      ),
    );
  }

  Widget _bigAction(
      SeasonTheme theme, {
        required IconData icon,
        required String label,
        required Color color,
        required Color fg,
        required VoidCallback? onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onTap == null ? theme.muted : color,
              border: Border.all(color: theme.border.withOpacity(0.35)),
            ),
            child: Icon(icon, color: onTap == null ? theme.mutedForeground : fg, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: theme.foreground,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// 🎨 Desenha o traçado da corrida (preview)
class _RoutePreviewPainter extends CustomPainter {
  final List<Map<String, double>> route;
  final Color color;
  _RoutePreviewPainter(this.route, {required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    final paint = Paint()
      ..color = color
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

    final latRange = (maxLat - minLat == 0) ? 0.0001 : (maxLat - minLat);
    final lngRange = (maxLng - minLng == 0) ? 0.0001 : (maxLng - minLng);

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
      oldDelegate.route != route || oldDelegate.color != color;
}
