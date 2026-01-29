import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback + rootBundle
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:run_walk_app/profile_page.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:run_walk_app/service/service/territory_service.dart';
import 'package:run_walk_app/service/level_frame_manager.dart';
import 'package:run_walk_app/service/weather_service.dart';
import 'package:run_walk_app/territory_danger_map_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'UI/territory_toggle.dart';
import 'controller/territory_controller.dart';
import 'enums/territory_mode.dart';
import 'model/run_model.dart';
import 'detalhe_corrida_page.dart';
import 'widgets/main_scaffold.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';


import 'package:cloud_firestore/cloud_firestore.dart' as fs;





// Lista de frases e áudios correspondentes
final List<Map<String, String>> preRunPhrases = [
  {
    "text": "Você tem 15 segundos para se preparar 🏁",
    "audio": "audio/pre_run_1.mp3"
  },
  {
    "text": "Aquecimento rápido! Largada em até 15s ⏱️",
    "audio": "audio/pre_run_2.mp3"
  },
  {
    "text": "Prepare-se! Corrida começa em até 15 segundos 🔥",
    "audio": "audio/pre_run_3.mp3"
  },
  {
    "text": "Hora de alongar e focar — largada em até 15s 💪",
    "audio": "audio/pre_run_4.mp3"
  },
  {
    "text": "Respira fundo… corrida começa em 15 segundos!",
    "audio": "audio/pre_run_5.mp3"
  },
  {
    "text": "Você tem 15s pra se preparar. Vamos nessa! 🧡",
    "audio": "audio/pre_run_6.mp3"
  },
  {
    "text": "Aquecendo motores… largada em 15 segundos 🏁",
    "audio": "audio/pre_run_7.mp3"
  },
];

class SimpleGeoHash {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static final _decodeMap = {
    for (int i = 0; i < _base32.length; i++) _base32[i]: i
  };

  String encode(double lat, double lng, {int precision = 9}) {
    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;

    final sb = StringBuffer();
    bool evenBit = true;
    int bit = 0;
    int ch = 0;

    while (sb.length < precision) {
      if (evenBit) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) {
          ch |= 1 << (4 - bit);
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          ch |= 1 << (4 - bit);
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      evenBit = !evenBit;

      if (bit < 4) {
        bit++;
      } else {
        sb.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return sb.toString();
  }

  /// aproximação: escolhe o tamanho do geohash conforme raio
  int precisionForRadius(double radiusMeters) {
    if (radiusMeters <= 20) return 8;
    if (radiusMeters <= 76) return 7;
    if (radiusMeters <= 610) return 6;
    if (radiusMeters <= 2400) return 5;
    if (radiusMeters <= 20000) return 4;
    if (radiusMeters <= 78000) return 3;
    if (radiusMeters <= 630000) return 2;
    return 1;
  }

  /// retorna 9 hashes (centro + 8 vizinhos)
  List<String> neighbors9(String hash) {
    final n = _neighbor(hash, 'n');
    final s = _neighbor(hash, 's');
    final e = _neighbor(hash, 'e');
    final w = _neighbor(hash, 'w');

    final ne = _neighbor(n, 'e');
    final nw = _neighbor(n, 'w');
    final se = _neighbor(s, 'e');
    final sw = _neighbor(s, 'w');

    return [hash, n, s, e, w, ne, nw, se, sw].toSet().toList();
  }

  /// bounds tipo geofire: [start, end] usando "~" como char final alto
  List<List<String>> queryBounds(LatLng center, double radiusMeters) {
    final p = precisionForRadius(radiusMeters);
    final h = encode(center.latitude, center.longitude, precision: p);
    final hashes = neighbors9(h);

    return hashes.map((x) => [x, '$x~']).toList();
  }

  // --- neighbor internals (tabela padrão geohash) ---
  static const _neighbors = {
    'n': {
      'even': 'p0r21436x8zb9dcf5h7kjnmqesgutwvy',
      'odd':  'bc01fg45238967deuvhjyznpkmstqrwx'
    },
    's': {
      'even': '14365h7k9dcfesgujnmqp0r2twvyx8zb',
      'odd':  '238967debc01fg45kmstqrwxuvhjyznp'
    },
    'e': {
      'even': 'bc01fg45238967deuvhjyznpkmstqrwx',
      'odd':  'p0r21436x8zb9dcf5h7kjnmqesgutwvy'
    },
    'w': {
      'even': '238967debc01fg45kmstqrwxuvhjyznp',
      'odd':  '14365h7k9dcfesgujnmqp0r2twvyx8zb'
    },
  };

  static const _borders = {
    'n': {'even': 'prxz',     'odd': 'bcfguvyz'},
    's': {'even': '028b',     'odd': '0145hjnp'},
    'e': {'even': 'bcfguvyz', 'odd': 'prxz'},
    'w': {'even': '0145hjnp', 'odd': '028b'},
  };

  String _neighbor(String hash, String dir) {
    hash = hash.toLowerCase();
    final last = hash[hash.length - 1];
    final type = (hash.length % 2 == 0) ? 'even' : 'odd';
    final base = hash.substring(0, hash.length - 1);

    final border = _borders[dir]![type]!;
    final neighbor = _neighbors[dir]![type]!;

    final newBase = (base.isNotEmpty && border.contains(last))
        ? _neighbor(base, dir)
        : base;

    final lastIndex = neighbor.indexOf(last);
    return newBase + _base32[lastIndex];
  }
}


class Character3D extends StatelessWidget {
  final double bearing;

  const Character3D({super.key, required this.bearing});

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      src: 'assets/models/runner.glb',
      backgroundColor: Colors.transparent,
      disableZoom: true,
      cameraControls: false,
      autoPlay: true,
      animationName: "Run",
      autoRotate: false,

      // 📸 Ajustes finos:
      // - 180° pra virar o personagem “de frente pra frente do mapa”
      // - 3m de distância pra mostrar o corpo todo
      // - alvo da câmera levemente mais alto (1.7m)
      cameraOrbit: "${(bearing + 180).toStringAsFixed(0)}deg 65deg 3m",
      cameraTarget: "0m 1.7m 0m",
      fieldOfView: "28deg",
      exposure: 1.2,
      disableTap: true,
    );
  }
}

class _TerritoryDispute {
  final String status;
  final String attackerId;
  final String defenderId;
  final double? lastProgress;
  final Timestamp? startedAt;

  const _TerritoryDispute({
    required this.status,
    required this.attackerId,
    required this.defenderId,
    this.lastProgress,
    this.startedAt,
  });

  static _TerritoryDispute? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw as Map);

    return _TerritoryDispute(
      status: (m['status'] ?? '') as String,
      attackerId: (m['attackerId'] ?? '') as String,
      defenderId: (m['defenderId'] ?? '') as String,
      lastProgress: (m['lastProgress'] is num) ? (m['lastProgress'] as num).toDouble() : null,
      startedAt: (m['startedAt'] is Timestamp) ? m['startedAt'] as Timestamp : null,
    );
  }
}

class _Territory {
  final String id;
  final String ownerId;
  final List<LatLng> points;

  // ✅ NOVO
  final _TerritoryDispute? dispute;

  const _Territory({
    required this.id,
    required this.ownerId,
    required this.points,
    this.dispute,
  });
}


final List<_Territory> _territories = [];


class FuturisticChrono extends StatefulWidget {
  final int seconds;
  final double fontSize;
  const FuturisticChrono({
    super.key,
    required this.seconds,
    this.fontSize = 68,
  });

  @override
  State<FuturisticChrono> createState() => _FuturisticChronoState();
}

class _FuturisticChronoState extends State<FuturisticChrono>
    with SingleTickerProviderStateMixin {

  late final TerritoryController _territoryController;

  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();

    _territoryController = TerritoryController(
      currentUserId: FirebaseAuth.instance.currentUser!.uid,
    );

    _checkAchievementsOnLoad();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.2,
      upperBound: 0.9,
    )..repeat(reverse: true);
  }


  Future<void> _checkAchievementsOnLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Checa se o usuário tem corridas registradas
    final query = await FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .get();

    if (query.docs.isNotEmpty) {
      // Garante que a “Primeira Corrida” seja desbloqueada mesmo se o app foi fechado antes
      await AchievementService().checkAchievements(
        runData: {
          'distance': query.docs.last['distance'],
          'pace': query.docs.last['pace'],
        },
      );
    }
  }



  @override
  void dispose() {
    _glowCtrl.dispose();
    _territoryController.dispose();
    super.dispose();
  }

  String _format(int totalSeconds) {
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final time = _format(widget.seconds);

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, _) {
        final glow = _glowCtrl.value;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
              Tween<Offset>(begin: const Offset(0, .15), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: ShaderMask(
            key: ValueKey(time),
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF4A90E2),
                Color(0xFF007AFF),
              ],
            ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
            blendMode: BlendMode.srcIn,
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    blurRadius: 20 + 10 * glow,
                    color: const Color(0xFF4A90E2).withOpacity(0.5 * glow),
                  ),
                  Shadow(
                    blurRadius: 30 + 15 * glow,
                    color: const Color(0xFF007AFF).withOpacity(0.4 * glow),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class RunTrackingPage extends StatefulWidget {
  const RunTrackingPage({super.key});


  @override
  State<RunTrackingPage> createState() => _RunTrackingPageState();
}

class _RunTrackingPageState extends State<RunTrackingPage>
    with SingleTickerProviderStateMixin {

  final TerritoryController _territoryController =
  TerritoryController(
    currentUserId: FirebaseAuth.instance.currentUser!.uid,
  );

  StreamSubscription<QuerySnapshot>? _territoriesSub;


  // ✅ Token para cancelar "carregamentos antigos" (async) quando trocar de modo
  int _overlayEpoch = 0;

  // ✅ opcional: controla se estamos no modo livre (facilita checks)
  bool get _isFreeMode => _territoryController.mode == MapTerritoryMode.livre;

  void _invalidateOverlayJobs() {
    _overlayEpoch++;
  }


  String? _lastEnemyTerritoryId;     // pra não repetir o mesmo alerta
  DateTime? _lastEnemyAlertAt;       // throttling
  bool _enemyAlertOpen = false;      // evita abrir vários dialogs


  double _slideDragValue = 0.0;

  bool _isOnline = true;
  StreamSubscription<Position>? _onlinePositionStream;
  LatLng? _lastSavedPositionOnline;
  bool _isChallengePanelVisible = false;

  bool _mapReady = false;
  bool _followUser = true; // 🔓 controla se o mapa deve seguir automaticamente


  Map<String, dynamic>? _activeChallenge;
  String? _activeChallengeId;

  OverlayEntry? _radialMenuOverlay;
  Timer? _longPressTimer;
  bool _isHoldingMarker = false;
  Offset? _markerScreenPosition;

  String? _activeDisputeTerritoryId; // qual território está em disputa agora

  String _areaCapturedFormatted = "0 m²";

  final Set<Polygon> _territoryPolygons = {}; // 🟩 Territórios salvos

  // 🟩 NOVO: Área conquistada
  final Set<Polygon> _polygons = {};
  double _areaCaptured = 0;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _challengeStream;
  Map<String, dynamic>? _activeChallengeData;

  // ─────────────────────────────
// 📈 MÉTRICAS NOVAS (GPS)
// ─────────────────────────────
  final List<double> _altitudes = [];
  double _elevationGain = 0.0;     // soma somente das subidas (m)
  double _minElevation = 0.0;
  double _maxElevation = 0.0;

  double? _lastAltFiltered;        // para filtro
  double _currentSpeedMps = 0.0;   // velocidade instantânea m/s
  double _currentSpeedKmh = 0.0;   // velocidade instantânea km/h
  double _avgSpeedKmh = 0.0;       // velocidade média km/h

// opcional: amostras para gráficos (tempo, speed, altitude)
  final List<Map<String, dynamic>> _runSamples = [];
// exemplo de sample: {t: secondsFromStart, lat, lng, alt, speedMps, distTotal}

  double _userWeightKg = 70.0; // fallback

  bool _overlayOpen = false;
  BuildContext? _overlayCtx;

  bool _navigatingToDetails = false;


  static const String _kLoadingRouteName = '__loading_overlay__';

  int _lastSampleSecond = -999;

  bool _savingRun = false;

  final _geo = SimpleGeoHash();

  StreamSubscription<Position>? _posSub;

  Timer? _powerupTicker;

  final Map<String, DateTime> _protectionUntilByTerritory = {};
  final Map<String, int> _boostExtraByTerritory = {};
  final Map<String, Marker> _statusMarkersByTerritory = {};

  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeChallengesStream;
  List<String> _activeChallengeIds = [];

// em vez de 1 listener, agora serão vários (um por bound)
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _territoryBoundsSubs = [];

// buffer/merge dos docs vindos de múltiplos listeners
  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _territoryDocsById = {};

// para evitar reload a cada micro-movimento
  LatLng? _lastQueryCenter;

  bool _territoryPaused = false;

// reaplica SEM consultar banco (instantâneo)
  void _reapplyTerritoryCacheToMap() {
    // ✅ polígonos: mantém o mesmo Set final (não reatribui)
    _territoryController.territoryPolygons
      ..clear()
      ..addAll(_polygonsByTerritory.values);

    // ✅ markers: se você guarda tudo em _markers, aqui você re-insere os de owner do cache
    // (se _addTerritoryOwnerMarker já coloca no _markers, então você precisa ter cache de Marker pronto)
    // Se você NÃO tem marker pronto no cache, deixa só polygons por enquanto.
    // Exemplo se tiver Marker pronto:
    for (final m in _ownerMarkersByTerritory.values) {
      _markers.removeWhere((x) => x.markerId == m.markerId);
      _markers.add(m);
    }
  }

  void _clearDisputeMarker() {
    _markers.removeWhere((m) =>
    m.markerId.value.startsWith('dispute_') ||
        m.markerId.value.startsWith('my_dispute_')
    );
    _activeDisputeTerritoryId = null;
  }

  Future<void> _cancelTerritoryBoundsSubs() async {
    for (final s in _territoryBoundsSubs) {
      await s.cancel();
    }
    _territoryBoundsSubs.clear();
    _territoryDocsById.clear();
  }

  static const _kLocDisclosureSeen = 'location_disclosure_seen';
  static const _kLocDisclosureAccepted = 'location_disclosure_accepted';

  Future<void> _handleLocationDisclosureOnce() async {
    final prefs = await SharedPreferences.getInstance();

    final seen = prefs.getBool(_kLocDisclosureSeen) ?? false;
    if (seen) {
      // ✅ Já viu uma vez, não mostra mais.
      final accepted = prefs.getBool(_kLocDisclosureAccepted) ?? false;
      if (accepted) {
        _initLocationFlow(); // segue normal pedindo permissões (se ainda precisar)
      } else {
        // recusou anteriormente -> não pede permissão e segue com modo limitado
        // (você decide o comportamento)
      }
      return;
    }

    // 👇 Primeira vez abrindo a tela: mostra o aviso antes da permissão
    final accepted = await _showLocationConsentDialog();
    await prefs.setBool(_kLocDisclosureSeen, true);
    await prefs.setBool(_kLocDisclosureAccepted, accepted);

    if (!mounted) return;

    if (accepted) {
      _initLocationFlow();
    } else {
      // recusou -> não pede permissão
    }
  }




  Future<BitmapDescriptor> _createVsDisputeIcon({
    required String leftName,
    required String rightName,
    String? leftPhotoUrl,
    String? rightPhotoUrl,
    required Color accent,
  }) async {
    const int w = 420;
    const int h = 140;
    const double avatarR = 44;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // fundo glass/placa
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      const Radius.circular(22),
    );
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.60);
    canvas.drawRRect(bgRect, bgPaint);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = accent.withOpacity(0.9);
    canvas.drawRRect(bgRect, border);

    // função auxiliar pra carregar imagem
    Future<ui.Image?> loadImg(String? url) async {
      if (url == null || url.isEmpty) return null;
      try {
        final data = await NetworkAssetBundle(Uri.parse(url)).load("");
        final bytes = data.buffer.asUint8List();
        return await decodeImageFromList(bytes);
      } catch (_) {
        return null;
      }
    }

    final leftImg = await loadImg(leftPhotoUrl);
    final rightImg = await loadImg(rightPhotoUrl);

    // desenha avatar circular
    void drawAvatar(double cx, double cy, ui.Image? img, String fallbackLetter) {
      final center = Offset(cx, cy);
      final r = avatarR;

      // glow
      final glow = Paint()
        ..color = accent.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10);
      canvas.drawCircle(center, r, glow);

      if (img == null) {
        final p = Paint()..color = Colors.grey.shade900;
        canvas.drawCircle(center, r, p);

        final tp = TextPainter(
          text: TextSpan(
            text: fallbackLetter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      } else {
        final clip = Path()..addOval(Rect.fromCircle(center: center, radius: r));
        canvas.save();
        canvas.clipPath(clip);
        final paint = Paint()
          ..shader = ImageShader(
            img,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity()
                .scaled((r * 2) / img.width, (r * 2) / img.height)
                .storage,
          );
        canvas.drawCircle(center, r, paint);
        canvas.restore();
      }

      // borda branca
      final b = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.9);
      canvas.drawCircle(center, r, b);
    }

    // posições
    final leftC = const Offset(92, 70);
    final rightC = const Offset(328, 70);

    drawAvatar(leftC.dx, leftC.dy, leftImg, leftName.isNotEmpty ? leftName[0].toUpperCase() : '?');
    drawAvatar(rightC.dx, rightC.dy, rightImg, rightName.isNotEmpty ? rightName[0].toUpperCase() : '?');

    // VS no meio
    final vsPainter = TextPainter(
      text: TextSpan(
        text: "VS",
        style: TextStyle(
          color: accent.withOpacity(0.95),
          fontSize: 38,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(blurRadius: 12, offset: Offset(0, 2), color: Colors.black87)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    vsPainter.layout();
    vsPainter.paint(canvas, Offset((w - vsPainter.width) / 2, 40));

    // texto embaixo
    final subPainter = TextPainter(
      text: const TextSpan(
        text: "Disputando território",
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    subPainter.layout(maxWidth: w.toDouble());
    subPainter.paint(canvas, Offset((w - subPainter.width) / 2, 102));

    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadUserWeight() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final w = snap.data()?['weight'];
    if (w is num && w > 0) {
      _userWeightKg = w.toDouble();
    }
  }


  Future<void> _showDisputeVsMarker({
    required _Territory territory,
  }) async {
    if (!mounted) return;
    if (isWearOS) return;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    // centro do território (use sua função)
    final center = _territoryCenter(territory.points);

    // pega dados do atacante (você)
    final myDoc = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
    final myData = myDoc.data() ?? {};
    final myName = (myData['displayName'] as String?) ?? 'Você';
    final myPhoto = (myData['photoURL'] as String?);

    // pega dados do defensor (dono)
    final ownerDoc = await FirebaseFirestore.instance.collection('users').doc(territory.ownerId).get();
    final ownerData = ownerDoc.data() ?? {};
    final ownerName = (ownerData['displayName'] as String?) ?? 'Jogador';
    final ownerPhoto = (ownerData['photoURL'] as String?);

    final accent = _territoryStrokeForOwner(territory.ownerId);

    final icon = await _createVsDisputeIcon(
      leftName: myName,
      rightName: ownerName,
      leftPhotoUrl: myPhoto,
      rightPhotoUrl: ownerPhoto,
      accent: accent,
    );

    setState(() {
      // remove VS antigo se houver
      _markers.removeWhere((m) => m.markerId.value.startsWith('dispute_'));

      _activeDisputeTerritoryId = territory.id;

      _markers.add(
        Marker(
          markerId: MarkerId('my_dispute_${territory.id}'),
          position: center,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 9998,
          onTap: () {
            _showDisputeDetailsSheet(
              context: context,
              territory: territory,
            );
          },
        ),
      );

    });
  }

  void _showDisputeDetailsSheet({
    required BuildContext context,
    required _Territory territory,
  }) {
    final dispute = territory.dispute;
    if (dispute == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),

              const Text(
                "⚔️ Disputa de Território",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),

              _DisputeUserRow(
                leftId: dispute.attackerId,
                rightId: dispute.defenderId,
                progress: dispute.lastProgress,
              ),

              const SizedBox(height: 16),

              LinearProgressIndicator(
                value: (dispute.lastProgress ?? 0).clamp(0, 1),
                backgroundColor: Colors.white12,
                color: Colors.orange,
                minHeight: 10,
              ),

              const SizedBox(height: 12),

              Text(
                "${((dispute.lastProgress ?? 0) * 100).toStringAsFixed(1)}% conquistado",
                style: const TextStyle(color: Colors.white70),
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Fechar"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _DisputeUserRow({
    required String leftId,
    required String rightId,
    required double? progress,
  }) {
    Widget userChip(String uid) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (_, snap) {
          final data = snap.data?.data();
          final name = (data?['displayName'] as String?) ?? 'Jogador';
          final photo = (data?['photoURL'] as String?);

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white12,
                backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                child: (photo == null || photo.isEmpty)
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))
                    : null,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      );
    }

    final pct = ((progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0);

    return Row(
      children: [
        Expanded(child: userChip(leftId)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              const Text("VS", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text("$pct%", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(child: Align(alignment: Alignment.centerRight, child: userChip(rightId))),
      ],
    );
  }

  _Territory? _enemyTerritoryAt(LatLng pos, String myUid) {
    for (final t in _territories) {
      if (t.points.length < 3) continue;
      if (_pointInPolygon(pos, t.points)) {
        if (t.ownerId.isNotEmpty && t.ownerId != myUid) {
          return t; // inimigo
        }
        return null; // é seu ou sem dono
      }
    }
    return null;
  }

  Future<void> _showEnemyTerritoryAlert(_Territory t) async {
    if (!mounted) return;
    if (_enemyAlertOpen) return;

    _enemyAlertOpen = true;

    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text("⚔️ Território inimigo"),
        content: const Text("Você está dentro de um território inimigo. Gostaria de iniciar uma disputa?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Agora não"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Iniciar disputa"),
          ),
        ],
      ),
    );

    _enemyAlertOpen = false;

    if (go == true) {
      await _startGlobalDispute(t);
      debugPrint("⚔️ Disputa iniciada no território: ${t.id} (dono=${t.ownerId})");

      // ✅ mostra o VS no centro e salva o id da disputa
      await _showDisputeVsMarker(territory: t);

      // opcional: feedback rápido
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚔️ Disputa iniciada! Finalize a corrida para tentar dominar.")),
        );
      }
    }

  }

  Future<void> _cancelGlobalDispute(String territoryId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territoryId)
          .update({
        'dispute': FieldValue.delete(),
      });

      debugPrint("❌ Disputa cancelada no território $territoryId");
    } catch (e) {
      debugPrint("Erro ao cancelar disputa: $e");
    }
  }




  Future<bool> _userHasActiveChallenge() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final now = DateTime.now();
      final qs = await FirebaseFirestore.instance
          .collection('challenges')
          .where('participantsIds', arrayContains: user.uid)
          .where('deadline', isGreaterThan: Timestamp.fromDate(now))
          .limit(1)
          .get();

      if (qs.docs.isEmpty) return false;

      // (Opcional) checar status do participante
      final doc = qs.docs.first;
      final partRef = doc.reference.collection('participants').doc(user.uid);
      final partSnap = await partRef.get();
      if (!partSnap.exists) return true;

      final status = (partSnap.data()?['status'] ?? 'active') as String;
      return status == 'active';
    } catch (e) {
      debugPrint('Erro ao verificar desafio ativo: $e');
      return false;
    }
  }

  Future<void> _startPassiveLocationTracking() async {
    await _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      _updateMarker();

      if (!isWearOS && _followUser) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(_currentPosition),
        );
      }
    });
  }

  void _clearMapOverlaysForFreeMode() {
    _polylines.clear();
    _polygons.clear();
    _markers.clear();
    _markerGestures.clear();
  }

  Future<void> _restoreGlobalOverlays() async {
    if (isWearOS) return;

    // 🔥 limpa overlays globais antes de redesenhar
    _polylines.clear();
    _markers.removeWhere((m) => m.markerId.value != 'currentLocation'); // opcional
    _polygons.clear(); // polígono local "territorio"
    _areaCaptured = 0;
    _areaCapturedFormatted = "0 m²";

    // ⚠️ e limpa os territórios (serão recarregados)
    _territories.clear();
    _territoryPolygons.clear();

    if (mounted) setState(() {});

    //await _loadSavedRuns();
    await _updateMarker();
  }




  Future<void> _setOfflineOnExit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'isOnline': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint("📴 Usuário marcado como offline ao encerrar o app");
    } catch (e) {
      debugPrint("Erro ao marcar offline ao sair: $e");
    }
  }



  Future<void> _listenToActiveChallenge() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = Timestamp.now();

      // Stream direto da coleção "challenges"
      final stream = FirebaseFirestore.instance
          .collection('challenges')
          .where('participants', arrayContains: user.uid)
      // se tiver campo status
          .where('status', isNotEqualTo: 'closed')
          .snapshots();

      setState(() {
        _activeChallengesStream = stream;
      });

      // opcional: manter também uma lista de IDs em memória
      stream.listen((snap) {
        final ids = <String>[];

        for (final doc in snap.docs) {
          final data = doc.data();

          // filtra período (se tiver start/end)
          final Timestamp? start = data['startDate'];
          final Timestamp? end = data['endDate'];

          if (start != null && start.compareTo(now) > 0) continue;
          if (end != null && end.compareTo(now) < 0) continue;

          // se você tiver "quitters" também na coleção challenges, filtra aqui:
          final quitters = (data['quitters'] as List?) ?? const [];
          if (quitters.contains(user.uid)) continue;

          ids.add(doc.id);
        }

        if (!mounted) return;
        setState(() {
          _activeChallengeIds = ids;
        });
      });
    } catch (e) {
      debugPrint("❌ Erro ao escutar desafios ativos: $e");
    }
  }



  Future<void> _recenterMap() async {
    if (_googleMapController == null) return;

    // Se estiver em execução, centraliza na posição atual em movimento;
    // senão, centraliza na última posição conhecida.
    final target = _currentPosition;

    await _googleMapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 17),
      ),
    );

    // Pequeno feedback tátil
    HapticFeedback.lightImpact();
  }

  // ===== Wear OS detection =====
  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300; // heurística prática p/ relógios
  }

  bool loading = false;

  GoogleMapController? _googleMapController;

  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;
  bool _runEnded = false;
  bool _isPaused = false;
  DateTime? _startTime;
  final Stopwatch _stopwatch = Stopwatch();

  final List<LatLng> _positions = [];
  double _totalDistance = 0;
  double _caloriesBurned = 0;
  int weeklyRunsCount = 0;
  int streakDays = 0;
  double _averagePace = 0; // min/km
  int _elapsedSeconds = 0;

  // 🎮 Controle de XP em tempo real
  int _sessionXP = 0;            // XP acumulado durante esta corrida
  int _nextXPThreshold = 100;    // Meta para vibração (ex: a cada 100 XP)
  double _distanceSinceLastXP = 0; // distância acumulada até o próximo ponto

  StreamSubscription<Position>? _positionStream;
  LatLng _currentPosition =
  const LatLng(-23.5505, -46.6333); // fallback (São Paulo)
  bool _loadingLocation = true;
  LocationPermission? _locationPermission;

  late AnimationController _animationController;
  LatLng? _previousPosition;
  LatLng? _animatedPosition;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};


  int _selectedIndex = 2;
  String? _mapStyle;

  // ===== Áudio (som digital suave) — apenas Wear OS =====
  final AudioPlayer _audio = AudioPlayer();
  Future<void> _playStart() async {
    if (!isWearOS) return;
    try {
      await HapticFeedback.lightImpact();
      await _audio.play(AssetSource('sounds/start.wav'));
    } catch (e) {
      debugPrint('Erro som start: $e');
    }
  }

  Future<void> _startGlobalDispute(_Territory t) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    if (t.ownerId.isEmpty || t.ownerId == me.uid) {
      debugPrint("⚠️ Território sem dono ou seu — disputa não inicia.");
      return;
    }

    final docRef = FirebaseFirestore.instance.collection('territorios').doc(t.id);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>;
        final currentOwner = (data['userId'] ?? '') as String;

        // ✅ se mudou o dono, cancela
        if (currentOwner != t.ownerId) {
          throw Exception("Dono do território mudou. Atualize o mapa.");
        }

        // ✅ já existe disputa ativa?
        final dispute = data['dispute'] as Map<String, dynamic>?;
        if (dispute != null && dispute['status'] == 'active') {
          final attacker = dispute['attackerId'];
          throw Exception("Já existe disputa ativa (atacante: $attacker).");
        }

        tx.update(docRef, {
          'dispute': {
            'status': 'active',
            'attackerId': me.uid,
            'defenderId': t.ownerId,
            'startedAt': FieldValue.serverTimestamp(),
          }
        });
      });

      debugPrint("⚔️ Disputa GLOBAL iniciada em ${t.id}");

    } catch (e) {
      debugPrint("❌ Falha ao iniciar disputa: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Não foi possível iniciar disputa: $e")),
        );
      }
    }
  }


  Future<void> _playStop() async {
    if (!isWearOS) return;
    try {
      await HapticFeedback.lightImpact();
      await _audio.play(AssetSource('sounds/stop.wav'));
    } catch (e) {
      debugPrint('Erro som stop: $e');
    }
  }

  Future<bool> _showLocationConsentDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 🔒 não deixa fechar tocando fora
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Permissão de Localização',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const SingleChildScrollView(
            child: Text(
              'O Runner: Império da Corrida coleta sua localização '
                  'mesmo quando o aplicativo está fechado ou em segundo plano.\n\n'
                  'Isso é necessário para:\n\n'
                  '• Registrar seus percursos de corrida com precisão.\n'
                  '• Gerar mapas e estatísticas detalhadas das suas atividades.\n'
                  '• Manter o histórico das suas corridas para que você acompanhe sua evolução.\n\n'
                  'Aviso de Privacidade:\n'
                  'Seus dados de localização são usados apenas para melhorar sua experiência '
                  'no app e não são compartilhados com terceiros sem seu consentimento.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // ❌ recusou
              },
              child: const Text('Recusar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // ✅ aceitou
              },
              child: const Text('Aceitar e Continuar'),
            ),
          ],
        );
      },
    ) ??
        false;
  }


  @override
  @override
  void initState() {
    super.initState();

    _territoryController.setMode(
      MapTerritoryMode.livre,
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLocationDisclosureOnce();
    });



    _powerupTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _refreshPowerupBadges();
    });

    rootBundle.loadString('assets/map_style.json').then((style) {
      _mapStyle = style;
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() {
      if (_previousPosition != null && _animatedPosition != null) {
        setState(() {
          final t = _animationController.value;
          _currentPosition = LatLng(
            _previousPosition!.latitude +
                (_animatedPosition!.latitude - _previousPosition!.latitude) * t,
            _previousPosition!.longitude +
                (_animatedPosition!.longitude - _previousPosition!.longitude) * t,
          );
          _updateMarker();
        });
      }
    });

    _listenToActiveChallenge();
    _setOnlineInitially();
  }


  final List<Color> _colorPalette = const [
    Colors.orangeAccent,
    Colors.cyanAccent,
    Colors.purpleAccent,
    Colors.amberAccent,
    Colors.pinkAccent,
    Colors.lightGreenAccent,
    Colors.blueAccent,
  ];

  Color _baseColorForUser(String userId) {
    final me = FirebaseAuth.instance.currentUser?.uid;

    // 💚 você sempre verde
    if (me != null && userId == me) return const Color(0xFF00C853);

    // 🎨 determinístico (sempre a mesma cor para o mesmo userId)
    final idx = (userId.hashCode & 0x7fffffff) % _colorPalette.length;
    return _colorPalette[idx];
  }

  Color _territoryFillForOwner(String ownerId) =>
      _baseColorForUser(ownerId).withOpacity(0.22);

  Color _territoryStrokeForOwner(String ownerId) =>
      _baseColorForUser(ownerId).withOpacity(0.85);



  Future<void> _initLocationFlow() async {
    await _checkLocationPermissionAndSetInitialLocation();
    await _startPassiveLocationTracking(); // atualiza posição mesmo sem iniciar corrida
  }

  Future<void> _checkLocationPermissionAndSetInitialLocation() async {
    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
    }
    if (_locationPermission == LocationPermission.deniedForever) {
      setState(() {
        _loadingLocation = false;
      });
      return;
    }
    await _setInitialLocation();
  }

  Future<void> _updateMarker() async {
    if (isWearOS) return; // sem mapa no Wear
    if (!mounted) return;

    final customIcon = await _createUserCircleIcon(
      size: 60,
      fillColor: const Color(0xFFFF7600),
    );

    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'currentLocation');
      _markers.add(
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: _currentPosition,
          icon: customIcon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 10000,
        ),
      );
    });

    // ✅ não alerta em modo livre
    if (_territoryController.mode == MapTerritoryMode.livre) return;


    // ❌ não alerta se já estiver correndo
    if (_isRunning) return;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    // ✅ precisa ter territórios carregados
    if (_territories.isEmpty) return;

    final enemy = _enemyTerritoryAt(_currentPosition, me.uid);
    if (enemy == null) {
      _lastEnemyTerritoryId = null; // saiu do inimigo → reseta
      return;
    }

    // ✅ se já tem disputa ativa, não mostra mensagem de iniciar disputa
    final alreadyDisputed = await _isTerritoryAlreadyInDispute(enemy.id);
    if (alreadyDisputed) {
      return;
    }

    // ✅ evita repetir o mesmo alerta sem sair do território
    if (_lastEnemyTerritoryId == enemy.id) return;

    // ✅ throttling (ex: 12s) pra não ficar irritante se GPS oscilar
    final now = DateTime.now();
    if (_lastEnemyAlertAt != null &&
        now.difference(_lastEnemyAlertAt!).inSeconds < 12) {
      return;
    }

    _lastEnemyTerritoryId = enemy.id;
    _lastEnemyAlertAt = now;

    await _showEnemyTerritoryAlert(enemy);

    if (_activeDisputeTerritoryId != null) {
      final active = _territories.where((x) => x.id == _activeDisputeTerritoryId).toList();
      if (active.isEmpty || !_pointInPolygon(_currentPosition, active.first.points)) {
        _clearDisputeMarker();
        if (mounted) setState(() {});
      }
    }

  }

  Future<bool> _isTerritoryAlreadyInDispute(String territoryId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territoryId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data() ?? {};
      final dispute = data['dispute'];

      if (dispute is Map) {
        final status = dispute['status'];
        return status == 'active';
      }

      return false;
    } catch (e) {
      debugPrint("Erro ao checar disputa do território: $e");
      return false;
    }
  }



  Future<void> _setInitialLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _loadingLocation = false;
      });

      await _updateMarker();

      if (!isWearOS && _followUser && _mapReady) {
        await _googleMapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentPosition, zoom: 17),
          ),
        );
        Future.delayed(const Duration(milliseconds: 300), () {
        });
      }

    } catch (e) {
      setState(() => _loadingLocation = false);
    }
  }

  void _syncDisputeMarkers(Set<String> activeTerritoryIds) {
    _markers.removeWhere((m) {
      final id = m.markerId.value;
      if (!id.startsWith('dispute_')) return false;
      final territoryId = id.replaceFirst('dispute_', '');
      return !activeTerritoryIds.contains(territoryId);
    });
  }


  Future<void> _upsertGlobalDisputeMarker({
    required _Territory territory,
    required String attackerId,
    required String defenderId,
  }) async {
    if (!mounted) return;
    if (isWearOS) return;

    final center = _territoryCenter(territory.points);
    final accent = _territoryStrokeForOwner(territory.ownerId);

    // carrega atacante
    final atkDoc = await FirebaseFirestore.instance.collection('users').doc(attackerId).get();
    final atk = atkDoc.data() ?? {};
    final atkName = (atk['displayName'] as String?) ?? 'Atacante';
    final atkPhoto = (atk['photoURL'] as String?);

    // carrega defensor
    final defDoc = await FirebaseFirestore.instance.collection('users').doc(defenderId).get();
    final def = defDoc.data() ?? {};
    final defName = (def['displayName'] as String?) ?? 'Defensor';
    final defPhoto = (def['photoURL'] as String?);

    final icon = await _createVsDisputeIcon(
      leftName: atkName,
      rightName: defName,
      leftPhotoUrl: atkPhoto,
      rightPhotoUrl: defPhoto,
      accent: accent,
    );

    if (!mounted) return;

    setState(() {
      // remove marker antigo daquele território e coloca o novo
      _markers.removeWhere((m) => m.markerId.value == 'dispute_${territory.id}');
      _markers.add(
        Marker(
          markerId: MarkerId('dispute_${territory.id}'),
          position: center,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 9998,
          onTap: () {
            if (!mounted) return;
            _showGlobalDisputeSheet(
              territoryId: territory.id,
              attackerId: attackerId,
              defenderId: defenderId,
            );
          },
        ),
      );
    });
  }

  void _showGlobalDisputeSheet({
    required String territoryId,
    required String attackerId,
    required String defenderId,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('territorios')
              .doc(territoryId)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final dispute = data?['dispute'];

            double progress = 0.0;
            String status = 'unknown';

            // 🔹 ids reais (se o doc mudou, a sheet acompanha)
            String liveAttackerId = attackerId;
            String liveDefenderId = defenderId;

            if (dispute is Map) {
              status = (dispute['status'] ?? 'unknown').toString();

              final lp = dispute['lastProgress'];
              if (lp is num) progress = lp.toDouble().clamp(0.0, 1.0);

              final atk = dispute['attackerId'];
              final def = dispute['defenderId'];
              if (atk is String && atk.isNotEmpty) liveAttackerId = atk;
              if (def is String && def.isNotEmpty) liveDefenderId = def;
            }

            final me = FirebaseAuth.instance.currentUser;
            final myUid = me?.uid ?? "";

            final bool isActive = status == 'active';
            final bool isMine = (myUid.isNotEmpty && liveAttackerId == myUid);

            Future<void> confirmAndCancel() async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF0E0E12),
                  title: const Text(
                    "Cancelar disputa?",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  content: const Text(
                    "Se você cancelar, a disputa some do mapa e ninguém mais pode disputar até iniciar de novo.",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Voltar", style: TextStyle(color: Colors.white70)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Cancelar disputa"),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;

              await _cancelGlobalDispute(territoryId);

              if (!mounted) return;

              // ✅ se essa disputa era “a sua” ativa, limpa o estado local
              if (_activeDisputeTerritoryId == territoryId) {
                setState(() {
                  _activeDisputeTerritoryId = null;

                  // remove marker global desse território
                  _markers.removeWhere((m) => m.markerId.value == 'dispute_$territoryId');

                  // remove marker “my_dispute_...” se você estiver usando também
                  _markers.removeWhere((m) => m.markerId.value == 'my_dispute_$territoryId');
                });
              } else {
                // ainda remove markers por garantia
                setState(() {
                  _markers.removeWhere((m) => m.markerId.value == 'dispute_$territoryId');
                  _markers.removeWhere((m) => m.markerId.value == 'my_dispute_$territoryId');
                });
              }

              // fecha a sheet
              if (Navigator.canPop(context)) Navigator.pop(context);

              // snack
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text("❌ Disputa cancelada")),
                );
              }
            }

            return Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),

                  const Text(
                    "⚔️ Disputa de Território",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 8),

                  _DisputeUserRow(
                    leftId: liveAttackerId,
                    rightId: liveDefenderId,
                    progress: progress,
                  ),

                  const SizedBox(height: 16),

                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    color: Colors.orange,
                    minHeight: 10,
                  ),
                  const SizedBox(height: 10),

                  Text(
                    "${(progress * 100).toStringAsFixed(1)}% conquistado • status: $status",
                    style: const TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // ✅ botão cancelar (só se for minha disputa e ainda estiver ativa)
                      if (isMine && isActive) ...[
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: confirmAndCancel,
                            child: const Text("Cancelar disputa"),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Fechar"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> upsertDisputeMarker({
    required String territoryId,
    required LatLng pos,
    required double progress,
    required bool isMine,
  }) async {
    final marker = await buildDisputeMarker(
      territoryId: territoryId,
      position: pos,
      progress: progress,
      isMine: isMine,
      onTap: () => _showGlobalDisputeSheet(
        territoryId: territoryId,
        attackerId: isMine ? FirebaseAuth.instance.currentUser!.uid : '',
        defenderId: '',
      ),
    );

    if (!mounted) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'dispute_$territoryId');
      _markers.add(marker);
    });
  }


  Future<Marker> buildDisputeMarker({
    required String territoryId,
    required LatLng position,
    required double progress,
    required bool isMine,
    required VoidCallback onTap,
  }) async {
    final icon = await buildDisputeMarkerIcon(
      size: 150,         // 👈 aumenta
      progress: progress,
      isMine: isMine,
    );

    return Marker(
      markerId: MarkerId('dispute_$territoryId'),
      position: position,
      icon: icon,
      anchor: const Offset(0.5, 0.5), // 👈 centro (testa 0.5,0.6 se quiser “peso” pra baixo)
      zIndex: 999,                    // 👈 fica acima dos outros
      consumeTapEvents: true,
      onTap: onTap,
    );
  }


  Future<BitmapDescriptor> buildDisputeMarkerIcon({
    double size = 140,          // 👈 aumenta aqui (120–180 fica ótimo)
    double progress = 0.0,      // 0..1
    bool isMine = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final center = Offset(size / 2, size / 2);
    final radius = size * 0.34;

    // --- Shadow / glow ---
    final glowPaint = Paint()
      ..color = (isMine ? Colors.orangeAccent : Colors.deepOrangeAccent).withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, radius * 1.45, glowPaint);

    // --- Outer ring ---
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.06;
    canvas.drawCircle(center, radius * 1.05, ringPaint);

    // --- Progress arc (opcional, mas dá vida) ---
    final arcPaint = Paint()
      ..color = (isMine ? Colors.orange : Colors.deepOrange)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size * 0.09;

    final rect = Rect.fromCircle(center: center, radius: radius * 1.05);
    const startAngle = -1.55; // quase no topo
    final sweep = (progress.clamp(0.0, 1.0)) * 6.283185307179586; // 2*pi
    canvas.drawArc(rect, startAngle, sweep, false, arcPaint);

    // --- Main badge (fundo) ---
    final badgePaint = Paint()
      ..color = const Color(0xFF0E0E12);
    canvas.drawCircle(center, radius, badgePaint);

    // --- Border ---
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.05;
    canvas.drawCircle(center, radius, borderPaint);

    // --- Emoji / Icon text (⚔️) ---
    final tp = TextPainter(
      text: TextSpan(
        text: '⚔️',
        style: TextStyle(
          fontSize: size * 0.34,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    // --- Percent tiny label (opcional) ---
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    final tp2 = TextPainter(
      text: TextSpan(
        text: '$percent%',
        style: TextStyle(
          fontSize: size * 0.16,
          fontWeight: FontWeight.w900,
          color: Colors.white.withOpacity(0.92),
          shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp2.paint(
      canvas,
      Offset(center.dx - tp2.width / 2, center.dy + radius * 0.35),
    );

    // Export image
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  // ==============================
// TERRITÓRIOS - LOAD / LISTEN / MERGE (COPIAR E COLAR)
// ==============================

// ✅ caches incrementais (não precisa recarregar tudo toda hora)
  final Map<String, Marker> _ownerMarkersByTerritory = {};
  final Map<String, Polygon> _polygonsByTerritory = {};
  final Map<String, String> _territorySig = {}; // id -> assinatura (pra saber se mudou visualmente)

// ✅ loading banner
  bool _loadingTerritoryMarkers = false;
  int _markersDone = 0;
  int _markersTotal = 0;

// ✅ token pra descartar merges antigos (quando troca modo, muda centro, etc)
  int _mergeToken = 0;


// ==============================
// LOAD PRINCIPAL
// ==============================
  Future<void> _loadTerritories() async {
    // ✅ cancela listeners antigos
    await _territoriesSub?.cancel();
    _territoriesSub = null;

    await _posSub?.cancel();
    _posSub = null;

    await _cancelTerritoryBoundsSubs();

    // ✅ modo livre: limpa e sai
    if (_territoryController.mode == MapTerritoryMode.livre) {
      _territoryDocsById.clear();
      _ownerMarkersByTerritory.clear();
      _polygonsByTerritory.clear();
      _territorySig.clear();

      _territories.clear();
      _territoryPolygons.clear();
      _polygons.clear();
      _areaCaptured = 0;
      _areaCapturedFormatted = "0 m²";

      // ✅ garante que loading não fica travado
      _loadingTerritoryMarkers = false;
      _markersDone = 0;
      _markersTotal = 0;

      if (mounted) setState(() {});
      return;
    }

    // ✅ força refazer query ao voltar do modo livre
    _lastQueryCenter = null;

    // ✅ pega posição atual
    final current = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    const double radiusMeters = 3000;

    // ✅ mostra loading imediato ao entrar no modo territórios
    _startTerritoryLoadingSoft();

    await _listenTerritoriesInRadius(
      center: LatLng(current.latitude, current.longitude),
      radiusMeters: radiusMeters,
    );

    // ✅ acompanha movimento (só dispara quando andar X metros)
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 250, // 🔥 recomendo >= 200
      ),
    ).listen((pos) async {
      if (!mounted) return;

      if (_territoryController.mode == MapTerritoryMode.livre) return;

      await _listenTerritoriesInRadius(
        center: LatLng(pos.latitude, pos.longitude),
        radiusMeters: radiusMeters,
      );
    });
  }

// banner "soft" (evita travar sem feedback)
  void _startTerritoryLoadingSoft() {
    if (!mounted) return;
    setState(() {
      _loadingTerritoryMarkers = true;
      _markersDone = 0;
      _markersTotal = 0;
    });

    // fallback: se por algum motivo não vier snapshot, não fica travado
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_territoryController.mode == MapTerritoryMode.livre) return;
      if (_loadingTerritoryMarkers && _markersTotal == 0) {
        setState(() {
          _loadingTerritoryMarkers = false;
        });
      }
    });
  }

// ==============================
// LISTEN POR RAIO (GEOHASH BOUNDS)
// ==============================
  Future<void> _listenTerritoriesInRadius({
    required LatLng center,
    required double radiusMeters,
  }) async {
    // ✅ evita recriar listeners se o centro mudou pouco
    if (_isRunning) {
      // ❄️ congela territórios durante corrida
      return;
    }

    final threshold = 300.0; // metros, fora da corrida

    if (_lastQueryCenter != null) {
      final d = _distMeters(_lastQueryCenter!, center);
      if (d < threshold) return;
    }

    _lastQueryCenter = center;

    await _cancelTerritoryBoundsSubs();

    final bounds = _geo.queryBounds(center, radiusMeters);

    // ✅ token novo: merges antigos serão descartados
    final int myToken = ++_mergeToken;

    for (final b in bounds) {
      final start = b[0];
      final end = b[1];

      final sub = FirebaseFirestore.instance
          .collection('territorios')
          .orderBy('geohash')
          .startAt([start])
          .endAt([end])
          .snapshots()
          .listen((snap) async {
        if (_territoryPaused) return;
        if (_territoryController.mode == MapTerritoryMode.livre) return;
        if (!mounted) return;
        if (myToken != _mergeToken) return; // ✅ listener velho

        bool changed = false;

        // ✅ update incremental (só se mudou algo)
        for (final ch in snap.docChanges) {
          final id = ch.doc.id;

          if (ch.type == DocumentChangeType.removed) {
            if (_territoryDocsById.remove(id) != null) {
              _territorySig.remove(id);
              _polygonsByTerritory.remove(id);
              _ownerMarkersByTerritory.remove(id);
              changed = true;
            }
          } else {
            _territoryDocsById[id] = ch.doc;
            changed = true;
          }
        }

        if (!changed) return;

        await _applyTerritoryDocsMerged(
          center: center,
          radiusMeters: radiusMeters,
          token: myToken,
        );
      });

      _territoryBoundsSubs.add(sub);
    }
  }



// ==============================
// MERGE (SÓ ATUALIZA O QUE MUDOU)
// ==============================

  DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  bool _isPowerupActive(Map<String, dynamic> powerups, String key) {
    final m = powerups[key];
    if (m is! Map) return false;

    final active = (m['active'] == true);
    final until = _tsToDate(m['until']);
    if (!active || until == null) return false;

    return until.isAfter(DateTime.now());
  }

  int _boostExtraDifficulty(Map<String, dynamic> powerups) {
    final m = powerups['difficultyBoost'];
    if (m is! Map) return 0;

    final until = _tsToDate(m['until']);
    if (m['active'] != true || until == null || !until.isAfter(DateTime.now())) return 0;

    final extra = m['extraDifficulty'];
    return (extra is num) ? extra.toInt() : 0;
  }

  LatLng _simpleCenter(List<LatLng> pts) {
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return 'Expirado';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  void _refreshPowerupBadges() {
    bool changed = false;

    for (final tid in _statusMarkersByTerritory.keys.toList()) {
      final marker = _statusMarkersByTerritory[tid];
      if (marker == null) continue;

      final until = _protectionUntilByTerritory[tid];

      // 🛡️ Proteção com timer
      if (until != null) {
        final remaining = until.difference(DateTime.now());

        if (remaining.isNegative) {
          // expirou -> remove caches (o stream depois vai redesenhar cores)
          _statusMarkersByTerritory.remove(tid);
          _protectionUntilByTerritory.remove(tid);
          changed = true;
          continue;
        }

        final txt = _formatRemaining(remaining);

        _statusMarkersByTerritory[tid] = marker.copyWith(
          infoWindowParam: InfoWindow(
            title: '🛡️ Protegido • $txt',
            snippet: 'Imune a tomadas até expirar',
          ),
        );
        changed = true;
        continue;
      }

      // 🔥 Boost sem timer (ou você pode colocar timer também se quiser)
      final extra = _boostExtraByTerritory[tid];
      if (extra != null) {
        _statusMarkersByTerritory[tid] = marker.copyWith(
          infoWindowParam: InfoWindow(
            title: '🔥 Dificuldade +$extra',
            snippet: 'Exige mais progresso para dominar',
          ),
        );
        changed = true;
      }
    }

    if (changed && mounted) setState(() {});
  }



  Future<void> _applyTerritoryDocsMerged({
    required LatLng center,
    required double radiusMeters,
    required int token,
  }) async {


    if (token != _mergeToken) return;
    if (_territoryController.mode == MapTerritoryMode.livre) return;

    try {
      if (mounted) {
        setState(() {
          _loadingTerritoryMarkers = true;
          _markersDone = 0;
          _markersTotal = 0;
        });
      }

      final docs = _territoryDocsById.values.toList();
      final filtered = <DocumentSnapshot<Map<String, dynamic>>>[];

      // ✅ filtro por distância real
      for (final d in docs) {
        final data = d.data();
        if (data == null) continue;

        final clat = (data['centerLat'] as num?)?.toDouble();
        final clng = (data['centerLng'] as num?)?.toDouble();
        if (clat == null || clng == null) continue;

        final dist = _distMeters(center, LatLng(clat, clng));
        if (dist <= radiusMeters) filtered.add(d);
      }

      // ✅ remove territórios que saíram do raio
      final newIds = filtered.map((d) => d.id).toSet();
      final oldIds = _polygonsByTerritory.keys.toSet();
      final removedIds = oldIds.difference(newIds);

      for (final id in removedIds) {
        _polygonsByTerritory.remove(id);
        _ownerMarkersByTerritory.remove(id);
        _statusMarkersByTerritory.remove(id); // ✅ novo
        _territorySig.remove(id);
        _protectionUntilByTerritory.remove(id);
        _boostExtraByTerritory.remove(id);
      }


      // ✅ atualiza lista base de territórios
      _territories
        ..clear()
        ..addAll(filtered.map((d) {
          final data = d.data()!;
          final pts = (data['points'] as List? ?? [])
              .map((p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ))
              .toList();

          return _Territory(
            id: d.id,
            ownerId: (data['userId'] ?? '') as String,
            points: pts,
            dispute: _TerritoryDispute.fromMap(data['dispute']),
          );
        }));

      final owners = _territories.where((t) => t.ownerId.isNotEmpty).toList();
      _markersTotal = owners.length;

      // ✅ atualiza polígonos apenas se mudou assinatura
      for (final t in _territories) {
        final doc = _territoryDocsById[t.id];
        if (doc == null) continue;

        final data = doc.data();
        if (data == null) continue;

        final sig = _makeTerritorySig(data);
        if (_territorySig[t.id] == sig) continue;

        _territorySig[t.id] = sig;

        // --- POWERUPS VISUAIS ---
        final powerupsRaw = data['powerups'];
        final powerups = (powerupsRaw is Map)
            ? Map<String, dynamic>.from(powerupsRaw as Map)
            : <String, dynamic>{};

        final protected = _isPowerupActive(powerups, 'protection');
        final extraDiff = _boostExtraDifficulty(powerups);
        final boosted = extraDiff > 0;

// base (cor por dono)
        Color fill = _territoryFillForOwner(t.ownerId);
        Color stroke = _territoryStrokeForOwner(t.ownerId);
        int strokeWidth = 2;

// 🛡️ protegido: “escudo azul”
        if (protected) {
          stroke = Colors.lightBlueAccent;
          fill = Colors.lightBlueAccent.withOpacity(0.10);
          strokeWidth = 4;
        }

// 🔥 boost: “aura roxa”
        if (boosted && !protected) {
          stroke = Colors.deepPurpleAccent;
          fill = Colors.deepPurpleAccent.withOpacity(0.08);
          strokeWidth = 3;
        }

// se tiver os dois, mantém borda azul e fill levemente roxo (gamer)
        if (protected && boosted) {
          fill = Colors.deepPurpleAccent.withOpacity(0.06);
        }

        DateTime? protectionUntil;
        final prot = powerups['protection'];
        if (prot is Map) {
          protectionUntil = _tsToDate(prot['until']);
        }

        if (protected && protectionUntil != null) {
          _protectionUntilByTerritory[t.id] = protectionUntil;
        } else {
          _protectionUntilByTerritory.remove(t.id);
        }

        if (boosted) {
          _boostExtraByTerritory[t.id] = extraDiff;
        } else {
          _boostExtraByTerritory.remove(t.id);
        }

// aplica polígono
        _polygonsByTerritory[t.id] = Polygon(
          polygonId: PolygonId('territorio_${t.id}'),
          points: t.points,
          fillColor: fill,
          strokeColor: stroke,
          strokeWidth: strokeWidth,
        );

// --- MARKER BADGE (opcional, mas recomendado) ---
        final hasStatus = protected || boosted;

        if (hasStatus && t.points.length >= 3) {
          final LatLng c = (t.points.isNotEmpty) ? _simpleCenter(t.points) : LatLng(
            (data['centerLat'] as num).toDouble(),
            (data['centerLng'] as num).toDouble(),
          );

          final title = protected
              ? '🛡️ Protegido'
              : '🔥 Dificuldade +$extraDiff';

          final snippet = protected
              ? 'Imune a tomadas até expirar'
              : 'Exige mais progresso para dominar';

          _statusMarkersByTerritory[t.id] = Marker(
            markerId: MarkerId('status_${t.id}'),
            position: c,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              protected ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueViolet,
            ),
            infoWindow: InfoWindow(title: title, snippet: snippet),
            zIndex: 999, // fica por cima
          );
        } else {
          _statusMarkersByTerritory.remove(t.id);
        }

      }

      // ✅ markers do dono — só cria se não existir
      for (final t in owners) {
        if (token != _mergeToken) return;

        if (_ownerMarkersByTerritory.containsKey(t.id)) {
          _markersDone++;
          if (mounted) setState(() {});
          continue;
        }

        await _addTerritoryOwnerMarker(
          territoryId: t.id,
          ownerId: t.ownerId,
          territoryPoints: t.points,
        );

        _markersDone++;
        if (mounted) setState(() {});
      }

      // ✅ atualiza controller com cache final
      _territoryController.territoryPolygons
        ..clear()
        ..addAll(_polygonsByTerritory.values);

      // ✅ disputas globais (inalterado)
      final activeDisputes = <String, Map<String, dynamic>>{};
      for (final d in filtered) {
        final data = d.data();
        if (data == null) continue;

        final dispute = data['dispute'];
        if (dispute is Map<String, dynamic> &&
            dispute['status'] == 'active') {
          activeDisputes[d.id] = dispute;
        }
      }

      _syncDisputeMarkers(activeDisputes.keys.toSet());

      for (final entry in activeDisputes.entries) {
        final tid = entry.key;
        final dispute = entry.value;

        final attackerId = (dispute['attackerId'] ?? '') as String;
        final defenderId = (dispute['defenderId'] ?? '') as String;
        if (attackerId.isEmpty || defenderId.isEmpty) continue;

        final t = _territories.firstWhere(
              (x) => x.id == tid,
          orElse: () => const _Territory(id: '', ownerId: '', points: []),
        );
        if (t.points.length < 3) continue;

        await _upsertGlobalDisputeMarker(
          territory: t,
          attackerId: attackerId,
          defenderId: defenderId,
        );
      }

      _pruneLoserMarkers();
    } catch (e) {
      debugPrint("❌ _applyTerritoryDocsMerged erro: $e");
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingTerritoryMarkers = false;
      });
    }
  }





// ==============================
// ASSINATURA DO TERRITÓRIO (DETECTA MUDANÇA VISUAL)
// ==============================
  String _makeTerritorySig(Map<String, dynamic> data) {
    final owner = (data['userId'] ?? '').toString();
    final pts = (data['points'] as List? ?? []);
    final ptsLen = pts.length;

    // se você tiver updatedAt no doc, melhor ainda
    final updated = (data['updatedAt'] ?? data['capturedAt'] ?? data['createdAt'] ?? '').toString();

    // disputa muda ícone/marker? então entra na assinatura também
    final dispute = data['dispute'];
    final disputeStatus = (dispute is Map) ? (dispute['status'] ?? '').toString() : '';

    return "$owner|$ptsLen|$updated|$disputeStatus";
  }

// ==============================
// DISTÂNCIA
// ==============================
  double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180.0;
    final dLon = (b.longitude - a.longitude) * pi / 180.0;

    final lat1 = a.latitude * pi / 180.0;
    final lat2 = b.latitude * pi / 180.0;

    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);

    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }


  bool _pointInPolygon(LatLng p, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;

      final intersects = ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude <
              (xj - xi) *
                  (p.latitude - yi) /
                  (((yj - yi) == 0) ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  Future<void> _showPreRunCountdown() async {
    int secondsLeft = 15;
    bool skipPressed = false;
    bool showGo = false;
    bool showFlash = false;
    Timer? countdownTimer;

    // 🎲 Sorteia frase e áudio
    final random = Random();
    final selected = preRunPhrases[random.nextInt(preRunPhrases.length)];
    final phrase = selected["text"]!;
    final audioPath = selected["audio"]!;

    // 🎧 Prepara e toca o áudio
    final player = AudioPlayer();
    await player.play(AssetSource(audioPath));

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) async {
              if (skipPressed) {
                timer.cancel();
                return;
              }

              if (secondsLeft > 1) {
                setState(() => secondsLeft--);
              } else if (secondsLeft == 1) {
                setState(() {
                  secondsLeft = 0;
                  showGo = true;
                });

                // 🔆 Flash + “GO!”
                await Future.delayed(const Duration(milliseconds: 100));
                setState(() => showFlash = true);
                await Future.delayed(const Duration(milliseconds: 300));
                setState(() => showFlash = false);

                await Future.delayed(const Duration(milliseconds: 400));
                Navigator.pop(context);
                _startRun();

                timer.cancel();
              }
            });

            return Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 🔢 Número da contagem regressiva centralizado corretamente
                    if (!showGo)
                      Align(
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Text(
                            "$secondsLeft",
                            key: ValueKey(secondsLeft),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 160,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              height: 1, // garante centralização vertical visual
                            ),
                          ),
                        ),
                      ),


                    // 🏁 Frase motivacional
                    Positioned(
                      top: 100,
                      left: 20,
                      right: 20,
                      child: Text(
                        phrase,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // ⏩ Botão “Iniciar agora”
                    Positioned(
                      bottom: 60,
                      left: 40,
                      right: 40,
                      child: ElevatedButton(
                        onPressed: () async {
                          skipPressed = true;
                          countdownTimer?.cancel();
                          await player.stop();
                          Navigator.pop(context);
                          _startRun();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: const Text(
                          "INICIAR AGORA",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),

                    // ⚡ GO! no final — centralizado e com animação suave
                    if (showGo)
                      Center(
                        child: AnimatedOpacity(
                          opacity: showFlash ? 0 : 1,
                          duration: const Duration(milliseconds: 300),
                          child: const Text(
                            "GO!",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 160,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: -5,
                              height: 1,
                            ),
                          ),
                        ),
                      ),


                    // ✨ Flash branco rápido
                    if (showFlash)
                      AnimatedOpacity(
                        opacity: showFlash ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(color: Colors.white),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    countdownTimer?.cancel();
    await player.stop();
    await player.dispose();
  }

  void _startRun() async {
    _runFinalized = false;      // ✅ libera salvar novamente
    _navigatingToDetails = false;

    await _loadUserWeight();


    _clearDisputeMarker();
    ScaffoldVisibilityController.hide();
    FlutterBackgroundService().startService();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
    }

    _positions.clear();
    _polylines.clear();
    _totalDistance = 0;
    _seconds = 0;
    _caloriesBurned = 0;
    _averagePace = 0;
    _sessionXP = 0;
    _distanceSinceLastXP = 0;
    _nextXPThreshold = 100;

    _altitudes.clear();
    _elevationGain = 0.0;
    _minElevation = 0.0;
    _maxElevation = 0.0;
    _lastAltFiltered = null;

    _currentSpeedMps = 0.0;
    _currentSpeedKmh = 0.0;
    _avgSpeedKmh = 0.0;
    _runSamples.clear();

    _stopwatch.reset();
    _stopwatch.start();
    _startTime = DateTime.now();

    setState(() {
      _isRunning = true;
      _isPaused = false;
    });

    await _playStart(); // som apenas no Wear

    _startTimerTick();
    _startPositionStream();
  }

  void _startTimerTick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds = _stopwatch.elapsed.inSeconds;
        _calculatePaceAndCalories();
      });
    });
  }

  void _startPositionStream() {
    _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((position) {
      final latLngPos = LatLng(position.latitude, position.longitude);

      // tempo decorrido (fora do setState pra ficar consistente)
      final secs = _stopwatch.elapsed.inSeconds;

      // velocidade instantânea (m/s -> km/h)
      final rawSpeed = position.speed;
      final currentSpeedMps = (rawSpeed.isFinite && rawSpeed >= 0) ? rawSpeed : 0.0;
      final currentSpeedKmh = currentSpeedMps * 3.6;

      // elevação + filtro simples (EMA)
      final alt = position.altitude;
      const alpha = 0.15;
      final filteredAlt = (_lastAltFiltered == null)
          ? alt
          : (_lastAltFiltered! + alpha * (alt - _lastAltFiltered!));

      // distância incremental
      double d = 0.0;
      if (_positions.isNotEmpty) {
        d = Geolocator.distanceBetween(
          _positions.last.latitude, _positions.last.longitude,
          latLngPos.latitude, latLngPos.longitude,
        );
      }

      // ✅ Atualiza estado/UI
      setState(() {
        // 1) distância + rota
        if (_positions.isEmpty) {
          _positions.add(latLngPos);
        } else {
          if (d > 0.5) {
            _totalDistance += d;
            _positions.add(latLngPos);

            // XP em tempo real
            _distanceSinceLastXP += d;
            if (_distanceSinceLastXP >= 100) {
              _distanceSinceLastXP -= 100;
              _sessionXP += 1;
              _showXPGainEffect("+1 XP");

              if (_sessionXP >= _nextXPThreshold) {
                _nextXPThreshold += 100;
                HapticFeedback.mediumImpact();
                _showXPLevelUp();
              }
            }

            if (!isWearOS) _updatePolyline();
          }
        }

        // 2) velocidade média
        _currentSpeedMps = currentSpeedMps;
        _currentSpeedKmh = currentSpeedKmh;

        if (secs > 0) {
          final avgMps = _totalDistance / secs;
          _avgSpeedKmh = avgMps * 3.6;
        } else {
          _avgSpeedKmh = 0.0;
        }

        // 3) ganho de elevação
        const minStep = 1.5;
        if (_lastAltFiltered != null) {
          final diff = filteredAlt - _lastAltFiltered!;
          if (diff.abs() >= minStep && diff > 0) {
            _elevationGain += diff;
          }
        }

        _lastAltFiltered = filteredAlt;
        _altitudes.add(filteredAlt);

        if (_altitudes.length == 1) {
          _minElevation = filteredAlt;
          _maxElevation = filteredAlt;
        } else {
          if (filteredAlt < _minElevation) _minElevation = filteredAlt;
          if (filteredAlt > _maxElevation) _maxElevation = filteredAlt;
        }

        // ✅ 4) Samples (AGORA NÃO DEPENDE DE BATER EXATAMENTE NO 5,10,15…)
        // grava a cada 5s desde o último sample
        if (secs - _lastSampleSecond >= 5) {
          _lastSampleSecond = secs;

          _runSamples.add({
            't': secs,
            'lat': latLngPos.latitude,
            'lng': latLngPos.longitude,
            'alt': filteredAlt,
            'speedKmh': _currentSpeedKmh,
            'distTotalM': _totalDistance,
          });

          // debug rápido pra você ver funcionando
          // debugPrint("🧪 sample+ t=$secs total=${_runSamples.length}");
        }

        // 5) animação / tracking
        _previousPosition = _currentPosition;
        _animatedPosition = latLngPos;
      });

      _animationController.forward(from: 0.0);

      if (!isWearOS && _followUser) {
        _googleMapController?.animateCamera(CameraUpdate.newLatLng(latLngPos));
      }
    });
  }



  void _pauseRun() {
    if (!_isRunning || _isPaused) return;

    _timer?.cancel();
    _stopwatch.stop();
    _positionStream?.pause();

    setState(() {
      _isPaused = true;
    });

    debugPrint("⏸ Corrida pausada. Tempo: ${_stopwatch.elapsed.inSeconds}s");
  }

  void _resumeRun() {
    if (!_isRunning || !_isPaused) return;

    _stopwatch.start();
    _startTimerTick();
    _positionStream?.resume();

    setState(() {
      _isPaused = false;
    });

    debugPrint("▶️ Corrida retomada.");
  }

  DateTime? _lastPointTime;

  void _updatePolyline() {
    if (isWearOS) return;
    if (_positions.length < 2) return;

    final i = _positions.length - 2;
    final start = _positions[i];
    final end = _positions[i + 1];

    final now = DateTime.now();
    double elapsed = 1.0;
    if (_lastPointTime != null) {
      elapsed = now.difference(_lastPointTime!).inMilliseconds / 1000;
    }
    _lastPointTime = now;

    final distance = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    if (distance < 0.5) return;

    final speed = (distance / elapsed).clamp(0.2, 6.0);

    final color = Color.lerp(
      const Color(0xFF3FA9F5),
      const Color(0xFFFF3D00),
      (speed / 6).clamp(0, 1),
    )!;

    final width = (4 + speed * 1.2).clamp(4, 12).toInt();

    _polylines.add(
      Polyline(
        polylineId: PolylineId('segment_$i'),
        points: [start, end],
        color: color.withOpacity(0.9),
        width: width,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );

    // ✅ Se estiver em modo livre, NÃO conquista território (nem calcula, nem desenha)
    if (_isFreeMode) {
      if (_areaCaptured != 0 || _areaCapturedFormatted != "0 m²" || _polygons.isNotEmpty) {
        _areaCaptured = 0;
        _areaCapturedFormatted = "0 m²";
        _polygons.clear();
      }
      return;
    }

    // 🟩 Atualiza área/plot do território (somente modo território)
    if (_positions.length >= 3) {
      _areaCapturedFormatted = _calculateAreaFormatted(_positions);
      _polygons
        ..clear()
        ..add(Polygon(
          polygonId: const PolygonId('territorio'),
          points: List.from(_positions),
          strokeColor: color,
          strokeWidth: 2,
          fillColor: color.withOpacity(0.3),
        ));
    }
  }


  // 🟩 NOVO: cálculo de área (m² ou km², com formatação automática)
  String _calculateAreaFormatted(List<LatLng> points) {
    if (_isFreeMode) {
      _areaCaptured = 0;
      return "0 m²";
    }
    if (points.length < 3) return "0 m²";

    const double earthRadius = 6378137.0;
    final refLat = points.first.latitude * math.pi / 180;
    final refLng = points.first.longitude * math.pi / 180;

    final projected = points.map((p) {
      final latRad = p.latitude * math.pi / 180;
      final lngRad = p.longitude * math.pi / 180;
      final x = (lngRad - refLng) * earthRadius * math.cos(refLat);
      final y = (latRad - refLat) * earthRadius;
      return Offset(x, y);
    }).toList();

    // Shoelace formula
    double area = 0;
    for (int i = 0; i < projected.length; i++) {
      final j = (i + 1) % projected.length;
      area += projected[i].dx * projected[j].dy - projected[j].dx * projected[i].dy;
    }

    area = area.abs() / 2.0;

    _areaCaptured = area; // ⬅️ agora o painel consegue saber se mostra (opacity)

    return (area >= 1_000_000)
        ? "${(area / 1_000_000).toStringAsFixed(2)} km²"
        : "${area.toStringAsFixed(0)} m²";

  }

  Future<void> _stopRun() async {
    _timer?.cancel();
    await _positionStream?.cancel();
    _positionStream = null;

    _stopwatch.stop();
    setState(() {
      _isRunning = false;
      _isPaused = false;
    });

    await _playStop(); // som apenas no Wear
    ScaffoldVisibilityController.show();
    FlutterBackgroundService().invoke('stopService');

    // 🚫 Evita corrida inválida
    if (_totalDistance < 10) {
      debugPrint("[RUN] Corrida muito curta (${_totalDistance.toStringAsFixed(2)} m) — não salva.");
      return;
    }

    if (!mounted) return;

    // ✅ garante métricas finais atualizadas antes de salvar
    _calculatePaceAndCalories();

    // ✅ AQUI salva (e ele mesmo navega pro detalhe)
    await _saveRun(wearMode: isWearOS);
  }



  void _calculatePaceAndCalories() {
    final dMeters = _totalDistance;
    final secs = _stopwatch.elapsed.inSeconds;

    if (secs > 0 && dMeters > 1) {
      final km = dMeters / 1000.0;

      // 🏃 Pace médio (min/km)
      _averagePace = (secs / 60.0) / km;

      // 🚀 Velocidade média (km/h)
      _avgSpeedKmh = km / (secs / 3600.0);

      // 🔥 Calorias realistas com peso
      // fator 1.0 = corrida moderada
      _caloriesBurned = km * _userWeightKg * 1.0;
    } else {
      _averagePace = 0.0;
      _avgSpeedKmh = 0.0;
      _caloriesBurned = 0.0;
    }
  }



  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  String _formatPace(double pace) {
    if (pace.isInfinite || pace.isNaN || pace <= 0) return '00:00';
    int minutes = pace.floor();
    int seconds = ((pace - minutes) * 60).round();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _setOnlineInitially() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _lastSavedPositionOnline = LatLng(pos.latitude, pos.longitude);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': true,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _startOnlineTracking();
      debugPrint("✅ Usuário inicializado como online em ${pos.latitude}, ${pos.longitude}");
    } catch (e) {
      debugPrint("❌ Erro ao inicializar online: $e");
    }
  }

  void _startOnlineTracking() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _onlinePositionStream?.cancel();
    _onlinePositionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 100, // evita atualizações muito próximas
      ),
    ).listen((pos) async {
      if (_lastSavedPositionOnline == null) {
        _lastSavedPositionOnline = LatLng(pos.latitude, pos.longitude);
        return;
      }

      final dist = Geolocator.distanceBetween(
        _lastSavedPositionOnline!.latitude,
        _lastSavedPositionOnline!.longitude,
        pos.latitude,
        pos.longitude,
      );

      if (dist >= 500) {
        _lastSavedPositionOnline = LatLng(pos.latitude, pos.longitude);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint("📍 Localização atualizada após mover ${dist.toStringAsFixed(0)}m");
      }
    });
  }

  Future<void> _toggleOnlineStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isOnline = !_isOnline);

    if (_isOnline) {
      await _setOnlineInitially();
    } else {
      _onlinePositionStream?.cancel();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint("🛑 Usuário ficou offline");
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isOnline ? "🟢 Você está online!" : "🔴 Você ficou offline"),
        duration: const Duration(seconds: 2),
      ));
    }
  }



  @override
  void dispose() {
    _territoriesSub?.cancel();
    _territoriesSub = null;
    _powerupTicker?.cancel();
    _timer?.cancel();
    _positionStream?.cancel();
    _animationController.dispose();
    _googleMapController?.dispose();
    _audio.dispose();
    _onlinePositionStream?.cancel();
    _setOfflineOnExit();

    super.dispose();
  }


  // ===== UI =====

  // Wear OS: UI leve, sem Google Map
  // 🕶️ -------- WEAR OS BODY (cronômetro + botão central + métricas) --------


  Widget _buildActiveChallengePanel(Map<String, dynamic> challenge, String challengeId) {
    final title = challenge['title'] ?? 'Desafio sem nome';
    final distanceTargetKm = (challenge['distance'] ?? 0).toDouble();
    final deadline = (challenge['deadline'] as Timestamp?)?.toDate();
    final now = DateTime.now();

    final timeLeft = deadline != null ? deadline.difference(now) : Duration.zero;
    final daysLeft = timeLeft.inDays >= 0 ? timeLeft.inDays : 0;

    final userId = FirebaseAuth.instance.currentUser!.uid;
    final userProgressMeters = (challenge['progress']?[userId]?['distance'] ?? 0).toDouble();
    final userProgressKm = userProgressMeters / 1000.0;

    final progress = distanceTargetKm > 0 ? (userProgressKm / distanceTargetKm).clamp(0.0, 1.0) : 0.0;
    final progressPercent = (progress * 100).toStringAsFixed(0);

    // 🔸 Verifica status do desafio (para ocultar se encerrado ou concluído)
    final participants = (challenge['participants'] ?? []) as List;
    final quitters = (challenge['quitters'] ?? []) as List? ?? [];
    final participantStatus = (challenge['progress']?[userId]?['status'] ?? 'active').toString();

    final isAuthor = challenge['authorId'] == userId;
    final isParticipant = participants.contains(userId) && !quitters.contains(userId);
    final isActive = (
        participantStatus == 'active' ||
            participantStatus == 'in_progress' ||
            participantStatus.isEmpty
    ) && daysLeft >= 0;


    if (!isActive || !isParticipant) return const SizedBox(); // ✅ não exibe se encerrado, concluído ou não participante

    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Cabeçalho fixo (minimizado inicialmente)
            GestureDetector(
              onTap: () => setState(() {
                _isChallengePanelVisible = !_isChallengePanelVisible;
              }),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6D00),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Desafio ativo",
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(
                    _isChallengePanelVisible
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),

            // 🔻 Conteúdo expansível
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _isChallengePanelVisible
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "🏁 $title",
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Meta: ${distanceTargetKm.toStringAsFixed(1)} km",
                      style: GoogleFonts.poppins(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      daysLeft > 0
                          ? "Prazo: $daysLeft dias restantes"
                          : "⏰ Desafio encerrando hoje!",
                      style: GoogleFonts.poppins(
                        color: daysLeft > 0 ? Colors.black54 : Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 🔸 Barra de progresso com gradiente laranja
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFF6D00),
                                  Color(0xFFFFA726),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 📊 Progresso numérico
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$progressPercent% concluído",
                          style: GoogleFonts.poppins(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          "${userProgressKm.toStringAsFixed(1)} / ${distanceTargetKm.toStringAsFixed(1)} km",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFFF6D00),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ❌ Botão cancelar
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _confirmCancelChallenge(challengeId),
                        icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                        label: Text(
                          "Cancelar inscrição",
                          style: GoogleFonts.poppins(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          backgroundColor: Colors.redAccent.withOpacity(0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancelChallenge(String challengeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("Tem certeza?",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          "😢 Se você desistir, seu nome vai brilhar no mural dos desistentes!\nTem certeza mesmo?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Voltar", style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Desistir 😭",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('posts').doc(challengeId).update({
        'quitters': FieldValue.arrayUnion([userId]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Você desistiu do desafio 😅"),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }




  Widget _buildMetricWear(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))
      ],
    );
  }

  // Mobile: UI completa com Google Map e tudo
  Widget _buildMobileBody() {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "RUNNER",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 🗺️ Mapa branco e cinza
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 16,
            ),
            onMapCreated: (controller) async {
              _googleMapController = controller;
              _mapReady = true;
              await _updateMarker();
              final style = await rootBundle.loadString('assets/map_style/white_map.json');
              _googleMapController?.setMapStyle(style);
            },
            polylines: _polylines,
            polygons: {..._polygons, ..._territoryController.territoryPolygons},
            markers: _markers,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),

          // 🌫️ Vinheta branca suave — estilo névoa real
          IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    Colors.white.withOpacity(0.0),   // centro transparente
                    Colors.white.withOpacity(0.8),   // camada média
                    Colors.white.withOpacity(1.0),   // bordas levemente brancas
                    Colors.white,                    // extremidades totalmente brancas
                  ],
                  stops: const [0.4, 0.7, 0.9, 1.0],
                ),
              ),
            ),
          ),

          // 🏁 Desafio ativo (card moderno)
          if (_challengeStream != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 220,
              left: 0,
              right: 0,
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _challengeStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();

                  final data = snapshot.data!.data();
                  if (data == null) return const SizedBox();

                  final participants = (data['participants'] ?? []) as List;
                  final userId = FirebaseAuth.instance.currentUser!.uid;
                  final isAuthor = data['authorId'] == userId;

                  // só mostra se o usuário participa do desafio ou é o criador
                  if (!participants.contains(userId) && !isAuthor) return const SizedBox();

                  return _buildActiveChallengePanel(data, snapshot.data!.id);
                },
              ),
            ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 230,
            left: 0,
            right: 0,
            child: Center(
              child: TerritoryModeToggle(
                mode: _territoryController.mode,
                onChange: (newMode) async {
                  if (newMode == _territoryController.mode) return;

                  _invalidateOverlayJobs();

                  _territoryController.setMode(
                    newMode,
                    onUpdate: () {
                      if (mounted) setState(() {});
                    },
                  );

                  if (newMode == MapTerritoryMode.livre) {
                    // ✅ PAUSA (não cancela listeners)
                    _territoryPaused = true;

                    if (mounted) {
                      setState(() {
                        _loadingTerritoryMarkers = false;
                        _markersDone = 0;
                        _markersTotal = 0;
                        _clearMapOverlaysForFreeMode(); // some do mapa
                      });
                    }

                    if (!isWearOS) _updateMarker();
                    return;
                  }

                  // ==========================
                  // ✅ VOLTOU PRO TERRITÓRIO/GLOBAL
                  // ==========================

                  _territoryPaused = false;

                  // ✅ reaplica cache instantâneo (sem loading)
                  if (mounted) {
                    setState(() {
                      _loadingTerritoryMarkers = false;
                      _markersDone = 0;
                      _markersTotal = 0;
                      _reapplyTerritoryCacheToMap();
                    });
                  }

                  // ✅ restaura overlays globais (pin/corrida)
                  await _restoreGlobalOverlays();

                  // ✅ opcional: refresh silencioso (sem banner)
                  // Só se quiser garantir que pegou mudanças enquanto estava no Livre.
                  // Não precisa setar loading!
                  _lastQueryCenter = null;
                  await _loadTerritories();

                  if (mounted) setState(() {});
                },


              ),
            ),
          ),




          // 🕒 Cronômetro e métricas superiores
          Positioned(
            top: MediaQuery.of(context).padding.top + 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _formatDuration(Duration(seconds: _seconds)),
                  style: GoogleFonts.poppins(
                    fontSize: 50,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMetricCard(Icons.route, (_totalDistance / 1000).toStringAsFixed(2), "Km"),
                    _buildMetricCard(Icons.local_fire_department, _caloriesBurned.round().toString(), "Kcal"),
                    _buildMetricCard(Icons.timer, _formatPace(_averagePace), "Ritmo"),
                  ],
                ),
              ],
            ),
          ),


          // ⚫ Controles da corrida (start / pausar / retomar + slide para parar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomRunControls(),
          ),


          // 🔘 Botão recenter
          Positioned(
            top: MediaQuery.of(context).padding.top + MediaQuery.of(context).size.height * 0.74,
            right: 20,
            child: GestureDetector(
              onTap: _recenterMap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded, color: Colors.black, size: 26),
              ),
            ),
          ),

          if (_activeDisputeTerritoryId != null)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  MediaQuery.of(context).size.height * 0.74 -
                  60, // 👈 fica acima do Online/Offline
              right: 20,
              child: GestureDetector(
                onTap: () async {
                  final id = _activeDisputeTerritoryId!;
                  await _cancelGlobalDispute(id);

                  if (!mounted) return;
                  setState(() {
                    _activeDisputeTerritoryId = null;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("❌ Disputa cancelada"),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cancel_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Cancelar disputa",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),


          // 🌐 Online/Offline — minimalista
          Positioned(
            top: MediaQuery.of(context).padding.top + MediaQuery.of(context).size.height * 0.74,
            left: 20,
            child: GestureDetector(
              onTap: _toggleOnlineStatus,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: Colors.black,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isOnline ? "Online" : "Offline",
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loadingTerritoryMarkers)
            Positioned(
              top: MediaQuery.of(context).padding.top + 290, // acima do toggle
              left: 12,
              right: 12,
              child: _buildTerritoryLoadingBanner(),
            ),
        ],
      ),
    );
  }

  Widget _buildTerritoryLoadingBanner() {
    final text = (_markersTotal <= 0)
        ? "Carregando territórios…"
        : "Carregando marcadores… $_markersDone/$_markersTotal";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSlideToStopButton() {
    final double progress = (_slideDragValue / 180).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _slideDragValue += details.primaryDelta ?? 0;
          _slideDragValue = _slideDragValue.clamp(0.0, 180.0);
        });
      },
      onHorizontalDragEnd: (details) async {
        if (_slideDragValue > 120) {
          HapticFeedback.mediumImpact();

          // 👉 encerra a corrida
          await _stopRun();

          setState(() {
            _slideDragValue = 0.0;
            // _isRunning = false;  // se o _stopRun já seta, nem precisa aqui
          });
        } else {
          HapticFeedback.lightImpact();
          setState(() => _slideDragValue = 0.0);
        }
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 65,
            width: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),

          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            height: 65,
            width: (240 * progress).clamp(0, 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.horizontal(
                left: const Radius.circular(40),
                right: Radius.circular(progress > 0.98 ? 40 : 10),
              ),
              color: Colors.grey[300],
            ),
          ),

          SizedBox(
            height: 65,
            width: 240,
            child: Center(
              child: Text(
                progress > 0.9 ? "Solte para parar 🏁" : "⬅️ Deslize para parar",
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(progress > 0.9 ? 1 : 0.9),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  fontSize: 14,
                ),
              ),
            ),
          ),

          Positioned(
            left: _slideDragValue.clamp(0, 175),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 65,
              width: 65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop_rounded,
                color: Colors.black,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRunControls() {
    // 👉 Quando não está em corrida, você pode mostrar o botão de INICIAR
    if (!_isRunning) {
      return SafeArea(
        minimum: const EdgeInsets.only(bottom: 24),
        child: Center(
          child: GestureDetector(
            onTap: _showPreRunCountdown,
            child: Container(
              height: 90,
              width: 90,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFFFF6D00),
                size: 48,
              ),
            ),
          ),
        ),
      );
    }



    // 👉 Quando está em corrida (rodando ou pausada)
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔘 Botão redondo de pausar/retomar
          GestureDetector(
            onTap: _isPaused ? _resumeRun : _pauseRun,
            child: Container(
              height: 70,
              width: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isPaused ? "Retomar" : "Pausar",
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),

          // 🏁 Slide para encerrar corrida
          _buildSlideToStopButton(),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return _buildMobileBody();
  }

  // 🔲 Cards de métricas — branco com texto preto e fonte Adidas
  Widget _buildMetricCard(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.black, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.black54,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  LatLng _computeCenterFromPoints(List<Map<String, dynamic>> pts) {
    // média simples (boa o suficiente pro “raio” e muito estável)
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += (p['lat'] as num).toDouble();
      lng += (p['lng'] as num).toDouble();
    }
    final n = pts.isEmpty ? 1 : pts.length;
    return LatLng(lat / n, lng / n);
  }

  String _geohashOf(LatLng c) {
    final p = _geo.precisionForRadius(250); // ou o raio que você usa no app
    return _geo.encode(c.latitude, c.longitude, precision: p);
  }

  bool _runFinalized = false;

  // ===== Persistência =====
  Future<void> _saveRun({bool wearMode = false}) async {
    // ✅ impede dupla execução
    if (_savingRun) return;

    // ✅ impede disparar de novo ao voltar da tela de detalhes (lifecycle/stream/etc)
    if (_runFinalized) {
      debugPrint("🚫 _saveRun ignorado: runFinalized=true (aguardando nova corrida)");
      return;
    }

    _savingRun = true;

    try {
      _calculatePaceAndCalories();

      // ✅ snapshot IMEDIATO (fonte de verdade pra validação e salvamento)
      final positionsSnapshot = List<LatLng>.from(_positions);
      final distanceSnapshot = _totalDistance; // metros
      final durationSnapshot = _stopwatch.elapsed.inSeconds;
      final avgPaceSnapshot = _averagePace;
      final caloriesSnapshot = _caloriesBurned;
      final avgSpeedSnapshot = _avgSpeedKmh;
      final currentSpeedSnapshot = _currentSpeedKmh;
      final elevationGainSnapshot = _elevationGain;
      final minElevationSnapshot = _minElevation;
      final maxElevationSnapshot = _maxElevation;

      final List<String> capturedTerritoryIds = [];
      final List<String> claimedTerritoryIds = []; // se quiser separar "sem dono"
      final List<String> newTerritoryIds = [];     // expansões criadas


      final distanceMeters = distanceSnapshot;
      final distanceKm = distanceMeters / 1000.0;

      final endTime = DateTime.now();

      // ✅ lastPos vem do snapshot (não do estado vivo)
      final lastPos = positionsSnapshot.isNotEmpty ? positionsSnapshot.last : null;

      // ✅ BLOQUEIA CORRIDA CURTA AQUI TAMBÉM
      if (distanceSnapshot < 10) {
        debugPrint("[RUN] Corrida muito curta (${distanceSnapshot.toStringAsFixed(2)} m) — não salva.");

        if (context.mounted && !wearMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Corrida muito curta — não foi salva.")),
          );
        }

        return;
      }

      if (loading) return;
      setState(() => loading = true);

      int capturedInThisRun = 0;

      if (context.mounted) _showLoadingOverlay(context);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (context.mounted) _hideLoadingOverlay(context);
        if (context.mounted && !wearMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Usuário não autenticado. Login necessário para salvar.")),
          );
        }
        setState(() => loading = false);
        return;
      }

      RunWeather? weather;
      if (lastPos != null) {
        weather = await WeatherService.fetchForRun(
          lat: lastPos.latitude,
          lng: lastPos.longitude,
          endTime: endTime,
        );
      }

      final runData = {
        'userId': user.uid,
        'startTime': _startTime?.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': durationSnapshot,
        'distance': distanceMeters,
        'calories': caloriesSnapshot,
        'pace': avgPaceSnapshot,
        'path': positionsSnapshot.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'avgSpeedKmh': avgSpeedSnapshot,
        'currentSpeedKmh': currentSpeedSnapshot,
        'elevationGain': elevationGainSnapshot,
        'minElevation': minElevationSnapshot,
        'maxElevation': maxElevationSnapshot,
        'weather': weather?.toMap(),
      };

      // ✅ rota pra território sempre do snapshot
      final pathSnapshot = List<LatLng>.from(positionsSnapshot);

      // ✅ Salva corrida
      final runRef = await FirebaseFirestore.instance.collection('corridas').add(runData);
      final runId = runRef.id;

      final corridaModel = RunModel(
        id: runId,
        userId: user.uid,
        distance: distanceMeters,
        duration: durationSnapshot,
        pace: avgPaceSnapshot,
        calories: caloriesSnapshot,
        date: DateTime.now(),
        route: pathSnapshot.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      );

      // ✅ (1) Capturar territórios existentes
      if (!_isFreeMode && pathSnapshot.length >= 3) {
        try {
          final dominance = await TerritoryService().checkTerritoryDominance(
            userId: user.uid,
            pace: avgPaceSnapshot,
            route: pathSnapshot.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
            context: null,
            activeDisputeTerritoryId: _activeDisputeTerritoryId,
            onTerritoryCaptured: ({
              required String territoryId,
              required String oldUserId,
              required String newUserId,
              required double progress,
            }) async {
              if (oldUserId.isNotEmpty) {
                capturedTerritoryIds.add(territoryId);
              } else {
                claimedTerritoryIds.add(territoryId);
              }
            },
          );

          capturedInThisRun = dominance.capturedCount;


// ✅ se não capturou nada, mas teve tentativa bloqueada, avisa
          if (context.mounted && capturedInThisRun == 0 && dominance.blocked.isNotEmpty) {
            // prioridade: proteção > progresso insuficiente
            final prot = dominance.blocked.where((b) => b.reason == TerritoryBlockReason.protected).toList();
            final info = prot.isNotEmpty ? prot.first : dominance.blocked.first;

            String msg;
            if (info.reason == TerritoryBlockReason.protected) {
              if (info.protectionUntil != null) {
                final d = info.protectionUntil!.difference(DateTime.now());
                final h = d.inHours;
                final m = d.inMinutes.remainder(60);
                final rem = h > 0 ? "${h}h ${m}m" : "${m}m";
                msg = "🛡️ Você cruzou um território protegido. Tente novamente em $rem.";
              } else {
                msg = "🛡️ Você cruzou um território protegido. Não dá pra dominar agora.";
              }
            } else {
              final p = (info.progress * 100).round();
              final r = (info.requiredThreshold * 100).round();
              msg = "🔥 Quase! Você fez $p% do território, mas precisava $r% pra dominar.";
            }

            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          }




          debugPrint("[TERRITORY] Capturados nesta corrida: $capturedInThisRun");
        } catch (e) {
          debugPrint("[TERRITORY] Erro no checkTerritoryDominance: $e");
        }
      }

      // ✅ (2) Criar NOVO território se não cruzou existente
      // ✅ depois de capturar territórios existentes, você pode criar expansão
      if (!_isFreeMode && pathSnapshot.length >= 3 && _areaCaptured > 0) {

        final route = pathSnapshot.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

        // ✅ pega só os pontos que ficaram FORA de territórios existentes
        final outsideRoute = await TerritoryService().extractOutsideRoute(route: route);

        // regra anti “território lixo”
        const int minOutsidePoints = 6;

        if (outsideRoute.length >= minOutsidePoints) {
          final center = _computeCenterFromPoints(
            outsideRoute.map((e) => Map<String, dynamic>.from(e)).toList(),
          );

          final geohash = _geohashOf(center);

          final terrRef = await FirebaseFirestore.instance.collection('territorios').add({
            'userId': user.uid,
            'points': outsideRoute,
            'geohash': geohash,
            'center': GeoPoint(center.latitude, center.longitude), // opcional, mas útil
            'area': _areaCaptured,
            'capturedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'type': 'expand',

            // ✅ ESSENCIAIS pro “carregar no raio”
            'centerLat': center.latitude,
            'centerLng': center.longitude,
            'geohash': geohash,
          });

          newTerritoryIds.add(terrRef.id);

          await terrRef.collection('ownership').add({
            'previousOwner': null,
            'newOwner': user.uid,
            'progress': 1.0,
            'pace': _averagePace,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'expand',
          });

          // ✅ incrementa contadores também (novo território criado)
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'territories': {
              'activeCount': FieldValue.increment(1),
              'capturedCount': FieldValue.increment(1),
            }
          }, SetOptions(merge: true));

          debugPrint("🧩 [TERRITORY] Expansão criada com pontos fora: ${outsideRoute.length}");
          await _loadTerritories();
        } else {
          debugPrint("🚫 [TERRITORY] Sem expansão: poucos pontos fora (${outsideRoute.length})");
        }
      }
      else {
        debugPrint('[TERRITORY] Novo território NÃO criado. free=$_isFreeMode pts=${pathSnapshot.length} area=$_areaCaptured');
      }

      // 🏆 Checa conquistas
      try {
        await Future.delayed(const Duration(milliseconds: 600));
        await AchievementService().checkAchievements(runData: runData, context: context);
      } catch (e) {
        debugPrint('Erro ao verificar conquistas: $e');
      }

      // 🏅 XP automático no salvamento
      try {
        int baseXP = (distanceKm * 10).floor() + 5;
        double xpMultiplier = 1.0;

        final isPro = (user.email ?? '').contains('pro');
        if (isPro) xpMultiplier *= 2.0;

        final inActiveChallenge = await _userHasActiveChallenge();
        if (inActiveChallenge) xpMultiplier *= 1.5;

        final totalXP = (baseXP * xpMultiplier).round();

        final minutes = (durationSnapshot / 60).floor();

        await GamificationService().addPoints(
          points: totalXP,
          source: "Corrida",
          description: "Concluiu ${distanceKm.toStringAsFixed(2)} km em $minutes min",
          meta: {
            'distanciaKm': distanceKm,
            'duracaoSeg': durationSnapshot,
            'duracaoMin': minutes,
            'calorias': caloriesSnapshot,
          },
          context: context,
        );

        await GamificationService().updateChallengesAfterRun(
          distanciaKm: distanceKm,
          xpGanho: totalXP,
          runCreatedAt: endTime,
          context: context,
        );


        _showXPAnimation("+$totalXP XP");
        await _updateLeaderboard();
      } catch (e) {
        debugPrint('Erro ao conceder XP no _saveRun: $e');
      }

      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🏁 Corrida salva com sucesso!')),
        );
      }

      await _loadTerritories();

      final samplesSnapshot = List<Map<String, dynamic>>.from(_runSamples);
      await _saveRunSamples(runRef: runRef, samples: samplesSnapshot);

      if (context.mounted && !wearMode) {
        // ✅ evita entrar duas vezes
        if (_navigatingToDetails) return;
        _navigatingToDetails = true;

        // ✅ a partir daqui: NÃO deixa salvar de novo até o usuário iniciar outra corrida
        _runFinalized = true;

        _hideLoadingOverlay(context);

        final capturedUnique = capturedTerritoryIds.toSet().toList();
        final claimedUnique = claimedTerritoryIds.toSet().toList();
        final newUnique = newTerritoryIds.toSet().toList();

        for (final id in capturedUnique) {
          await _promptNameTerritory(
            context: context,
            territoryId: id,
            title: "🏴 Você dominou um território! Dê um nome",
            onlyIfEmpty: false,
          );
        }

        for (final id in claimedUnique) {
          await _promptNameTerritory(
            context: context,
            territoryId: id,
            title: "🗺️ Território conquistado! Como ele vai se chamar?",
            onlyIfEmpty: true,
          );
        }

        for (final id in newUnique) {
          await _promptNameTerritory(
            context: context,
            territoryId: id,
            title: "✨ Novo território criado! Como ele vai se chamar?",
            onlyIfEmpty: true,
          );
        }

        if (!context.mounted) return;

        // ✅ IMPORTANTE: aguarda a navegação (evita liberar lock e chamar de novo)
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetalheCorridaPage(corrida: corridaModel)),
        );

        if (!mounted) return;

// ✅ 1) garante que o listener existe de novo
        await _loadTerritories();

// ✅ 2) recria o seu pin/overlays globais (corridas + marcador)
        await _restoreGlobalOverlays();
        if (!isWearOS) await _updateMarker();

// ✅ 3) força repaint
        if (mounted) setState(() {});

        // quando voltar da tela de detalhes, libera
        _navigatingToDetails = false;
      }



    } catch (e) {
      if (context.mounted && !wearMode) {
        _hideLoadingOverlay(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar corrida: $e")),
        );
      }
    } finally {
      if (context.mounted) _hideLoadingOverlay(context);

      if (mounted) {
        setState(() => loading = false);

        setState(() {
          _seconds = 0;
          _totalDistance = 0;
          _caloriesBurned = 0;
          _averagePace = 0;
          _positions.clear();

          if (!isWearOS) {
            _polylines.clear();

            // ✅ só limpa markers no modo LIVRE
            if (_territoryController.mode == MapTerritoryMode.livre) {
              _markers.clear();
            }
          }
        });
      }

      await _setInitialLocation();

      // ✅ libera lock
      _savingRun = false;
    }
  }

  Future<void> _promptNameTerritory({
    required BuildContext context,
    required String territoryId,
    required String title,
    bool onlyIfEmpty = true,
  }) async {
    // ✅ opcional: só pedir se estiver sem nome
    if (onlyIfEmpty) {
      final d = await FirebaseFirestore.instance.collection('territorios').doc(territoryId).get();
      final existing = (d.data()?['name'] ?? '').toString().trim();
      if (existing.isNotEmpty) return;
    }

    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            maxLength: 26,
            decoration: const InputDecoration(
              hintText: "Ex: Reino da Penha",
              counterText: "",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, null),
              child: const Text("Pular"),
            ),
            ElevatedButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.length < 3) return;
                Navigator.pop(dialogCtx, v);
              },
              child: const Text("Salvar"),
            ),
          ],
        );
      },
    );

    if (name == null) return;
    final v = name.trim();
    if (v.length < 3) return;

    await FirebaseFirestore.instance.collection('territorios').doc(territoryId).set({
      'name': v,
      'namedAt': FieldValue.serverTimestamp(),
      'namedBy': FirebaseAuth.instance.currentUser!.uid,
    }, SetOptions(merge: true));
  }

  Future<void> _saveRunSamples({
    required DocumentReference runRef,
    required List<Map<String, dynamic>> samples,
  }) async {
    if (samples.isEmpty) {
      debugPrint("⚠️ _saveRunSamples: vazio");
      return;
    }

    debugPrint("🧪 Salvando ${samples.length} samples em corridas/${runRef.id}/samples");

    final col = runRef.collection('samples');
    const chunkSize = 450;

    try {
      for (int i = 0; i < samples.length; i += chunkSize) {
        final chunk = samples.sublist(i, min(i + chunkSize, samples.length));
        final batch = FirebaseFirestore.instance.batch();

        for (final s in chunk) {
          // ✅ SANITIZA: só tipos simples
          final data = <String, dynamic>{
            't': (s['t'] as num?)?.toInt() ?? 0,
            'lat': (s['lat'] as num?)?.toDouble() ?? 0.0,
            'lng': (s['lng'] as num?)?.toDouble() ?? 0.0,
            'alt': (s['alt'] as num?)?.toDouble() ?? 0.0,
            'speedMps': (s['speedMps'] as num?)?.toDouble() ?? 0.0,
            'speedKmh': (s['speedKmh'] as num?)?.toDouble() ?? 0.0,
            'distTotalM': (s['distTotalM'] as num?)?.toDouble() ?? 0.0,
            'createdAt': FieldValue.serverTimestamp(),
          };

          batch.set(col.doc(), data);
        }

        await batch.commit();
        debugPrint("✅ batch commit ok: ${chunk.length} (offset=$i)");
      }

      debugPrint("🏁 Samples salvos com sucesso!");
    } catch (e, st) {
      debugPrint("❌ ERRO salvando samples: $e");
      debugPrint(st.toString());
      rethrow; // pra cair no catch do _saveRun
    }
  }

  Future<void> _updateLeaderboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 🔹 Busca XP e nome do usuário
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final xp = ((userDoc.data()?['xp'] ?? 0) as num).toDouble();
      final username = userDoc.data()?['displayName'] ?? user.email ?? 'Runner';

      // 🔹 Soma todas as distâncias válidas das corridas
      final query = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: user.uid)
          .get();

      double totalKm = 0.0;
      for (var doc in query.docs) {
        final data = doc.data();
        final rawDist = data['distance'];

        // ✅ Garante que é número antes de somar
        if (rawDist != null && rawDist is num) {
          totalKm += rawDist.toDouble() / 1000.0;
        }
      }

      // 🔹 Atualiza Leaderboard Global
      await FirebaseFirestore.instance
          .collection('leaderboard_global')
          .doc(user.uid)
          .set({
        'userId': user.uid,
        'displayName': username,
        'xp': xp,
        'km': double.parse(totalKm.toStringAsFixed(2)),
        'lastRunAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 🔹 Atualiza Leaderboard Semanal
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekId =
          "${weekStart.year}_${weekStart.month.toString().padLeft(2, '0')}_${weekStart.day.toString().padLeft(2, '0')}";

      await FirebaseFirestore.instance
          .collection('leaderboard_weekly')
          .doc("${weekId}-${user.uid}")
          .set({
        'userId': user.uid,
        'displayName': username,
        'xp': xp,
        'km': double.parse(totalKm.toStringAsFixed(2)),
        'weekStart': weekStart,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint("✅ Leaderboard atualizado: ${totalKm.toStringAsFixed(2)} km | $xp XP");
    } catch (e) {
      debugPrint('❌ Erro ao atualizar leaderboard: $e');
    }
  }

  void _showXPAnimation(String text) {
    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 20,
          left: 0, right: 0,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1200),
              builder: (context, t, _) {
                return Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(0, -40 * t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.4),
                            blurRadius: 16, spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(overlayEntry!);
    Future.delayed(const Duration(milliseconds: 1250), () {
      overlayEntry?.remove();
    });
  }

  void _showXPGainEffect(String text) {
    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 40,
          left: 0, right: 0,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              builder: (context, t, _) {
                return Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(0, -40 * t),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Color(0xFF4A90E2),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 10, color: Colors.blueAccent),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(overlay!);
    Future.delayed(const Duration(milliseconds: 850), () => overlay?.remove());
  }

  void _showXPLevelUp() {
    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                builder: (context, t, _) {
                  final opacity = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: 1 + 0.3 * (1 - opacity),
                      child: Text(
                        "⭐ LEVEL UP!",
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.yellowAccent.withOpacity(opacity),
                          shadows: const [
                            Shadow(blurRadius: 30, color: Colors.orangeAccent),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(overlay!);
    Future.delayed(const Duration(milliseconds: 1000), () => overlay?.remove());
  }

  void _clearTerritoryOwnerMarkers() {
    _markers.removeWhere((m) => m.markerId.value.startsWith('territory_owner_'));
  }


  Future<void> _addTerritoryOwnerMarker({
    required String territoryId,
    required String ownerId,
    required List<LatLng> territoryPoints,
  }) async {
    if (isWearOS) return;

    final int epoch = _overlayEpoch;

    // modo livre: não cria
    if (_territoryController.mode == MapTerritoryMode.livre) return;

    if (territoryPoints.length < 3) return;

    // ✅ centro do território
    final position = _territoryCenter(territoryPoints);

    try {
      // 🔎 busca dados do dono
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(ownerId).get();
      final data = userDoc.data() ?? {};
      final userName = (data['displayName'] as String?) ?? 'Jogador';
      final photoUrl = (data['photoURL'] as String?);

      const double size = 86;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      final center = Offset(size / 2, size / 2);
      final radius = size / 2;

      // 🎨 cor do território (pra combinar com o polígono)
      final strokeColor = _territoryStrokeForOwner(ownerId);

      // glow externo
      final glowPaint = Paint()
        ..color = strokeColor.withOpacity(0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
      canvas.drawCircle(center, radius - 2, glowPaint);

      // tenta carregar foto
      ui.Image? profileImage;
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          final imageData = await NetworkAssetBundle(Uri.parse(photoUrl)).load("");
          final bytes = imageData.buffer.asUint8List();
          profileImage = await decodeImageFromList(bytes);
        } catch (_) {}
      }

      if (profileImage == null) {
        // fundo + inicial
        paint.color = Colors.grey.shade900;
        canvas.drawCircle(center, radius - 5, paint);

        final textPainter = TextPainter(
          text: TextSpan(
            text: userName.isNotEmpty ? userName[0].toUpperCase() : "?",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
        );
      } else {
        // foto circular
        final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius - 5));
        canvas.save();
        canvas.clipPath(clipPath);
        paint.shader = ImageShader(
          profileImage,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity()
              .scaled(size / profileImage.width, size / profileImage.height)
              .storage,
        );
        canvas.drawCircle(center, radius - 5, paint);
        canvas.restore();
      }

      // borda dupla (branca + cor do dono)
      paint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.9);
      canvas.drawCircle(center, radius - 3, paint);

      paint
        ..strokeWidth = 4
        ..color = strokeColor.withOpacity(0.95);
      canvas.drawCircle(center, radius - 5, paint);

      final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

      final marker = Marker(
        markerId: MarkerId("territory_owner_$territoryId"),
        position: position,
        icon: BitmapDescriptor.fromBytes(bytes),
        anchor: const Offset(0.5, 0.5), // ✅ centralizado no território
        zIndex: 9000,
        onTap: () async {
          HapticFeedback.lightImpact();
          _showLoadingOverlay(context);
          await Future.delayed(const Duration(milliseconds: 300));
          if (!context.mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.pop(context);
              _showPlayerCard(
                context,
                ownerId,
                fromTerritory: true,
                territoryId: territoryId,
              );
            }
          });

        },

      );

      if (!mounted || epoch != _overlayEpoch || _territoryController.mode == MapTerritoryMode.livre) return;

      setState(() {
        // remove se já existia (pra atualizar)
        _markers.removeWhere((m) => m.markerId.value == "territory_owner_$territoryId");
        _markers.add(marker);
      });
    } catch (e) {
      debugPrint("❌ Erro ao criar marker do dono do território: $e");
    }
  }


  LatLng _territoryCenter(List<LatLng> pts) {
    if (pts.isEmpty) return _currentPosition;

    // média simples
    double latSum = 0, lngSum = 0;
    for (final p in pts) {
      latSum += p.latitude;
      lngSum += p.longitude;
    }
    final candidate = LatLng(latSum / pts.length, lngSum / pts.length);

    // se estiver fora, usa centro do bounds
    if (!_pointInPolygon(candidate, pts)) {
      double minLat = pts.first.latitude, maxLat = pts.first.latitude;
      double minLng = pts.first.longitude, maxLng = pts.first.longitude;

      for (final p in pts) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    }

    return candidate;
  }

  void _pruneLoserMarkers() {
    final List<Marker> kept = [];
    for (final m in _markers) {
      // Tente recuperar o runData que você salvou em _markerGestures[position]
      final tuple = _markerGestures[m.position]; // (userName, photoUrl, runData)
      final runData = tuple?.$3; // adapte se for outro tipo
      final runUserId = (runData?['userId'] ?? '') as String;

      // Se não temos runData, mantém
      if (runUserId.isEmpty) {
        kept.add(m);
        continue;
      }

      final t = _territories.firstWhere(
            (tt) => _pointInPolygon(m.position, tt.points),
        orElse: () => const _Territory(id: '', ownerId: '', points: []),
      );

      if (t.id.isEmpty || t.ownerId.isEmpty || t.ownerId == runUserId) {
        // Fora de território OU dono correto → mantém
        kept.add(m);
      } else {
        debugPrint("🧹 Removendo marcador de $runUserId dentro do território ${t.id} (dono: ${t.ownerId})");
      }
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(kept);
    });
  }



// 🔹 Armazena dados dos marcadores
  final Map<LatLng, (String, String?, Map<String, dynamic>)> _markerGestures = {};


  void _showLoadingOverlay(BuildContext context) {
    // evita abrir 2 vezes
    if (_overlayOpen) return;
    _overlayOpen = true;

    final lotties = [
      'assets/lottie/running1.json',
      'assets/lottie/running2.json',
    ];
    final selectedLottie = lotties[Random().nextInt(lotties.length)];

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'loading',
      barrierColor: Colors.white.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 180),
      routeSettings: const RouteSettings(name: _kLoadingRouteName),
      pageBuilder: (dialogCtx, _, __) {
        _overlayCtx = dialogCtx;

        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.9 + 0.1 * value,
                child: Opacity(
                  opacity: value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        height: 150,
                        width: 150,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.black.withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.deepOrangeAccent.withOpacity(0.3),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.deepOrangeAccent.withOpacity(0.4),
                              blurRadius: 25,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 80,
                              width: 80,
                              child: CircularProgressIndicator(
                                strokeWidth: 5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.deepOrangeAccent,
                                ),
                                backgroundColor: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            Lottie.asset(
                              selectedLottie,
                              height: 90,
                              width: 90,
                              fit: BoxFit.contain,
                              repeat: true,
                              animate: true,
                            ),
                            Positioned.fill(
                              child: AnimatedOpacity(
                                duration: const Duration(seconds: 1),
                                opacity: value > 0.5 ? 0.15 : 0.25,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Colors.deepOrangeAccent.withOpacity(0.5),
                                        Colors.transparent,
                                      ],
                                      radius: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      _overlayOpen = false;
      _overlayCtx = null;
    });
  }



  void _hideLoadingOverlay(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);

    // popa até remover a rota do overlay, se ela estiver no topo
    nav.popUntil((route) {
      // enquanto o topo for o overlay, continua “poppando”
      return route.settings.name != _kLoadingRouteName;
    });
  }

  Future<Map<String, dynamic>> _getPlayerStats(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      // Pega até 3 conquistas recentes
      final achievementsQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('achievements')
          .orderBy('timestamp', descending: true)
          .limit(3)
          .get();

      final achievements = achievementsQuery.docs
          .map((a) => a.data()['icon'] ?? '🏅')
          .toList();

      return {
        'displayName': userData['displayName'] ?? 'Jogador',
        'photoURL': userData['photoURL'],
        'xp': userData['xp'] ?? 0,
        'level': userData['level'] ?? 1,
        'achievements': achievements,
      };
    } catch (e) {
      debugPrint("Erro ao carregar estatísticas do jogador: $e");
      return {};
    }
  }

  Future<void> _showPlayerCard(
      BuildContext context,
      String userId, {
        Map<String, dynamic>? runData,
        bool fromTerritory = false,
        String? territoryId,
      }) async {
    runData ??= const <String, dynamic>{};

    debugPrint(
      "📊 Abrindo card para $userId | fromTerritory=$fromTerritory | keys=${runData.keys}",
    );

    final stats = await _getPlayerStats(userId);
    if (stats.isEmpty) {
      debugPrint("⚠️ Nenhum dado retornado — card abortado");
      return;
    }

    // ✅ só mantém "when" se você ainda quiser mostrar a data (opcional)
    final when = DateTime.tryParse((runData['endTime'] ?? '').toString()) ?? DateTime.now();

    Map<String, dynamic>? territory;
    Map<String, dynamic>? conquestRun;

    String _fmt2(int n) => n.toString().padLeft(2, '0');
    String _fmtDuration(int s) => "${_fmt2(s ~/ 3600)}:${_fmt2((s % 3600) ~/ 60)}:${_fmt2(s % 60)}";
    String _fmtPace(double p) {
      if (p.isNaN || p.isInfinite || p <= 0) return "00:00";
      final m = p.floor();
      final s = ((p - m) * 60).round();
      return "${_fmt2(m)}:${_fmt2(s)}";
    }

    // --- follow state (botão seguir + contadores) ---
    final currentUser = FirebaseAuth.instance.currentUser!;
    final followsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('following');

    bool isFollowing = false;
    int followersCount = 0;
    int followingCount = 0;

    try {
      final doc = await followsRef.doc(userId).get();
      isFollowing = doc.exists;

      final followersSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('followers')
          .get();
      followersCount = followersSnap.size;

      final followingSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('following')
          .get();
      followingCount = followingSnap.size;
    } catch (_) {}

    Future<void> toggleFollow(StateSetter setStateDialog) async {
      if (userId == currentUser.uid) return;

      final targetRef = FirebaseFirestore.instance.collection('users').doc(userId);

      if (isFollowing) {
        await followsRef.doc(userId).delete();
        await targetRef.collection('followers').doc(currentUser.uid).delete();
        setStateDialog(() {
          isFollowing = false;
          followersCount = followersCount > 0 ? followersCount - 1 : 0;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deixou de seguir o jogador')),
          );
        }
      } else {
        await followsRef.doc(userId).set({'followedAt': Timestamp.now()});
        await targetRef.collection('followers').doc(currentUser.uid).set({
          'followedAt': Timestamp.now(),
        });
        setStateDialog(() {
          isFollowing = true;
          followersCount += 1;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agora você segue este jogador')),
          );
        }
      }
    }

    // --- se veio de território: carrega dados do território + corrida da conquista ---
    if (fromTerritory && territoryId != null) {
      final terrDoc = await FirebaseFirestore.instance.collection('territorios').doc(territoryId).get();
      territory = terrDoc.data();

      final ownSnap = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territoryId)
          .collection('ownership')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (ownSnap.docs.isNotEmpty) {
        final own = ownSnap.docs.first.data();
        conquestRun = {
          'distance': (own['distance'] ?? 0),
          'duration': (own['duration'] ?? 0),
          'pace': (own['pace'] ?? 0.0),
          'calories': (own['calories'] ?? 0),
          'endTime': (own['timestamp'] is Timestamp)
              ? (own['timestamp'] as Timestamp).toDate().toIso8601String()
              : '',
        };

        final runId = (own['runId'] ?? '').toString();
        if (runId.isNotEmpty) {
          final runDoc = await FirebaseFirestore.instance.collection('corridas').doc(runId).get();
          if (runDoc.exists) conquestRun = runDoc.data();
        }
      }
    }

    await showGeneralDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: 'Fechar card do jogador',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final screenHeight = MediaQuery.of(context).size.height;
            final screenWidth = MediaQuery.of(context).size.width;

            final terrName = (territory?['name'] ?? territory?['customName'] ?? 'Território').toString();
            final difficulty = (territory?['difficulty'] ?? 1);
            final safety = (territory?['safety'] ?? 'unknown').toString();

            final dangerRaw = (territory?['dangerPoints'] as List?) ?? const [];
            final dangerPoints = dangerRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

            final powerupsRaw = territory?['powerups'];
            final powerups = (powerupsRaw is Map)
                ? Map<String, dynamic>.from(powerupsRaw as Map)
                : <String, dynamic>{};

            DateTime? _tsToDate(dynamic v) {
              if (v is Timestamp) return v.toDate();
              if (v is DateTime) return v;
              return null;
            }

            bool _isActive(Map<String, dynamic> p, String key) {
              final m = p[key];
              if (m is! Map) return false;
              final until = _tsToDate(m['until']);
              return m['active'] == true && until != null && until.isAfter(DateTime.now());
            }

            Duration? _remaining(Map<String, dynamic> p, String key) {
              final m = p[key];
              if (m is! Map) return null;
              final until = _tsToDate(m['until']);
              if (until == null) return null;
              final d = until.difference(DateTime.now());
              if (d.isNegative) return null;
              return d;
            }

            String _fmtRemaining(Duration d) {
              final h = d.inHours;
              final m = d.inMinutes.remainder(60);
              if (h > 0) return '${h}h ${m}m';
              return '${m}m';
            }

            final protectionActive = _isActive(powerups, 'protection');
            final protectionRem = _remaining(powerups, 'protection');

            final boostActive = _isActive(powerups, 'difficultyBoost');
            final boostRem = _remaining(powerups, 'difficultyBoost');

            int boostExtra = 0;
            final bm = powerups['difficultyBoost'];
            if (bm is Map && bm['extraDifficulty'] is num) {
              boostExtra = (bm['extraDifficulty'] as num).toInt();
            }


            String safetyLabel(String s) {
              if (s == 'danger') return 'Perigoso';
              if (s == 'safe') return 'Seguro';
              return 'Desconhecido';
            }

            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: screenWidth * 0.9,
                    constraints: BoxConstraints(maxHeight: screenHeight * 0.6),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.5),
                      border: Border.all(color: Colors.white),
                      boxShadow: const [BoxShadow(color: Colors.white)],
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 🔹 Cabeçalho
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(width: 40),
                              Text(
                                "Perfil do Jogador",
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded, color: Colors.black87),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // 🔹 Avatar + nome + XP/Nível
                          Row(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    top: 5,
                                    child: CircleAvatar(
                                      radius: 33,
                                      backgroundImage: stats['photoURL'] != null
                                          ? NetworkImage(stats['photoURL'])
                                          : null,
                                      backgroundColor: Colors.white,
                                      child: stats['photoURL'] == null
                                          ? const Icon(Icons.person, color: Colors.black54, size: 35)
                                          : null,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 85,
                                    width: 150,
                                    child: Lottie.asset(
                                      LevelFrameManager.getFrameForLevel(stats['level'] ?? 0),
                                      repeat: true,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          Navigator.pop(context);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Text(
                                            (stats['displayName'] ?? 'Jogador').toString(),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: GoogleFonts.poppins(
                                              color: Colors.black,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 20),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${(stats['xp'] as num).toStringAsFixed(0)} XP • Nível ${stats['level']}",
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            color: Colors.black87,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // ✅ Seguidores/seguindo + BOTÃO SEGUIR (sempre disponível)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "$followersCount seguidores • $followingCount seguindo",
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (userId != currentUser.uid)
                                ElevatedButton.icon(
                                  icon: Icon(
                                    isFollowing ? Icons.check : Icons.person_add_alt_1,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isFollowing ? "Seguindo" : "Seguir",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: isFollowing ? const Color(0xFFFF6D00) : Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () => toggleFollow(setStateDialog),
                                ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // 🏅 Conquistas recentes
                          if ((stats['achievements'] as List?)?.isNotEmpty == true)
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: (stats['achievements'] as List)
                                  .map<Widget>(
                                    (icon) => AnimatedScale(
                                  scale: 1.08,
                                  duration: const Duration(milliseconds: 400),
                                  child: Text(icon.toString(), style: const TextStyle(fontSize: 28)),
                                ),
                              )
                                  .toList(),
                            )
                          else
                            Text(
                              "Nenhuma insígnia conquistada ainda",
                              style: GoogleFonts.poppins(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                          const SizedBox(height: 16),

                          // ✅ Se veio de território, mantém card do território + métricas da conquista
                          if (fromTerritory) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withOpacity(0.7)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.public, color: Colors.black87),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          terrName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            color: Colors.black87,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _pill("Dificuldade do trajeto: $difficulty", Icons.trending_up),
                                      _pill("Segurança: ${safetyLabel(safety)}", Icons.shield),
                                      _pill("Pontos de atenção: ${dangerPoints.length}", Icons.warning_amber_rounded),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

// 🛡️/🔥 status do território (powerups)
                                  StreamBuilder<int>(
                                    stream: Stream.periodic(const Duration(seconds: 30), (x) => x),
                                    builder: (context, _) {
                                      final now = DateTime.now();

                                      Duration? remOf(String key) {
                                        final m = powerups[key];
                                        if (m is! Map) return null;
                                        final until = _tsToDate(m['until']);
                                        if (m['active'] != true || until == null) return null;
                                        final d = until.difference(now);
                                        if (d.isNegative) return null;
                                        return d;
                                      }

                                      final pr = remOf('protection');
                                      final br = remOf('difficultyBoost');

                                      final protOn = pr != null;
                                      final boostOn = br != null;

                                      if (!protOn && !boostOn) {
                                        return Text(
                                          "Sem proteção ativa",
                                          style: GoogleFonts.poppins(
                                            color: Colors.black54,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      }

                                      return Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (protOn)
                                            _pill("Protegido: ${_fmtRemaining(pr!)}", Icons.lock_clock),
                                          if (boostOn)
                                            _pill("🔥 Dificuldade de domínio +$boostExtra: ${_fmtRemaining(br!)}", Icons.local_fire_department),
                                        ],
                                      );
                                    },
                                  ),


                                  if (dangerPoints.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.map_outlined),
                                        label: const Text("Ver pontos de atenção no mapa"),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TerritoryDangerMapPage(
                                                territoryName: terrName,
                                                points: dangerPoints,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          // ✅ (Opcional) data — remova se não quiser mais mostrar nada de corrida aqui
                          const SizedBox(height: 10),
                          Text(
                            "${_fmt2(when.day)}/${_fmt2(when.month)}/${when.year}",
                            style: GoogleFonts.poppins(
                              color: Colors.black87,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
  }


  Widget _pill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: Colors.black87),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 14, // 🔑 PADRÃO
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }






}

Future<BitmapDescriptor> _createUserCircleIcon({
  double size = 60,
  Color borderColor = Colors.white,
  Color fillColor = Colors.blueAccent,
}) async {
  final pictureRecorder = ui.PictureRecorder();
  final canvas = Canvas(pictureRecorder);
  final paint = Paint()..isAntiAlias = true;

  // Fundo transparente
  canvas.drawColor(Colors.transparent, BlendMode.clear);

  // Círculo externo (borda)
  paint.color = borderColor;
  canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);

  // Círculo interno (preenchimento)
  paint.color = fillColor;
  canvas.drawCircle(Offset(size / 2, size / 2), size / 2.8, paint);

  final img =
  await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

class MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const MetricCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.85)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.black87), // ✅ menor
          const SizedBox(height: 8),

          // ✅ não deixa o texto “estourar”
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),

          const SizedBox(height: 2),

          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}



