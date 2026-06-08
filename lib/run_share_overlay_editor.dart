import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'model/run_model.dart';

enum OverlayMetricType {
  logo,
  distance,
  duration,
  pace,
  avgSpeed,
  currentSpeed,
  calories,
  elevationGain,
  minElevation,
  maxElevation,
  startTime,
  endTime,
  date,
  weather,
  samplesChart,
  routeTrace,
}

class OverlayItem {
  final String id;
  final OverlayMetricType type;
  Offset pos;
  double scale;
  double rotation;

  OverlayItem({
    required this.id,
    required this.type,
    required this.pos,
    this.scale = 1.0,
    this.rotation = 0.0,
  });
}

/// 🎛️ Estilo do sticker (quadradinho)
class StickerStyle {
  bool showBackground;
  bool showBorder;

  Color backgroundColor;
  double backgroundOpacity;

  Color borderColor;
  double borderWidth;

  Color valueColor;
  Color labelColor;

  StickerStyle({
    required this.showBackground,
    required this.showBorder,
    required this.backgroundColor,
    required this.backgroundOpacity,
    required this.borderColor,
    required this.borderWidth,
    required this.valueColor,
    required this.labelColor,
  });

  StickerStyle copyWith({
    bool? showBackground,
    bool? showBorder,
    Color? backgroundColor,
    double? backgroundOpacity,
    Color? borderColor,
    double? borderWidth,
    Color? valueColor,
    Color? labelColor,
  }) {
    return StickerStyle(
      showBackground: showBackground ?? this.showBackground,
      showBorder: showBorder ?? this.showBorder,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      valueColor: valueColor ?? this.valueColor,
      labelColor: labelColor ?? this.labelColor,
    );
  }

  static StickerStyle defaultStyle() => StickerStyle(
    showBackground: true,
    showBorder: true,
    backgroundColor: Colors.white,
    backgroundOpacity: 0.92,
    borderColor: const Color(0xFFFF6D00),
    borderWidth: 2,
    valueColor: Colors.black,
    labelColor: const Color(0xFFFF6D00),
  );

  static StickerStyle cleanNoBox() => StickerStyle(
    showBackground: false,
    showBorder: false,
    backgroundColor: Colors.transparent,
    backgroundOpacity: 0.0,
    borderColor: Colors.transparent,
    borderWidth: 0,
    valueColor: Colors.white,
    labelColor: Colors.white70,
  );
}

class OverlayTemplate {
  final String id;
  final String name;
  final String subtitle;
  final StickerStyle style;
  final Set<OverlayMetricType> enabled;
  final List<OverlayItem> items;

  const OverlayTemplate({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.style,
    required this.enabled,
    required this.items,
  });
}



class RunShareOverlayEditor extends StatefulWidget {
  final RunModel corrida;

  const RunShareOverlayEditor({super.key, required this.corrida});

  @override
  State<RunShareOverlayEditor> createState() => _RunShareOverlayEditorState();
}

class _RunShareOverlayEditorState extends State<RunShareOverlayEditor> {
  static const _kOrange = Color(0xFFFF6D00);
  static const _kBg = Color(0xFF0B0B0B);
  static const _kChipOff = Color(0xFF1A1A1A);
  static const _kWhite = Colors.white;

  final _boundaryKey = GlobalKey();


  static const int canvasW = 1080;
  static const int canvasH = 1920;

  late final PageController _tplCtrl;
  int _tplIndex = 0;
  late final List<OverlayTemplate> _templates;


  late List<OverlayItem> items;

  /// ✅ logo sempre habilitada (obrigatória)
  late Set<OverlayMetricType> enabled;

  /// 🎛️ estilo global dos stickers (quadradinhos)
  StickerStyle _stickerStyle = StickerStyle.defaultStyle();

  /// samples (pra gráfico)
  List<double> _samplesSpeed = [];
  bool _loadingSamples = true;

  bool _isFullscreen = false;

  Future<void> _openFullscreenEditor() async {
    // remove o boundary da tela normal (pra não brigar com o GlobalKey)
    setState(() => _isFullscreen = true);
    await Future.delayed(Duration.zero);

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenOverlayEditor(
          canvasW: canvasW,
          canvasH: canvasH,
          boundaryKey: _boundaryKey,
          items: items,
          enabled: enabled,
          buildOverlayWidget: _buildOverlayWidget,
          onChanged: () => setState(() {}),
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _isFullscreen = false);
  }

  @override
  void initState() {
    super.initState();

    _tplCtrl = PageController(viewportFraction: 0.88);

    _templates = _buildTemplates();


    enabled = {
      OverlayMetricType.logo, // ✅ obrigatório
      OverlayMetricType.routeTrace,
      OverlayMetricType.distance,
      OverlayMetricType.duration,
      OverlayMetricType.pace,
      OverlayMetricType.samplesChart,
      OverlayMetricType.date,
    };

    items = [
      OverlayItem(id: 'logo', type: OverlayMetricType.logo, pos: const Offset(720, 120), scale: 1.0),
      OverlayItem(id: 'route', type: OverlayMetricType.routeTrace, pos: const Offset(660, 300), scale: 1.0),
      OverlayItem(id: 'distance', type: OverlayMetricType.distance, pos: const Offset(80, 1360), scale: 1.05),
      OverlayItem(id: 'duration', type: OverlayMetricType.duration, pos: const Offset(80, 1480), scale: 1.05),
      OverlayItem(id: 'pace', type: OverlayMetricType.pace, pos: const Offset(80, 1600), scale: 1.05),
      OverlayItem(id: 'chart', type: OverlayMetricType.samplesChart, pos: const Offset(560, 1470), scale: 1.0),
      OverlayItem(id: 'date', type: OverlayMetricType.date, pos: const Offset(80, 1750), scale: 0.95),
    ];

    _loadSamples();
    // ✅ aplica o primeiro template automaticamente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyTemplate(0);
    });
  }

  List<OverlayTemplate> _buildTemplates() {
    // Helper rápido pra criar item
    OverlayItem it(String id, OverlayMetricType t, double x, double y,
        {double s = 1.0, double r = 0.0}) {
      return OverlayItem(id: id, type: t, pos: Offset(x, y), scale: s, rotation: r);
    }

    // ✅ 1) Strava-like (igual a imagem: texto central + logo embaixo)
    final stravaLike = OverlayTemplate(
      id: "strava_like",
      name: "Padrão",
      subtitle: "Central • minimal • logo embaixo",
      style: StickerStyle.cleanNoBox().copyWith(
        valueColor: Colors.white,
        labelColor: Colors.white70,
      ),
      enabled: {
        OverlayMetricType.logo,
        OverlayMetricType.distance,
        OverlayMetricType.pace,
        OverlayMetricType.duration,
        OverlayMetricType.routeTrace, // ✅ vamos usar o “rabisco” também
      },
      items: [
        // ✅ BLOCO 1 (Distance) – centro horizontal
        it('distance', OverlayMetricType.distance, 400, 500, s: 1.0),

        // ✅ BLOCO 2 (Pace)
        it('pace', OverlayMetricType.pace, 300, 630, s: 1.0),

        // ✅ BLOCO 3 (Time)
        it('duration', OverlayMetricType.duration, 400, 780, s: 1.0),

        // ✅ Traçado (rabisco) acima do logo
        it('route', OverlayMetricType.routeTrace, 300, 1000, s: 1.0),

        // ✅ Logo bem embaixo central
        it('logo', OverlayMetricType.logo, 400, 1550, s: 1.5),
      ],
    );


    // ✅ 2) Story Gamer (seu estilo atual, com caixas)
    final gamerStory = OverlayTemplate(
      id: "gamer_story",
      name: "Story Gamer",
      subtitle: "Cards • gráfico • traçado",
      style: StickerStyle.defaultStyle(),
      enabled: {
        OverlayMetricType.logo,
        OverlayMetricType.routeTrace,
        OverlayMetricType.distance,
        OverlayMetricType.duration,
        OverlayMetricType.pace,
        OverlayMetricType.samplesChart,
        OverlayMetricType.date,
      },
      items: [
        it('logo', OverlayMetricType.logo, 720, 120, s: 1.0),
        it('route', OverlayMetricType.routeTrace, 660, 300, s: 1.0),
        it('distance', OverlayMetricType.distance, 80, 1360, s: 1.05),
        it('duration', OverlayMetricType.duration, 80, 1480, s: 1.05),
        it('pace', OverlayMetricType.pace, 80, 1600, s: 1.05),
        it('chart', OverlayMetricType.samplesChart, 560, 1470, s: 1.0),
        it('date', OverlayMetricType.date, 80, 1750, s: 0.95),
      ],
    );

    // ✅ 3) Minimal Bottom (tudo embaixo, bom pra deixar topo livre)
    final minimalBottom = OverlayTemplate(
      id: "minimal_bottom",
      name: "Minimal Bottom",
      subtitle: "Tudo embaixo • bem limpo",
      style: StickerStyle.cleanNoBox().copyWith(
        valueColor: Colors.white,
        labelColor: Colors.white70,
      ),
      enabled: {
        OverlayMetricType.logo,
        OverlayMetricType.distance,
        OverlayMetricType.duration,
        OverlayMetricType.pace,
        OverlayMetricType.date,
      },
      items: [
        it('distance', OverlayMetricType.distance, 80, 1460, s: 1.15),
        it('duration', OverlayMetricType.duration, 80, 1600, s: 1.15),
        it('pace', OverlayMetricType.pace, 80, 1740, s: 1.15),
        it('date', OverlayMetricType.date, 760, 1780, s: 0.9),
        it('logo', OverlayMetricType.logo, 760, 120, s: 0.95),
      ],
    );

    return [stravaLike, gamerStory, minimalBottom];
  }

  void _applyTemplate(int index) {
    final t = _templates[index];

    setState(() {
      _tplIndex = index;

      // aplica estilo + enabled + itens
      _stickerStyle = t.style;
      enabled = {...t.enabled}; // cópia
      items = t.items.map((e) => OverlayItem(
        id: e.id,
        type: e.type,
        pos: e.pos,
        scale: e.scale,
        rotation: e.rotation,
      )).toList();

      // ✅ garante logo sempre
      enabled.add(OverlayMetricType.logo);
      if (!items.any((i) => i.type == OverlayMetricType.logo)) {
        items.add(OverlayItem(
          id: 'logo',
          type: OverlayMetricType.logo,
          pos: const Offset(540, 1550),
          scale: 1.0,
        ));
      }
    });
  }



  Future<void> _loadSamples() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('corridas')
          .doc(widget.corrida.id)
          .collection('samples')
          .orderBy('createdAt')
          .limitToLast(80)
          .get();

      final speeds = <double>[];
      for (final d in snap.docs) {
        final data = d.data();
        final v = data['speedKmh'];
        if (v is num) speeds.add(v.toDouble());
      }

      if (!mounted) return;
      setState(() {
        _samplesSpeed = speeds;
        _loadingSamples = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSamples = false);
    }
  }

  Future<void> _exportAndSharePng() async {
    try {
      final png = await _exportTransparentPng();

      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/runner_overlay_${DateTime.now().millisecondsSinceEpoch}.png");
      await file.writeAsBytes(png);

      if (kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PNG gerado ✅ ${file.path}")),
        );
        return;
      }

      // ✅ CORREÇÃO: Adicionado sharePositionOrigin para evitar crash no iOS/iPad
      final box = context.findRenderObject() as RenderBox?;
      final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: "PNG transparente - Runner",
        sharePositionOrigin: rect,
      );
    } catch (e) {
      debugPrint("Erro ao exportar/compartilhar PNG: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erro ao gerar PNG 😕")),
      );
    }
  }

  Future<Uint8List> _exportTransparentPng() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ===========================
  // Helpers de texto
  // ===========================
  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  String _ritmoMedio() {
    final dist = widget.corrida.distance;
    final dur = widget.corrida.duration;
    if (dist <= 0 || dur <= 0) return "--:--";
    final km = dist / 1000.0;
    final paceMin = (dur / 60.0) / km;
    final m = paceMin.floor();
    final s = ((paceMin - m) * 60).round().clamp(0, 59);
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} min/km";
  }

  String _formatDate(DateTime date) =>
      "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

  String _formatTime(DateTime? dt) {
    if (dt == null) return "--:--";
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _metricText(OverlayMetricType t) {
    final c = widget.corrida;
    switch (t) {
      case OverlayMetricType.distance:
        return "${(c.distance / 1000).toStringAsFixed(2)} km";
      case OverlayMetricType.duration:
        return _formatDuration(c.duration);
      case OverlayMetricType.pace:
        return _ritmoMedio();
      case OverlayMetricType.avgSpeed:
        return "${(c.avgSpeedKmh ?? 0).toStringAsFixed(1)} km/h";
      case OverlayMetricType.currentSpeed:
        return "${(c.currentSpeedKmh ?? 0).toStringAsFixed(1)} km/h";
      case OverlayMetricType.calories:
        return "${(c.calories ?? 0).toStringAsFixed(0)} kcal";
      case OverlayMetricType.elevationGain:
        return "${(c.elevationGain ?? 0).toStringAsFixed(0)} m";
      case OverlayMetricType.minElevation:
        return "${(c.minElevation ?? 0).toStringAsFixed(0)} m";
      case OverlayMetricType.maxElevation:
        return "${(c.maxElevation ?? 0).toStringAsFixed(0)} m";
      case OverlayMetricType.startTime:
        return _formatTime(c.startTime);
      case OverlayMetricType.endTime:
        return _formatTime(c.endTime);
      case OverlayMetricType.date:
        return _formatDate(c.date);
      case OverlayMetricType.weather:
        final w = c.weather;
        return (w?['condition'] ?? 'Clima').toString();
      default:
        return "";
    }
  }

  String _metricLabel(OverlayMetricType t) {
    switch (t) {
      case OverlayMetricType.distance:
        return "Distância";
      case OverlayMetricType.duration:
        return "Duração";
      case OverlayMetricType.pace:
        return "Ritmo";
      case OverlayMetricType.avgSpeed:
        return "Vel. Média";
      case OverlayMetricType.currentSpeed:
        return "Vel. Atual";
      case OverlayMetricType.calories:
        return "Calorias";
      case OverlayMetricType.elevationGain:
        return "Ganho Alt.";
      case OverlayMetricType.minElevation:
        return "Alt. Mín";
      case OverlayMetricType.maxElevation:
        return "Alt. Máx";
      case OverlayMetricType.startTime:
        return "Início";
      case OverlayMetricType.endTime:
        return "Fim";
      case OverlayMetricType.date:
        return "Data";
      case OverlayMetricType.weather:
        return "Clima";
      case OverlayMetricType.samplesChart:
        return "Gráfico";
      case OverlayMetricType.logo:
        return "Logo";
      case OverlayMetricType.routeTrace:
        return "Traçado";
    }
  }

  // ===========================
  // Toggle: Logo é obrigatória
  // ===========================
  void _toggleMetric(OverlayMetricType t, bool on) {
    if (t == OverlayMetricType.logo) return; // ✅ nunca desliga

    setState(() {
      if (on) {
        enabled.add(t);
        if (!items.any((i) => i.type == t)) {
          items.add(
            OverlayItem(
              id: "${t.name}_${DateTime.now().millisecondsSinceEpoch}",
              type: t,
              pos: const Offset(120, 220),
            ),
          );
        }
      } else {
        enabled.remove(t);
        items.removeWhere((i) => i.type == t);
      }
    });
  }

  // ===========================
  // UI
  // ===========================
  @override
  Widget build(BuildContext context) {
    Widget checkerboard() => CustomPaint(
      painter: _CheckerPainter(),
      child: const SizedBox.expand(),
    );

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text("Imagem Customizada"),
        backgroundColor: _kBg,
        foregroundColor: _kWhite,
        actions: [
          IconButton(
            onPressed: _openFullscreenEditor,
            icon: const Icon(Icons.fullscreen_rounded),
            tooltip: "Expandir editor",
          ),
          IconButton(
            onPressed: _exportAndSharePng,
            icon: const Icon(Icons.download_rounded),
            tooltip: "Baixar PNG (Compartilhar)",
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔥 Templates (carrossel + bolinhas)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0E0E0E),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 64,
                  child: PageView.builder(
                    controller: _tplCtrl,
                    itemCount: _templates.length,
                    onPageChanged: _applyTemplate, // ✅ muda modelo ao scroll
                    itemBuilder: (context, i) {
                      final t = _templates[i];
                      final selected = i == _tplIndex;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFFF6D00) : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome, color: Colors.white.withOpacity(0.95), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      t.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // ✅ bolinhas (indicador)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_templates.length, (i) {
                    final on = i == _tplIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: on ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: on ? const Color(0xFFFF6D00) : Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),


          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: canvasW / canvasH,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      checkerboard(),

                      Center(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: !_isFullscreen
                              ? RepaintBoundary(
                            key: _boundaryKey,
                            child: SizedBox(
                              width: canvasW.toDouble(),
                              height: canvasH.toDouble(),
                              child: Stack(
                                children: [
                                  for (final it in items)
                                    if (enabled.contains(it.type))
                                      _OverlayDraggable(
                                        item: it,
                                        child: _buildOverlayWidget(it.type),
                                        onChanged: () => setState(() {}),
                                      ),
                                ],
                              ),
                            ),
                          )
                              : SizedBox(
                            width: canvasW.toDouble(),
                            height: canvasH.toDouble(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          _StylePanel(
            style: _stickerStyle,
            onChanged: (s) => setState(() => _stickerStyle = s),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0E0E0E),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in OverlayMetricType.values)
                    if (t != OverlayMetricType.logo)
                      if (t != OverlayMetricType.samplesChart || !_loadingSamples)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: FilterChip(
                            selected: enabled.contains(t),
                            label: Text(
                              _metricLabel(t),
                              style: TextStyle(
                                color: enabled.contains(t) ? Colors.white : Colors.white.withOpacity(0.88),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            backgroundColor: _kChipOff,
                            selectedColor: _kOrange,
                            checkmarkColor: Colors.white,
                            side: BorderSide(
                              color: enabled.contains(t) ? _kOrange : Colors.white12,
                              width: 1.2,
                            ),
                            onSelected: (v) => _toggleMetric(t, v),
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

  Widget _buildOverlayWidget(OverlayMetricType t) {
    // ✅ Logo (Strava-like precisa logo + versão "STRAVA" maior embaixo)
    if (t == OverlayMetricType.logo) {
      return const _StravaLogoWidget(); // criaremos abaixo
    }

    // ✅ routeTrace no strava = rabisco SEM FUNDO
    if (t == OverlayMetricType.routeTrace) {
      return SizedBox(
        width: 520,
        height: 520,
        child: CustomPaint(
          painter: _RouteOnlyPainter(widget.corrida.route),
        ),
      );
    }

    // ✅ se o template atual é o strava, usa blocos strava
    final isStrava = _templates[_tplIndex].id == "strava_like";
    if (isStrava) {
      return _StravaMetricBlock(
        label: _metricLabel(t),
        value: _metricText(t),
        labelColor: Colors.white70,
        valueColor: Colors.white,
      );
    }

    // normal (seu sistema atual)
    if (t == OverlayMetricType.samplesChart) {
      return _MiniSparkline(values: _samplesSpeed, title: "Velocidade", style: _stickerStyle);
    }

    return _MetricSticker(
      label: _metricLabel(t),
      value: _metricText(t),
      style: _stickerStyle,
    );
  }

}

// ===========================
// Widgets
// ===========================
class _MetricSticker extends StatelessWidget {
  final String label;
  final String value;
  final StickerStyle style;

  const _MetricSticker({
    required this.label,
    required this.value,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final bg = style.showBackground ? style.backgroundColor.withOpacity(style.backgroundOpacity) : Colors.transparent;

    final border = style.showBorder ? Border.all(color: style.borderColor, width: style.borderWidth) : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: border,
        boxShadow: style.showBackground
            ? const [BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 6))]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: style.valueColor,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: style.labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StravaLogoWidget extends StatelessWidget {
  const _StravaLogoWidget();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _LogoWidget(), // seu logo atual (imagem)
        SizedBox(height: 12),
      ],
    );
  }
}


class _StravaMetricBlock extends StatelessWidget {
  final String label; // Distance
  final String value; // 6.09 km
  final Color labelColor;
  final Color valueColor;

  const _StravaMetricBlock({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: labelColor,
            fontWeight: FontWeight.w700,
            fontSize: 26, // label pequeno, mas ainda grande
            height: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w900,
            fontSize: 84, // 🔥 valor bem grande (Strava-like)
            height: 0.95,
            letterSpacing: -1.0,
          ),
        ),
      ],
    );
  }
}


class _LogoWidget extends StatelessWidget {
  const _LogoWidget();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _loadLogo(),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox(width: 200, height: 80);
        return RawImage(image: snap.data, width: 260);
      },
    );
  }

  Future<ui.Image> _loadLogo() async {
    final logoData = await rootBundle.load('assets/icon/logo_transp.png');
    final codec = await ui.instantiateImageCodec(
      logoData.buffer.asUint8List(),
      targetWidth: 360,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

// ===========================
// Traçado “só o traçado”
// ===========================
class _RouteOnlyPainter extends CustomPainter {
  final List<Map<String, double>> route;
  _RouteOnlyPainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    double minLat = route.first['lat'] ?? 0;
    double maxLat = route.first['lat'] ?? 0;
    double minLng = route.first['lng'] ?? 0;
    double maxLng = route.first['lng'] ?? 0;

    for (final p in route) {
      final lat = p['lat'] ?? 0;
      final lng = p['lng'] ?? 0;
      minLat = min(minLat, lat);
      maxLat = max(maxLat, lat);
      minLng = min(minLng, lng);
      maxLng = max(maxLng, lng);
    }

    final latRange = (maxLat - minLat).abs() < 0.0000001 ? 0.0001 : (maxLat - minLat);
    final lngRange = (maxLng - minLng).abs() < 0.0000001 ? 0.0001 : (maxLng - minLng);

    const pad = 14.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final lat = route[i]['lat'] ?? 0;
      final lng = route[i]['lng'] ?? 0;

      final latNorm = (lat - minLat) / latRange;
      final lngNorm = (lng - minLng) / lngRange;

      final dx = pad + (lngNorm * w);
      final dy = pad + (h - (latNorm * h));

      if (i == 0) path.moveTo(dx, dy);
      else path.lineTo(dx, dy);
    }

    final glow = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawPath(path, glow);

    final paint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RouteOnlyPainter oldDelegate) => oldDelegate.route != route;
}

// ===========================
// Drag + scale + rotate
// ===========================
class _OverlayDraggable extends StatefulWidget {
  final OverlayItem item;
  final Widget child;
  final VoidCallback onChanged;

  const _OverlayDraggable({
    required this.item,
    required this.child,
    required this.onChanged,
  });

  @override
  State<_OverlayDraggable> createState() => _OverlayDraggableState();
}

class _OverlayDraggableState extends State<_OverlayDraggable> {
  Offset? _startFocal;
  Offset? _startPos;
  double _startScale = 1.0;
  double _startRotation = 0.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.item.pos.dx,
      top: widget.item.pos.dy,
      child: Transform.translate(
        // ✅ agora pos é o CENTRO do item
        offset: const Offset(0, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: (d) {
            _startFocal = d.localFocalPoint;
            _startPos = widget.item.pos;
            _startScale = widget.item.scale;
            _startRotation = widget.item.rotation;
          },
          onScaleUpdate: (d) {
            if (_startFocal != null && _startPos != null) {
              final delta = d.localFocalPoint - _startFocal!;
              widget.item.pos = _startPos! + delta;
            }
            widget.item.scale = (_startScale * d.scale).clamp(0.5, 3.0);
            widget.item.rotation = _startRotation + d.rotation;
            widget.onChanged();
          },
          child: Transform.rotate(
            angle: widget.item.rotation,
            transformHitTests: true,
            child: Transform.scale(
              scale: widget.item.scale,
              transformHitTests: true,
              alignment: Alignment.center,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

}

// ===========================
// Mini gráfico (sparkline) — também respeita estilo
// ===========================
class _MiniSparkline extends StatelessWidget {
  final List<double> values;
  final String title;
  final StickerStyle style;

  const _MiniSparkline({
    required this.values,
    required this.title,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final bg = style.showBackground ? style.backgroundColor.withOpacity(style.backgroundOpacity) : Colors.transparent;

    final border = style.showBorder ? Border.all(color: style.borderColor, width: style.borderWidth) : null;

    return Container(
      width: 360,
      height: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: border,
        boxShadow: style.showBackground
            ? const [BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 6))]
            : null,
      ),
      child: CustomPaint(
        painter: _SparklinePainter(values),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: style.labelColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> v;
  _SparklinePainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;

    final minV = v.reduce(min);
    final maxV = v.reduce(max);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final padTop = 26.0;
    final pad = 10.0;
    final w = size.width - pad * 2;
    final h = size.height - padTop - pad;

    final p = Path();
    for (int i = 0; i < v.length; i++) {
      final x = pad + (i / (v.length - 1)) * w;
      final y = padTop + h - ((v[i] - minV) / range) * h;
      if (i == 0) p.moveTo(x, y);
      else p.lineTo(x, y);
    }

    final paint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.v != v;
}

// ===========================
// Checkerboard (preview)
// ===========================
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 24.0;
    final p1 = Paint()..color = const Color(0xFF2A2A2A);
    final p2 = Paint()..color = const Color(0xFF1E1E1E);

    for (double y = 0; y < size.height; y += s) {
      for (double x = 0; x < size.width; x += s) {
        final isAlt = ((x / s).floor() + (y / s).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), isAlt ? p1 : p2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================
// Painel de estilo
// ===========================
class _StylePanel extends StatelessWidget {
  final StickerStyle style;
  final ValueChanged<StickerStyle> onChanged;

  const _StylePanel({required this.style, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, VoidCallback onTap, {bool selected = false}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: selected ? 26 : 22,
          height: selected ? 26 : 22,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? const Color(0xFFFF6D00) : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      );
    }

    final palette = <Color>[
      Colors.white,
      Colors.black,
      const Color(0xFFFF6D00),
      const Color(0xFF00C853),
      const Color(0xFF1E88E5),
      const Color(0xFFE53935),
      const Color(0xFF9C27B0),
      const Color(0xFFFFD54F),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E0E),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Estilo dos cards",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: style.showBackground,
                  onChanged: (v) => onChanged(style.copyWith(showBackground: v)),
                  title: const Text("Fundo", style: TextStyle(color: Colors.white)),
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: style.showBorder,
                  onChanged: (v) => onChanged(style.copyWith(showBorder: v)),
                  title: const Text("Borda", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),

          if (style.showBackground) ...[
            const SizedBox(height: 6),
            const Text("Opacidade do fundo", style: TextStyle(color: Colors.white70)),
            Slider(
              value: style.backgroundOpacity,
              min: 0.05,
              max: 1.0,
              onChanged: (v) => onChanged(style.copyWith(backgroundOpacity: v)),
            ),
          ],

          const SizedBox(height: 6),
          const Text("Cor do valor", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in palette) dot(c, () => onChanged(style.copyWith(valueColor: c)),
                    selected: style.valueColor == c),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Text("Cor do label", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in palette)
                  dot(c, () => onChanged(style.copyWith(labelColor: c)), selected: style.labelColor == c),
              ],
            ),
          ),

          if (style.showBackground) ...[
            const SizedBox(height: 8),
            const Text("Cor do fundo", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in palette)
                    dot(c, () => onChanged(style.copyWith(backgroundColor: c)), selected: style.backgroundColor == c),
                ],
              ),
            ),
          ],

          if (style.showBorder) ...[
            const SizedBox(height: 8),
            const Text("Cor da borda", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in palette)
                    dot(c, () => onChanged(style.copyWith(borderColor: c)), selected: style.borderColor == c),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: () => onChanged(StickerStyle.defaultStyle()),
                  child: const Text("Reset padrão"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFFF6D00)),
                  ),
                  onPressed: () => onChanged(StickerStyle.cleanNoBox()),
                  child: const Text("Sem caixas"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FullscreenOverlayEditor extends StatefulWidget {
  final int canvasW;
  final int canvasH;

  final GlobalKey boundaryKey;
  final List<OverlayItem> items;
  final Set<OverlayMetricType> enabled;

  final Widget Function(OverlayMetricType type) buildOverlayWidget;
  final VoidCallback onChanged;

  const _FullscreenOverlayEditor({
    required this.canvasW,
    required this.canvasH,
    required this.boundaryKey,
    required this.items,
    required this.enabled,
    required this.buildOverlayWidget,
    required this.onChanged,
  });

  @override
  State<_FullscreenOverlayEditor> createState() => _FullscreenOverlayEditorState();
}

class _FullscreenOverlayEditorState extends State<_FullscreenOverlayEditor> {
  bool _editItemsMode = true;

  @override
  Widget build(BuildContext context) {
    final canvas = AspectRatio(
      aspectRatio: widget.canvasW / widget.canvasH,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomPaint(
              painter: _CheckerPainter(),
              child: const SizedBox.expand(),
            ),

            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: widget.boundaryKey,
                  child: SizedBox(
                    width: widget.canvasW.toDouble(),
                    height: widget.canvasH.toDouble(),
                    child: Stack(
                      children: [
                        for (final it in widget.items)
                          if (widget.enabled.contains(it.type))
                            _OverlayDraggable(
                              item: it,
                              child: widget.buildOverlayWidget(it.type),
                              onChanged: () {
                                // ✅ ESSENCIAL: atualiza o fullscreen durante o drag
                                setState(() {});
                                // ✅ opcional: mantém o editor principal sincronizado
                                widget.onChanged();
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.92),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _editItemsMode
                  ? canvas
                  : InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(200),
                child: canvas,
              ),
            ),

            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _pillButton(
                    icon: Icons.close_rounded,
                    label: "Fechar",
                    onTap: () => Navigator.pop(context),
                  ),
                  _pillToggle(
                    icon: _editItemsMode ? Icons.open_with_rounded : Icons.zoom_in_rounded,
                    label: _editItemsMode ? "Mover itens" : "Pan/Zoom",
                    onTap: () => setState(() => _editItemsMode = !_editItemsMode),
                  ),
                ],
              ),
            ),

            Positioned(
              top: 58,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.centerRight,
                child: _pillHint(
                  _editItemsMode ? "Arraste os itens • Pinça p/ escala/rotação" : "Arraste p/ mover canvas • Pinça p/ zoom",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillToggle({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6D00).withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFFF6D00).withOpacity(0.55)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
