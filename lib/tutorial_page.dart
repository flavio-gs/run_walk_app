import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapTutorialPage extends StatefulWidget {
  const MapTutorialPage({super.key});

  @override
  State<MapTutorialPage> createState() => _MapTutorialPageState();
}

class _MapTutorialPageState extends State<MapTutorialPage> {
  GoogleMapController? _mapController;
  final player = AudioPlayer();

  final List<LatLng> _playerPath = [];
  final List<LatLng> _enemyPath = [];
  Set<Polygon> _polygons = {};

  int _step = 0;
  double xpGain = 0.0;
  bool showXP = false;

  // ===== Micro effects =====
  bool _invadeFlash = false; // vermelho
  bool _playerFlash = false; // laranja (capítulo/alertas leves)

  double _enemyPulse = 0.0;
  Timer? _pulseTimer;

  double _playerPulse = 0.0;
  Timer? _playerPulseTimer;

  // ===== Routes =====
  final List<LatLng> playerRoute = const [
    LatLng(-22.9377202, -43.325633),
    LatLng(-22.9374791, -43.3256108),
    LatLng(-22.9374432, -43.3258882),
    LatLng(-22.9374001, -43.3261985),
    LatLng(-22.9373583, -43.3265102),
    LatLng(-22.9373068, -43.3268838),
    LatLng(-22.9372633, -43.3271977),
    LatLng(-22.9372005, -43.3275004),
    LatLng(-22.9371601, -43.3278197),
    LatLng(-22.937196, -43.3280726),
    LatLng(-22.9372849, -43.3283991),
    LatLng(-22.9373503, -43.3286423),
    LatLng(-22.9373125, -43.3289504),
    LatLng(-22.9372399, -43.3292891),
    LatLng(-22.9372941, -43.3296226),
    LatLng(-22.9373765, -43.329903),
    LatLng(-22.9374384, -43.3301839),
    LatLng(-22.9375066, -43.3305141),
    LatLng(-22.9375505, -43.33078),
    LatLng(-22.9376597, -43.3311495),
    LatLng(-22.937785, -43.3314355),
    LatLng(-22.9378906, -43.331662),
    LatLng(-22.9380217, -43.3319418),
    LatLng(-22.9381647, -43.3322539),
    LatLng(-22.938295, -43.3325382),
    LatLng(-22.9384802, -43.3326765),
    LatLng(-22.938736, -43.3326185),
    LatLng(-22.9390133, -43.3325483),
    LatLng(-22.93929, -43.3324799),
    LatLng(-22.9393428, -43.3322689),
    LatLng(-22.93933, -43.3318081),
    LatLng(-22.9391389, -43.3313807),
    LatLng(-22.9389315, -43.3309549),
    LatLng(-22.9388239, -43.3305753),
    LatLng(-22.9386804, -43.3301551),
    LatLng(-22.93859, -43.3299626),
    LatLng(-22.9385293, -43.3297697),
    LatLng(-22.9387138, -43.3293216),
    LatLng(-22.9388899, -43.3292398),
    LatLng(-22.9393418, -43.3293783),
    LatLng(-22.9396142, -43.3292026),
    LatLng(-22.9392399, -43.3284005),
    LatLng(-22.9390135, -43.327554),
    LatLng(-22.9389596, -43.3270919),
    LatLng(-22.9389392, -43.3266496),
    LatLng(-22.9389592, -43.3261896),
    LatLng(-22.9390491, -43.3257395),
    LatLng(-22.9386788, -43.3252897),
    LatLng(-22.9383099, -43.3251999),
  ];

  late final List<LatLng> enemyRoute;

  @override
  void initState() {
    super.initState();
    enemyRoute = playerRoute.sublist(0, (playerRoute.length / 2).floor());

    // dispara efeitos iniciais depois do 1º frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onEnterStep(_step);
    });
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _playerPulseTimer?.cancel();
    player.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ======================
  // Helpers: steps / narrative
  // ======================

  List<Map<String, String>> _steps({required bool isCompact}) {
    if (isCompact) {
      return const [
        {'title': "CAP.1 — Fundação", 'text': "Você chegou ao mapa. Vamos marcar sua primeira rota."},
        {'title': "Rota registrada", 'text': "Sua corrida vira linha. Pace, distância e calorias contam."},
        {'title': "Selo de domínio", 'text': "Fechou uma volta? A área vira território e gera XP."},
        {'title': "Alerta de rival", 'text': "Se alguém fechar área sobre a sua… pode invadir."},
        {'title': "Batalha!", 'text': "O território muda de cor. Você pode recuperar correndo de novo."},
        {'title': "Modo Território", 'text': "Aqui você disputa áreas e expande seu Império."},
        {'title': "Modo Livre", 'text': "Treine e registre atividade sem disputar mapa."},
        {'title': "Conquistas", 'text': "Desbloqueie conquistas e evolução visual."},
        {'title': "Social + Clãs", 'text': "Interaja, entre em clãs e faça desafios/rankings."},
        {
          'title': "Localização (2º plano)",
          'text': "Usamos sua localização também em segundo plano para registrar percursos com precisão, gerar mapas/estatísticas e manter seu histórico. Esses dados não são compartilhados com terceiros sem seu consentimento."
        },
      ];
    }

    return const [
      {
        'title': "CAPÍTULO 1 — Fundação do Império",
        'text': "Bem-vindo ao Runner: Império da Corrida. Aqui, corrida vira território. Vamos simular seu primeiro domínio no mapa."
      },
      {
        'title': "🏃 A Primeira Corrida",
        'text': "Ao iniciar, o app registra sua rota em tempo real e calcula distância, tempo, pace e calorias. Pausar/retomar mantém tudo certinho."
      },
      {
        'title': "🟧 Fechou uma volta = Território",
        'text': "Quando sua rota fecha uma área, ela vira território dominado no mapa. Isso rende XP e aumenta sua progressão/nível."
      },
      {
        'title': "⚠️ Contato! Rival Detectado",
        'text': "Outros corredores também disputam o mapa. Se alguém fechar uma área sobre a sua região… pode invadir e tomar parte do seu domínio."
      },
      {
        'title': "⚔️ Invasão em andamento",
        'text': "Quando um território é invadido, a área muda de cor e você recebe alerta. A defesa é simples: corra de novo pela área para reconquistar."
      },
      {
        'title': "🗺️ Modo Território",
        'text': "Nesse modo, suas corridas são usadas para conquistar e disputar áreas. Perfeito para quem quer jogar o mapa e expandir o Império."
      },
      {
        'title': "🌙 Modo Livre",
        'text': "Quer apenas treinar? No modo livre você registra a atividade e guarda no histórico — sem disputa de mapa."
      },
      {
        'title': "🏆 Conquistas e Evolução",
        'text': "Complete objetivos para desbloquear conquistas e marcos de evolução. Seu perfil mostra o quanto você evoluiu."
      },
      {
        'title': "📣 Social, Clãs e Desafios",
        'text': "Suas corridas aparecem no feed. Curta, comente, siga pessoas, entre em clãs/grupos e participe de desafios e rankings."
      },
      {
        'title': "📍 Localização em segundo plano",
        'text': "Para registrar suas corridas com precisão, o Runner: Império da Corrida pode coletar sua localização mesmo com o app em segundo plano ou fechado. Isso permite: salvar rotas, gerar mapas e estatísticas, e manter seu histórico de evolução.\n\nAviso de Privacidade: seus dados de localização são usados para melhorar sua experiência e não são compartilhados com terceiros sem seu consentimento."
      },
    ];
  }

  // ======================
  // Tutorial navigation (effects on enter)
  // ======================

  Future<void> _setStep(int newStep) async {
    if (!mounted) return;
    setState(() => _step = newStep);
    await _onEnterStep(newStep);
  }

  Future<void> _goNext({required bool isCompact}) async {
    // Ações “cinemáticas” dos primeiros steps
    if (_step == 0) {
      await _runPlayerRoute();
      await _setStep(1);
      return;
    }

    if (_step == 1) {
      await _showTerritory();
      await _pulsePlayerTerritory();
      await _setStep(2);
      return;
    }

    if (_step == 2) {
      await _runEnemyRoute();
      await _setStep(3);
      return;
    }

    if (_step == 3) {
      await _invadeTerritory();
      await _setStep(4);
      return;
    }

    // restantes: só avança
    final total = _steps(isCompact: isCompact).length;
    if (_step < total - 1) {
      await _setStep(_step + 1);
    } else {
      await _finish();
    }
  }

  Future<void> _goBack({required bool isCompact}) async {
    if (_step <= 0) return;

    setState(() {
      _step--;
      _enemyPath.clear();
      _playerPath.clear();
      _polygons.clear();
      showXP = false;
      xpGain = 0;
    });

    await _onEnterStep(_step);
  }

  Future<void> _onEnterStep(int s) async {
    // micro-efeitos por step (sem tooltips)
    if (s == 0) {
      await _flashOrange();
    }

    if (s == 3) {
      await _flashOrange(quick: true); // alerta leve antes do vermelho
    }
  }

  // ======================
  // Animations / FX
  // ======================

  double _easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  Future<void> _flashOrange({bool quick = false}) async {
    setState(() => _playerFlash = true);
    await Future.delayed(Duration(milliseconds: quick ? 80 : 130));
    if (!mounted) return;
    setState(() => _playerFlash = false);
  }

  Future<void> _enemyTakeoverEffect() async {
    // flash vermelho rápido
    setState(() => _invadeFlash = true);
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _invadeFlash = false);

    // pulso no polígono vermelho (3 batidas)
    _pulseTimer?.cancel();
    int beats = 0;
    bool up = true;
    _enemyPulse = 0.0;

    _pulseTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      setState(() {
        _enemyPulse += up ? 0.08 : -0.08;
        if (_enemyPulse >= 1) up = false;
        if (_enemyPulse <= 0 && !up) {
          beats++;
          up = true;
        }
      });

      if (beats >= 3) {
        t.cancel();
        setState(() => _enemyPulse = 0.0);
      }
    });

    // mini shake de câmera (sutil)
    if (_mapController != null) {
      final center = enemyRoute[enemyRoute.length ~/ 2];
      await _mapController!.animateCamera(CameraUpdate.newLatLng(center));
      await _mapController!.animateCamera(CameraUpdate.scrollBy(8, 0));
      await _mapController!.animateCamera(CameraUpdate.scrollBy(-16, 0));
      await _mapController!.animateCamera(CameraUpdate.scrollBy(8, 0));
    }
  }

  Future<void> _pulsePlayerTerritory() async {
    _playerPulseTimer?.cancel();
    int beats = 0;
    bool up = true;
    _playerPulse = 0.0;

    _playerPulseTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      setState(() {
        _playerPulse += up ? 0.08 : -0.08;
        if (_playerPulse >= 1) up = false;
        if (_playerPulse <= 0 && !up) {
          beats++;
          up = true;
        }

        // reaplica polígono pulsando
        _polygons = {
          Polygon(
            polygonId: const PolygonId('player_area'),
            points: playerRoute,
            fillColor: Colors.orangeAccent.withOpacity(0.25 + (_playerPulse * 0.35)),
            strokeColor: Colors.orangeAccent.withOpacity(0.70 + (_playerPulse * 0.25)),
            strokeWidth: 3 + (_playerPulse * 3).round(),
          ),
        };
      });

      if (beats >= 3) {
        t.cancel();
        setState(() => _playerPulse = 0.0);
      }
    });
  }

  // ======================
  // Audio
  // ======================

  Future<void> _play(String name) async {
    try {
      await player.play(AssetSource('sounds/$name.mp3'));
    } catch (_) {}
  }

  // ======================
  // Map style
  // ======================

  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  // ======================
  // Map camera helpers
  // ======================

  Future<void> _fitRoute(List<LatLng> route) async {
    if (_mapController == null || route.isEmpty) return;
    double minLat = route.first.latitude, maxLat = route.first.latitude;
    double minLng = route.first.longitude, maxLng = route.first.longitude;
    for (final p in route) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        40,
      ),
    );
  }

  // ======================
  // Tutorial actions (simulation)
  // ======================

  Future<void> _runPlayerRoute() async {
    _playerPath.clear();
    _enemyPath.clear();
    setState(() {
      _polygons.clear();
      showXP = false;
      xpGain = 0;
    });

    await _fitRoute(playerRoute);
    await _play('step');

    // ✅ fluidez real
    const framesPerSegment = 1; // aumenta = mais suave
    const frameDelay = Duration(milliseconds: 16); // ~60fps

    for (int i = 0; i < playerRoute.length - 1; i++) {
      if (!mounted) return;

      final a = playerRoute[i];
      final b = playerRoute[i + 1];

      for (int f = 0; f < framesPerSegment; f++) {
        final t = _easeInOutCubic(f / framesPerSegment);
        final p = _lerpLatLng(a, b, t);

        setState(() => _playerPath.add(p));

        if ((_playerPath.length % 18) == 0) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(p));
        }

        await Future.delayed(frameDelay);
      }

      if (i % 10 == 0) {
        _play('step');
      }
    }

    setState(() => _playerPath.add(playerRoute.last));
  }

  Future<void> _runEnemyRoute() async {
    _enemyPath.clear();
    await _play('alert');

    const framesPerSegment = 10;
    const frameDelay = Duration(milliseconds: 18);

    for (int i = 0; i < enemyRoute.length - 1; i++) {
      if (!mounted) return;

      final a = enemyRoute[i];
      final b = enemyRoute[i + 1];

      for (int f = 0; f < framesPerSegment; f++) {
        final t = _easeInOutCubic(f / framesPerSegment);
        final p = _lerpLatLng(a, b, t);

        setState(() => _enemyPath.add(p));

        if ((_enemyPath.length % 16) == 0 && _mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newLatLng(p));
        }

        await Future.delayed(frameDelay);
      }

      if (i % 12 == 0) _play('step');
    }

    setState(() => _enemyPath.add(enemyRoute.last));
  }

  Future<void> _showTerritory() async {
    await _fitRoute(playerRoute);
    await _play('conquer');

    setState(() {
      _polygons = {
        Polygon(
          polygonId: const PolygonId('player_area'),
          points: playerRoute,
          fillColor: Colors.orangeAccent.withOpacity(0.45),
          strokeColor: Colors.orangeAccent,
          strokeWidth: 3,
        ),
      };
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: playerRoute[playerRoute.length ~/ 2],
            zoom: 17.5,
            tilt: 30,
          ),
        ),
      );
    }
  }

  Future<void> _invadeTerritory() async {
    await _play('battle');

    // efeito visual antes
    await _enemyTakeoverEffect();

    setState(() {
      final pulseAlpha = 0.45 + (_enemyPulse * 0.35); // 0.45..0.80
      final strokeW = 4 + (_enemyPulse * 4).round(); // 4..8

      _polygons = {
        Polygon(
          polygonId: const PolygonId('player_area'),
          points: playerRoute,
          fillColor: Colors.orangeAccent.withOpacity(0.28),
          strokeColor: Colors.orangeAccent.withOpacity(0.85),
          strokeWidth: 3,
        ),
        Polygon(
          polygonId: const PolygonId('enemy_area'),
          points: enemyRoute,
          fillColor: Colors.redAccent.withOpacity(pulseAlpha),
          strokeColor: Colors.redAccent.withOpacity(0.95),
          strokeWidth: strokeW,
        ),
      };
      showXP = true;
    });

    _animateXP();
  }

  void _animateXP() {
    double val = 0;
    Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      if (val >= 1) {
        t.cancel();
        _play('victory');
      } else {
        setState(() => xpGain = val);
        val += 0.02;
      }
    });
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenTutorial', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/splash');
  }

  // ======================
  // UI
  // ======================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 300; // Wear

    if (isCompact) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _wearTutorial(),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // mapa
          GoogleMap(
            initialCameraPosition: CameraPosition(target: playerRoute.first, zoom: 17),
            onMapCreated: (c) {
              _mapController = c;
              _setMapStyle();
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('player'),
                color: Colors.orangeAccent,
                width: 7,
                points: _playerPath,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                jointType: JointType.round,
                geodesic: true,
              ),
              Polyline(
                polylineId: const PolylineId('enemy'),
                color: Colors.redAccent,
                width: 6,
                points: _enemyPath,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                jointType: JointType.round,
                geodesic: true,
              ),
            },
            polygons: _polygons,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            scrollGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),

          // leve escurecida (INTVL-ish)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withOpacity(0.10)),
            ),
          ),

          // flash laranja (capítulo/alerta)
          if (_playerFlash)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.orangeAccent.withOpacity(0.10)),
              ),
            ),

          // flash vermelho (invasão)
          if (_invadeFlash)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.redAccent.withOpacity(0.18)),
              ),
            ),

          if (showXP) _buildXPBar(),

          _overlay(isCompact: false),
        ],
      ),
    );
  }

  Widget _overlay({required bool isCompact}) {
    final steps = _steps(isCompact: isCompact);
    final titleSize = isCompact ? 14.0 : 20.0;
    final textSize = isCompact ? 11.0 : 14.0;

    return Positioned(
      left: 14,
      right: 14,
      bottom: isCompact ? 10 : 22,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 14, 16, isCompact ? 12 : 16),
            decoration: BoxDecoration(
              color: const Color(0xFF101015).withOpacity(0.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.orangeAccent.withOpacity(0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // topo: step + dots + pular
                Row(
                  children: [
                    Text(
                      "${_step + 1}/${steps.length}",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: isCompact ? 10 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: List.generate(steps.length, (i) {
                          final active = i == _step;
                          return Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: active ? 6 : 4,
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.orangeAccent
                                    : Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_step < steps.length - 1 && !isCompact)
                      TextButton(
                        onPressed: _finish,
                        child: const Text(
                          "Pular",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // texto
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    steps[_step]['title']!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    steps[_step]['text']!,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: textSize,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ações
                Row(
                  children: [
                    if (_step > 0)
                      InkWell(
                        onTap: () => _goBack(isCompact: isCompact),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: isCompact ? 38 : 44,
                          height: isCompact ? 38 : 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                          child: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 44),

                    const SizedBox(width: 10),

                    Expanded(
                      child: SizedBox(
                        height: isCompact ? 40 : 48,
                        child: ElevatedButton(
                          onPressed: () => _goNext(isCompact: isCompact),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            _step == steps.length - 1 ? "Começar" : "Continuar",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: isCompact ? 12 : 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.15, end: 0),
        ),
      ),
    );
  }

  // ========= Wear (mantém simples) =========
  Widget _wearTutorial() {
    final steps = _steps(isCompact: true);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      steps[_step]['title']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[_step]['text']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: () => _setStep((_step - 1).clamp(0, steps.length - 1)),
                    child: const Text(
                      "◀",
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                    ),
                  ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () async {
                    if (_step < steps.length - 1) {
                      await _setStep(_step + 1);
                    } else {
                      await _finish();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _step == steps.length - 1 ? "Ir ▶" : "Avançar ▶",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========= XP BAR =========
  Widget _buildXPBar() {
    return Positioned(
      top: 60,
      left: 30,
      right: 30,
      child: Container(
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: FractionallySizedBox(
          widthFactor: xpGain,
          alignment: Alignment.centerLeft,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.orange, Colors.amber]),
              borderRadius: BorderRadius.circular(12),
            ),
          ).animate().fadeIn(duration: 400.ms),
        ),
      ),
    );
  }
}
