import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_walk_app/widgets/main_scaffold.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  Timer? _pathTimer;
  int _step = 0;
  double xpGain = 0.0;
  bool showXP = false;

  final List<LatLng> playerRoute = [
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
  }

  @override
  void dispose() {
    _pathTimer?.cancel();
    player.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _play(String name) async {
    try {
      await player.play(AssetSource('sounds/$name.mp3'));
    } catch (_) {}
  }

  Future<void> _showTerritory() async {
    // 🔸 Centraliza e destaca o território
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

    // 🔸 Move a câmera suavemente para o centro
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


  Future<void> _fitRoute(List<LatLng> route) async {
    if (_mapController == null || route.isEmpty) return;
    double minLat = route.first.latitude, maxLat = route.first.latitude;
    double minLng = route.first.longitude, maxLng = route.first.longitude;
    for (var p in route) {
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

  // 🔹 Cada etapa controlada manualmente
  Future<void> _runPlayerRoute() async {
    _playerPath.clear();
    await _fitRoute(playerRoute);
    await _play('step');

    for (int i = 0; i < playerRoute.length - 1; i++) {
      if (!mounted) return;
      final current = playerRoute[i];
      final next = playerRoute[i + 1];
      final interp = LatLng(
        (current.latitude + next.latitude) / 2,
        (current.longitude + next.longitude) / 2,
      );
      setState(() => _playerPath.addAll([current, interp]));
      if (i % 10 == 0) _play('step');
      if (i % 6 == 0) {
        _mapController?.animateCamera(CameraUpdate.newLatLng(_playerPath.last));
      }
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  Future<void> _runEnemyRoute() async {
    _enemyPath.clear();
    await _play('alert');

    for (int i = 0; i < enemyRoute.length; i++) {
      if (!mounted) return;

      setState(() => _enemyPath.add(enemyRoute[i]));

      // 🔹 Move a câmera para seguir o inimigo suavemente
      if (i % 3 == 0 && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(enemyRoute[i]),
        );
      }

      // 🔹 Emite um leve som de passo/alerta a cada curva
      if (i % 10 == 0) {
        _play('step');
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }
  }


  void _invadeTerritory() async {
    setState(() {
      _polygons = {
        Polygon(
          polygonId: const PolygonId('player_area'),
          points: playerRoute,
          fillColor: Colors.orangeAccent.withOpacity(0.35),
          strokeColor: Colors.orangeAccent,
          strokeWidth: 3,
        ),
        Polygon(
          polygonId: const PolygonId('enemy_area'),
          points: enemyRoute,
          fillColor: Colors.redAccent.withOpacity(0.45),
          strokeColor: Colors.redAccent,
          strokeWidth: 3,
        ),
      };
      showXP = true;
    });
    await _play('battle');
    _animateXP();
  }

  void _animateXP() {
    double val = 0;
    Timer.periodic(const Duration(milliseconds: 40), (t) {
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

    Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isCompact = width < 300; // Wear OS geralmente tem ~140–200px

    if (isCompact) {
      // 🔹 Layout simplificado para Wear OS
      return Scaffold(
        backgroundColor: Colors.black,
        body: _wearTutorial(),
      );
    }

    // 🔹 Layout completo para mobile
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
            CameraPosition(target: playerRoute.first, zoom: 17),
            onMapCreated: (c) {
              _mapController = c;
              _setMapStyle();
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('player'),
                color: Colors.orangeAccent,
                width: 6,
                points: _playerPath,
              ),
              Polyline(
                polylineId: const PolylineId('enemy'),
                color: Colors.redAccent,
                width: 5,
                points: _enemyPath,
              ),
            },
            polygons: _polygons,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            scrollGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),
          if (showXP) _buildXPBar(),
          _overlay(false),
        ],
      ),
    );
  }


  Widget _overlay(bool isCompact) {
    // Seleciona versão curta ou completa
    final steps = isCompact
        ? [
      {'title': "🌎 Seu Império Começa!", 'text': "Corra e domine ruas!"},
      {'title': "🏃 Crie trajeto", 'text': "Feche voltas e ganhe XP."},
      {'title': "🔥 Território dominado!", 'text': "Suba de nível e evolua!"},
      {'title': "⚔️ Rivais!", 'text': "Defenda sua área!"},
      {'title': "🏅 Vitória!", 'text': "Conecte-se com outros corredores."},
    ]
        : [
      {
        'title': "🌎 Bem-vindo ao Empire of The Run!",
        'text': "Transforme suas corridas em conquistas reais!..."
      },
      {
        'title': "🏃 Criando seu trajeto...",
        'text':
        "Enquanto você corre, o app traça automaticamente seu percurso..."
      },
      {
        'title': "🔥 Território conquistado!",
        'text':
        "Parabéns! Você acaba de dominar sua primeira área. Territórios rendem XP..."
      },
      {
        'title': "⚔️ Invasão inimiga!",
        'text':
        "Outros corredores podem tentar roubar parte do seu território..."
      },
      {
        'title': "🏅 Vitória e Conexões!",
        'text':
        "Explore a rede social, siga corredores e participe de desafios!"
      },
    ];

    final double titleSize = isCompact ? 14 : 22;
    final double textSize = isCompact ? 10 : 15;
    final double spacing = isCompact ? 6 : 20;
    final double padH = isCompact ? 8 : 24;
    final double padV = isCompact ? 20 : 80;

    return Container(
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.only(bottom: padV, left: padH, right: padH),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              steps[_step]['title']!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: spacing / 2),
            Text(
              steps[_step]['text']!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontSize: textSize,
                height: 1.3,
              ),
            ),
            SizedBox(height: spacing),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: () => setState(() {
                      _step--;
                      _enemyPath.clear();
                      _playerPath.clear();
                      _polygons.clear();
                      showXP = false;
                    }),
                    child: Text(
                      "◀ Voltar",
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: textSize,
                      ),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    if (_step == 0) {
                      await _runPlayerRoute();
                      setState(() => _step = 1);
                    } else if (_step == 1) {
                      await _showTerritory();
                      setState(() => _step = 2);
                    } else if (_step == 2) {
                      await _runEnemyRoute();
                      setState(() => _step = 3);
                    } else if (_step == 3) {
                      _invadeTerritory();
                      setState(() => _step = 4);
                    } else if (_step == 4) {
                      _finish();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    minimumSize:
                    Size(isCompact ? 80 : 140, isCompact ? 32 : 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 8 : 32,
                      vertical: isCompact ? 6 : 14,
                    ),
                  ),
                  child: Text(
                    _step == 4 ? "Ir" : "Avançar ▶",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: textSize,
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

  Widget _wearTutorial() {
    final List<Map<String, String>> steps = [
      {
        'title': '🌎 Empire of The Run',
        'text':
        'Transforme suas corridas em conquistas reais! Cada trajeto vira território dominado no mapa.'
      },
      {
        'title': '🏃 Crie seu trajeto',
        'text':
        'Enquanto corre, o app registra seu percurso. Feche voltas e conquiste áreas para ganhar XP.'
      },
      {
        'title': '🔥 Suba de nível',
        'text':
        'Cada território rende XP e desbloqueia molduras exclusivas (Elos) que mostram sua evolução.'
      },
      {
        'title': '⚔️ Defenda seu império',
        'text':
        'Outros corredores podem invadir suas áreas! Corra para reconquistar e proteger seu domínio.'
      },
      {
        'title': '🏅 Explore e Conecte-se',
        'text':
        'Siga outros corredores, entre em clãs e participe de desafios globais para expandir seu império.'
      },
    ];

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
                    onPressed: () =>
                        setState(() => _step = (_step - 1).clamp(0, steps.length - 1)),
                    child: const Text(
                      "◀",
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                    ),
                  ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () async {
                    if (_step < steps.length - 1) {
                      setState(() => _step++);
                    } else {
                      await _finish();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
              gradient:
              const LinearGradient(colors: [Colors.orange, Colors.amber]),
              borderRadius: BorderRadius.circular(12),
            ),
          ).animate().fadeIn(duration: 400.ms),
        ),
      ),
    );
  }

}
