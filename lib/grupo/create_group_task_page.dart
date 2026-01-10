// create_group_task_page.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class CreateGroupTaskPage extends StatefulWidget {
  final String groupId;
  const CreateGroupTaskPage({super.key, required this.groupId});

  @override
  State<CreateGroupTaskPage> createState() => _CreateGroupTaskPageState();
}

class _CreateGroupTaskPageState extends State<CreateGroupTaskPage> {
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _goal = TextEditingController(); // meta (km)

  bool _saving = false;

  bool _routeIsLoop = false;
  int _laps = 1;


  // ✅ Modalidade
  static const List<String> _modes = [
    'Corrida',
    'Caminhada',
    'Bike',
    'Trilha',
    'Natação',
    'Esteira',
  ];
  String _selectedMode = _modes.first;

  // ✅ Mapa / rota
  LatLng? _initialCenter;
  bool _loadingLocation = true;

  // rota final (salva)
  List<LatLng> _routePoints = [];
  double _routeKm = 0.0;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _goal.dispose();
    super.dispose();
  }

  void _syncGoalFromRoute() {
    if (_routePoints.length < 2) return;

    final base = _routeKm;
    final total = _routeIsLoop ? (base * _laps) : base;

    // escreve no campo Meta automaticamente
    _goal.text = total.toStringAsFixed(2).replaceAll('.', ',');
  }


  // ===========================
  // 📍 Localização inicial
  // ===========================
  Future<void> _initLocation() async {
    try {
      setState(() => _loadingLocation = true);

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _initialCenter = const LatLng(-22.9068, -43.1729); // fallback RJ
        if (mounted) setState(() => _loadingLocation = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      _initialCenter = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      _initialCenter = const LatLng(-22.9068, -43.1729);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // ===========================
  // 🧭 Distância (Haversine)
  // ===========================
  double _degToRad(double deg) => deg * (pi / 180.0);

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  double _computeRouteKm(List<LatLng> pts) {
    if (pts.length < 2) return 0.0;
    double meters = 0;
    for (int i = 1; i < pts.length; i++) {
      meters += _haversineMeters(pts[i - 1], pts[i]);
    }
    return meters / 1000.0;
  }

  // ===========================
  // 🗺️ Fullscreen editor
  // ===========================
  Future<void> _openRouteEditor() async {
    if (_initialCenter == null) return;

    final result = await Navigator.push<_RouteEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditorPage(
          initialCenter: _initialCenter!,
          initialPoints: _routePoints,
          accent: kOrange,
          bg: kBg,
          card: kCard,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _routePoints = result.points;
      _routeKm = result.km;
      _routeIsLoop = result.isLoop;

      if (!_routeIsLoop) _laps = 1; // se deixou de ser loop, reseta voltas
    });

    _syncGoalFromRoute();

  }

  // ===========================
  // ✅ Criar task no Firestore
  // ===========================
  Future<void> _createTask() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final title = _title.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Título muito curto.')),
      );
      return;
    }

    if (_routePoints.length >= 2) {
      // se tiver rota, meta vem do mapa
      _syncGoalFromRoute();
    }


    double? goalKm;
    final rawGoal = _goal.text.trim().replaceAll(',', '.');
    if (rawGoal.isNotEmpty) {
      goalKm = double.tryParse(rawGoal);
      if (goalKm == null || goalKm <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meta inválida. Use um número (ex: 5 ou 5.5).')),
        );
        return;
      }
    }

    final goalKmToSave = _routePoints.length >= 2
        ? (_routeIsLoop ? _routeKm * _laps : _routeKm)
        : goalKm;

    if (_routePoints.isNotEmpty && _routePoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Percurso precisa ter pelo menos 2 pontos.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _db.collection('groups').doc(widget.groupId).collection('tasks').add({
        'title': title,
        'description': _desc.text.trim(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,

        'isLoop': _routeIsLoop,
        'laps': _routeIsLoop ? _laps : 1,

        'mode': _selectedMode,
        'goalKm': goalKmToSave,

        'route': _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'routeKm': double.parse(_routeKm.toStringAsFixed(3)),
        'routeStart': _routePoints.isNotEmpty
            ? {'lat': _routePoints.first.latitude, 'lng': _routePoints.first.longitude}
            : null,
        'routeEnd': _routePoints.length >= 2
            ? {'lat': _routePoints.last.latitude, 'lng': _routePoints.last.longitude}
            : null,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar task: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String text, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: kOrange, size: 18),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
        ),
      ],
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kOrange.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kOrange.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: kOrange, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        title: const Text(
          'Criar Task',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 🧱 Infos
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(
                    hintText: 'Título (ex: Correr 5km)',
                    hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
                const Divider(color: Colors.white10, height: 18),
                TextField(
                  controller: _desc,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'Descrição (opcional)',
                    hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ⚙️ Config
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Configurações', icon: Icons.tune_rounded),
                const SizedBox(height: 12),

                // Modalidade
                Row(
                  children: [
                    const Icon(Icons.sports_mma_rounded, color: Colors.white54, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Modalidade:',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedMode,
                        dropdownColor: kCard,
                        iconEnabledColor: Colors.white70,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0B0B0F),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        items: _modes
                            .map(
                              (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, style: const TextStyle(color: Colors.white)),
                          ),
                        )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedMode = v ?? _modes.first),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Meta
                Row(
                  children: [
                    const Icon(Icons.flag_rounded, color: Colors.white54, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Meta (km):',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child:
                      TextField(
                        controller: _goal,
                        readOnly: _routePoints.length >= 2, // ✅ trava quando tem rota
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          hintText: _routePoints.length >= 2 ? 'Calculado automaticamente' : 'ex: 5',
                          hintStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                          filled: true,
                          fillColor: const Color(0xFF0B0B0F),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Percurso (abre fullscreen)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle('Percurso', icon: Icons.map_rounded),
                    _pill('${_routeKm.toStringAsFixed(2)} km'),
                  ],
                ),
                const SizedBox(height: 10),

                if (_loadingLocation)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator(color: kOrange)),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openRouteEditor,
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0B0F),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AbsorbPointer(
                                child: GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: _initialCenter ?? const LatLng(-22.9068, -43.1729),
                                    zoom: 14,
                                  ),
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: false,
                                  mapToolbarEnabled: false,
                                  polylines: {
                                    if (_routePoints.isNotEmpty)
                                      Polyline(
                                        polylineId: const PolylineId('preview'),
                                        points: _routePoints,
                                        width: 6,
                                        color: kOrange,
                                        geodesic: true,
                                      )
                                  },
                                  markers: {
                                    if (_routePoints.isNotEmpty)
                                      Marker(
                                        markerId: const MarkerId('start'),
                                        position: _routePoints.first,
                                      ),
                                    if (_routePoints.length >= 2)
                                      Marker(
                                        markerId: const MarkerId('end'),
                                        position: _routePoints.last,
                                      ),
                                  },
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Toque para abrir o editor em tela cheia',
                                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          if (_routeIsLoop) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.repeat_rounded, color: Colors.white54, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Voltas:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0B0F),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          splashRadius: 18,
                          onPressed: _laps > 1
                              ? () {
                            setState(() => _laps--);
                            _syncGoalFromRoute();
                          }
                              : null,
                          icon: const Icon(Icons.remove_rounded, color: Colors.white70),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '$_laps',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          splashRadius: 18,
                          onPressed: () {
                            setState(() => _laps++);
                            _syncGoalFromRoute();
                          },
                          icon: const Icon(Icons.add_rounded, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],


          // ✅ Criar
          ElevatedButton(
            onPressed: _saving ? null : _createTask,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: kOrange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _saving
                ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
            )
                : const Text('Criar', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// ✅ RouteEditorPage (FULLSCREEN)
// - Mapa fica livre pra mover/zoom normalmente
// - Modo "Marcar pontos" liga/desliga
// - Botão OK retorna rota + km
// =============================================================
class RouteEditorPage extends StatefulWidget {
  final LatLng initialCenter;
  final List<LatLng> initialPoints;
  final Color accent;
  final Color bg;
  final Color card;

  const RouteEditorPage({
    super.key,
    required this.initialCenter,
    required this.initialPoints,
    required this.accent,
    required this.bg,
    required this.card,
  });

  @override
  State<RouteEditorPage> createState() => _RouteEditorPageState();
}

class _RouteEditorPageState extends State<RouteEditorPage> {
  GoogleMapController? _controller;
  bool _markMode = true;

  bool _isLoop = false;

// distância máxima (em metros) pra considerar "fechou no início"
  static const double _closeThresholdMeters = 25.0;

  final List<LatLng> _points = [];
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  double _km = 0.0;

  @override
  void initState() {
    super.initState();
    _points.addAll(widget.initialPoints);
    _rebuild();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool _canCloseLoop(LatLng tapped) {
    if (_points.length < 3) return false; // precisa pelo menos 3 pontos pra virar circuito
    if (_isLoop) return false;

    final start = _points.first;
    final dist = _haversineMeters(start, tapped);
    return dist <= _closeThresholdMeters;
  }

  void _closeLoop() {
    if (_points.length < 3) return;
    if (_isLoop) return;

    // fecha: último ponto = primeiro
    _points.add(_points.first);
    _isLoop = true;
    _rebuild();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Circuito fechado ✅')),
    );
  }


  double _degToRad(double deg) => deg * (pi / 180.0);

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  double _computeKm(List<LatLng> pts) {
    if (pts.length < 2) return 0.0;
    double meters = 0;
    for (int i = 1; i < pts.length; i++) {
      meters += _haversineMeters(pts[i - 1], pts[i]);
    }
    return meters / 1000.0;
  }

  void _rebuild() {
    _km = _computeKm(_points);

    _polylines
      ..clear()
      ..add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _points,
          width: 7,
          color: widget.accent,
          geodesic: true,
        ),
      );

    _markers.clear();
    if (_points.isNotEmpty) {
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _points.first,
          consumeTapEvents: true, // 👈 importante: captura o tap no marker
          onTap: () {
            // fecha apenas se tiver como (>=3 pontos e ainda não fechou)
            if (_points.length >= 3 && !_isLoop) {
              _closeLoop();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Adicione mais pontos antes de fechar o circuito.')),
              );
            }
          },
          infoWindow: const InfoWindow(title: 'Início'),
        ),
      );
    }
    if (_points.length >= 2) {
      _markers.add(Marker(
        markerId: const MarkerId('end'),
        position: _points.last,
        infoWindow: const InfoWindow(title: 'Fim'),
      ));
    }

    setState(() {});
  }

  void _addPoint(LatLng p) {
    // Se tocar perto do início, fecha o circuito
    if (_canCloseLoop(p)) {
      _closeLoop();
      return;
    }

    // se já estava fechado e a pessoa tenta adicionar mais ponto,
    // abre o loop antes (remove o último = primeiro)
    if (_isLoop && _points.isNotEmpty) {
      _points.removeLast();
      _isLoop = false;
    }

    _points.add(p);
    _rebuild();
  }


  void _undo() {
    if (_points.isEmpty) return;

    // se estiver fechado, ao desfazer remove o fechamento primeiro
    if (_isLoop && _points.length >= 2) {
      _points.removeLast(); // remove ponto igual ao início
      _isLoop = false;
      _rebuild();
      return;
    }

    _points.removeLast();
    _rebuild();
  }

  void _clear() {
    _points.clear();
    _isLoop = false;
    _rebuild();
  }


  void _ok() {
    Navigator.pop(
      context,
      _RouteEditorResult(points: _points, km: _km, isLoop: _isLoop),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.bg,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ✅ MAPA FULLSCREEN (sem Positioned.fill)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.initialCenter,
                zoom: 14,
              ),
              onMapCreated: (c) => _controller = c,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              polylines: _polylines,
              markers: _markers,
              onTap: (pos) {
                if (_markMode) _addPoint(pos);
              },
            ),

            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false, // importante para não empurrar pra baixo
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      _GlassIconBtn(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                        accent: widget.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.route_rounded,
                                  color: widget.accent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _markMode
                                      ? 'Modo marcar pontos'
                                      : 'Modo mover mapa',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_km.toStringAsFixed(2)} km',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (_isLoop) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: widget.accent.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: widget.accent.withOpacity(0.45)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.loop_rounded, color: widget.accent, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'LOOP',
                                            style: TextStyle(
                                              color: widget.accent,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),


            // Right controls
            Positioned(
              right: 12,
              top: MediaQuery.of(context).padding.top + 74,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _GlassIconBtn(
                    icon: Icons.undo_rounded,
                    label: 'Desfazer',
                    onTap: _undo,
                    accent: widget.accent,
                  ),
                  const SizedBox(height: 10),
                  _GlassIconBtn(
                    icon: Icons.delete_outline_rounded,
                    label: 'Limpar',
                    onTap: _clear,
                    accent: widget.accent,
                  ),
                ],
              ),
            ),

            // Bottom bar (OK)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        _markMode
                            ? 'Toque no mapa para adicionar pontos do percurso.'
                            : 'Arraste/zoom livremente. Ative “Marcar” pra adicionar pontos.',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _ok,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: widget.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color accent;

  const _GlassIconBtn({
    required this.icon,
    this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 18),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(
                  label!,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Resultado do editor
class _RouteEditorResult {
  final List<LatLng> points;
  final double km;
  final bool isLoop;

  _RouteEditorResult({
    required this.points,
    required this.km,
    required this.isLoop,
  });
}

