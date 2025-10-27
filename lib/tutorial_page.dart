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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScaffold()),
    );
  }
  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final bool isCompact = MediaQuery.of(context).size.width < 400;

    final stepsPt = [ /* textos em português (seu conteúdo atual) */ ];
    final stepsEn = [ /* textos em inglês (versão internacional) */ ];
    final stepsCompact = [ /* versão curta para Wear OS */ ];

    final steps = locale == 'en'
        ? stepsEn
        : (isCompact ? stepsCompact : stepsPt);
    return Scaffold(
      body: Stack(children: [
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
        _overlay(),
      ]),
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

  // 🔹 Overlay com botões de navegação
  Widget _overlay() {
    final steps = [
      {
        'title': "🌎 Bem-vindo ao Empire of The Run!",
        'text': """
Transforme suas corridas em conquistas reais!  
Cada vez que você corre, o trajeto é registrado no mapa e se transforma em território dominado.  
Avance pelas ruas, amplie seu império e suba no ranking entre milhares de corredores!  
""",
      },
      {
        'title': "🏃 Criando seu trajeto...",
        'text': """
Enquanto você corre, o app traça automaticamente seu percurso no mapa em tempo real.  
Complete voltas fechadas para reivindicar áreas e transformar seu trajeto em território conquistado.  
Quanto mais longo e preciso for seu trajeto, maior será sua conquista e seu ganho de XP!  
""",
      },
      {
        'title': "🔥 Território conquistado!",
        'text': """
Parabéns! Você acaba de dominar sua primeira área.  
Territórios conquistados rendem XP e te ajudam a subir de nível.  
Ao alcançar novos níveis, você desbloqueia **Elos**, molduras exclusivas que exibem seu status no mapa e no perfil.  
Mostre que você é um corredor lendário!  
""",
      },
      {
        'title': "⚔️ Invasão inimiga!",
        'text': """
Mas cuidado... outros corredores também estão lutando por domínio!  
Se um rival correr sobre parte do seu território, ele poderá tomar uma fração — ou até tudo!  
Corra para defender sua área, reconquiste o que é seu e suba ainda mais nos Elos.  
O mapa está vivo, e cada corrida é uma batalha por espaço!  
""",
      },
      {
        'title': "🏅 Vitória e Conexões!",
        'text': """
Você venceu e garantiu seu território!  
Agora, explore a rede social dentro do Empire of The Run:  
• Siga outros corredores e veja suas conquistas.  
• Crie ou entre em clãs para competir juntos.  
• Participe de desafios privados com amigos ou globais com jogadores do mundo todo.  

Suba de nível, evolua seus Elos e mostre ao mundo o tamanho do seu império!  
""",
      },
    ];

    final stepsCompact = [
      {
        'title': "🌎 Seu Império Começa!",
        'text': "Corra, trace seu caminho e transforme ruas em território dominado.",
      },
      {
        'title': "🏃 Crie seu trajeto",
        'text': "Feche voltas e capture áreas para ganhar XP e crescer seu império.",
      },
      {
        'title': "🔥 Território dominado!",
        'text': "Ganhe XP, suba de nível e desbloqueie molduras exclusivas (Elos).",
      },
      {
        'title': "⚔️ Rivais à vista!",
        'text': "Corra para defender o que é seu! Outros podem roubar parte da sua área.",
      },
      {
        'title': "🏅 Vitória!",
        'text': "Defenda, conquiste e conecte-se com outros corredores e clãs.",
      },
    ];

    final stepsEn = [
      {
        'title': "🌎 Welcome to Empire of The Run!",
        'text': """
Turn your runs into real-world conquests!  
Every step you take transforms streets into your territory.  
Expand your empire, earn XP, and climb the global ranking of runners!  
""",
      },
      {
        'title': "🏃 Creating your route...",
        'text': """
As you run, your path is drawn live on the map.  
Complete closed loops to claim new areas as your territory.  
The farther and cleaner your route, the more XP you earn!  
""",
      },
      {
        'title': "🔥 Territory Captured!",
        'text': """
You’ve just conquered your first area!  
Claimed territories reward XP and help you level up.  
Reach new levels to unlock **Ranks**, exclusive profile frames that show your progress and power.  
""",
      },
      {
        'title': "⚔️ Enemy Invasion!",
        'text': """
Be careful — other runners are competing for domination too!  
If a rival runs through your area, they can steal part — or all — of your territory.  
Defend what’s yours and rise through the Ranks!  
""",
      },
      {
        'title': "🏅 Victory and Community!",
        'text': """
You defended your empire!  
Now join the social side of Empire of The Run:  
• Follow other runners and track their progress.  
• Create or join clans to compete together.  
• Join global or private challenges and rise to glory!  

Level up, earn new Ranks, and show the world your running empire!  
""",
      },
    ];



    return Container(
      color: Colors.black.withOpacity(0.10),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 80, left: 24, right: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          steps[_step]['title']!,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 22,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          steps[_step]['text']!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black87, fontSize: 15),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
                child: const Text("◀ Voltar",
                    style: TextStyle(color: Colors.orangeAccent)),
              ),
            const SizedBox(width: 10),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: Text(
                _step == 4 ? "Ir para o app" : "Avançar ▶",
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
