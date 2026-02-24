import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/service/points_service.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class TerritoryDetailsPage extends StatefulWidget {
  final String territoryId;
  final bool isOwner;

  const TerritoryDetailsPage({
    super.key,
    required this.territoryId,
    required this.isOwner,
  });

  @override
  State<TerritoryDetailsPage> createState() => _TerritoryDetailsPageState();
}

class _DangerPoint {
  final LatLng pos;
  final String desc;
  _DangerPoint({required this.pos, required this.desc});
}

class _TerritoryDetailsPageState extends State<TerritoryDetailsPage> {
  final _nameCtrl = TextEditingController();

  int _difficulty = 1; // 1..5
  String _safety = 'safe'; // safe | danger
  bool _saving = false;

  GoogleMapController? _map;
  List<LatLng> _polygon = [];

  final List<_DangerPoint> _dangerPoints = [];
  bool _addingDangerPoint = false;

  bool _didInitFromDoc = false; // ✅ evita resetar campos toda hora

  bool _usePoints = false;
  int _myPoints = 0;
  bool _loadingPoints = false;

  @override
  void initState() {
    super.initState();
    _loadMyPoints();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ------------------------
  // Helpers
  // ------------------------
  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  LatLng? _toLatLng(Map<String, dynamic> m) {
    final lat = _toDouble(m['lat']);
    final lng = _toDouble(m['lng']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String _difficultyLabel(int v) {
    switch (v) {
      case 1:
        return 'Muito fácil';
      case 2:
        return 'Fácil';
      case 3:
        return 'Médio';
      case 4:
        return 'Difícil';
      case 5:
        return 'Muito difícil';
      default:
        return 'Médio';
    }
  }

  void _initFromDocOnce(Map<String, dynamic> data) {
    if (_didInitFromDoc) return;
    _didInitFromDoc = true;

    final customName = (data['customName'] ?? '').toString().trim();
    final baseName = (data['name'] ?? data['territoryName'] ?? '').toString().trim();
    _nameCtrl.text = customName.isNotEmpty ? customName : baseName;

    final d = data['difficulty'];
    _difficulty = (d is num) ? d.toInt().clamp(1, 5) : 1;

    final s = (data['safety'] ?? 'safe').toString();
    _safety = (s == 'danger' || s == 'safe') ? s : 'safe';

    final pts = (data['points'] as List?) ?? const [];
    _polygon = pts
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(_toLatLng)
        .whereType<LatLng>()
        .toList();

    _dangerPoints.clear();
    final dp = (data['dangerPoints'] as List?) ?? const [];
    for (final item in dp) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final ll = _toLatLng(m);
        if (ll != null) {
          _dangerPoints.add(_DangerPoint(
            pos: ll,
            desc: (m['desc'] ?? '').toString().trim(),
          ));
        }
      }
    }
  }

  Future<void> _loadMyPoints() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loadingPoints = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? {};
      final p = data['totalPoints'];
      _myPoints = (p is num) ? p.toInt() : 0;
    } finally {
      if (mounted) setState(() => _loadingPoints = false);
    }
  }

  Future<void> _save() async {
    if (!widget.isOwner) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('territorios').doc(widget.territoryId).set({
        'customName': _nameCtrl.text.trim(),
        'difficulty': _difficulty,
        'safety': _safety,
        'dangerPoints': _dangerPoints
            .map((p) => {
          'lat': p.pos.latitude,
          'lng': p.pos.longitude,
          'desc': p.desc,
        })
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Território atualizado ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  LatLng _fallbackCenter() {
    if (_polygon.isNotEmpty) return _polygon.first;
    if (_dangerPoints.isNotEmpty) return _dangerPoints.first.pos;
    return const LatLng(-22.9068, -43.1729);
  }

  Set<Polygon> _polygons(SeasonTheme s) {
    if (_polygon.length < 3) return {};
    return {
      Polygon(
        polygonId: const PolygonId('territory'),
        points: _polygon,
        strokeWidth: 2,
        strokeColor: s.primary,
        fillColor: s.primary.withOpacity(0.15),
      )
    };
  }

  Future<String?> _askDangerDescription(SeasonTheme s, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);

    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.popover,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 60,
              decoration: BoxDecoration(
                color: s.muted.withOpacity(0.8),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Descrever ponto de atenção',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: s.popoverForeground,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 120,
              style: TextStyle(color: s.foreground),
              decoration: InputDecoration(
                hintText: 'Ex: Rua escura / cruzamento perigoso / cães soltos...',
                hintStyle: TextStyle(color: s.mutedForeground),
                filled: true,
                fillColor: s.input.withOpacity(0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: s.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: s.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: s.ring, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: s.foreground,
                      side: BorderSide(color: s.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: s.primary,
                      foregroundColor: s.primaryForeground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    child: const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Set<Marker> _markers(SeasonTheme s) {
    final set = <Marker>{};

    for (int i = 0; i < _dangerPoints.length; i++) {
      final p = _dangerPoints[i];
      set.add(
        Marker(
          markerId: MarkerId('danger_$i'),
          position: p.pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Ponto de atenção',
            snippet: p.desc.isEmpty ? 'Sem descrição' : p.desc,
            onTap: widget.isOwner
                ? () async {
              final action = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: s.popover,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.edit, color: s.foreground),
                        title: Text('Editar descrição', style: TextStyle(color: s.foreground)),
                        onTap: () => Navigator.pop(ctx, 'edit'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete, color: Colors.red),
                        title: const Text('Remover ponto', style: TextStyle(color: Colors.red)),
                        onTap: () => Navigator.pop(ctx, 'delete'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );

              if (action == 'delete') {
                setState(() => _dangerPoints.removeAt(i));
                await _save();
                return;
              }

              if (action == 'edit') {
                final desc = await _askDangerDescription(s, initial: p.desc);
                if (desc == null) return;

                setState(() {
                  _dangerPoints[i] = _DangerPoint(pos: p.pos, desc: desc);
                });
                await _save();
              }
            }
                : null,
          ),
        ),
      );
    }

    return set;
  }

  Widget _card(SeasonTheme s, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  Widget _powerButton({
    required SeasonTheme s,
    required String label,
    required int cost,
    required Future<void> Function() onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.secondary,
          foregroundColor: s.secondaryForeground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () async {
          if (_myPoints < cost) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Pontos insuficientes 😭 (custa $cost)')),
            );
            return;
          }
          await onTap();
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('$cost pts', style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final docRef = FirebaseFirestore.instance.collection('territorios').doc(widget.territoryId);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        title: const Text('Detalhes do território'),
        backgroundColor: s.background,
        foregroundColor: s.foreground,
        elevation: 0,
        actions: [
          if (widget.isOwner)
            IconButton(
              icon: _saving
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.save_outlined),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: s.primary),
            );
          }

          final data = snap.data!.data() ?? {};
          _initFromDocOnce(data); // ✅ não reseta _safety/_difficulty toda hora

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                s,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personalize este território',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: s.cardForeground,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _nameCtrl,
                      enabled: widget.isOwner,
                      style: TextStyle(color: s.foreground),
                      decoration: InputDecoration(
                        labelText: 'Nome do território',
                        hintText: 'Ex: Pista do Aterro',
                        labelStyle: TextStyle(color: s.mutedForeground),
                        hintStyle: TextStyle(color: s.mutedForeground),
                        filled: true,
                        fillColor: s.input.withOpacity(0.9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: s.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: s.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: s.ring, width: 1.6),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Dificuldade',
                            style: TextStyle(fontWeight: FontWeight.w800, color: s.cardForeground),
                          ),
                        ),
                        Text(
                          _difficultyLabel(_difficulty),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: s.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _difficulty.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: _difficultyLabel(_difficulty),
                      onChanged: widget.isOwner ? (v) => setState(() => _difficulty = v.round()) : null,
                      activeColor: s.primary,
                      inactiveColor: s.muted.withOpacity(0.7),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'Segurança do local',
                      style: TextStyle(fontWeight: FontWeight.w800, color: s.cardForeground),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Tranquilo'),
                            selected: _safety == 'safe',
                            onSelected: widget.isOwner ? (_) => setState(() => _safety = 'safe') : null,
                            selectedColor: s.primary.withOpacity(0.18),
                            labelStyle: TextStyle(
                              color: _safety == 'safe' ? s.cardForeground : s.mutedForeground,
                              fontWeight: FontWeight.w800,
                            ),
                            side: BorderSide(color: _safety == 'safe' ? s.primary : s.border),
                            backgroundColor: s.card,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Perigoso'),
                            selected: _safety == 'danger',
                            onSelected: widget.isOwner ? (_) => setState(() => _safety = 'danger') : null,
                            selectedColor: s.destructive.withOpacity(0.18),
                            labelStyle: TextStyle(
                              color: _safety == 'danger' ? s.cardForeground : s.mutedForeground,
                              fontWeight: FontWeight.w800,
                            ),
                            side: BorderSide(color: _safety == 'danger' ? s.destructive : s.border),
                            backgroundColor: s.card,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Container(
                height: 360,
                decoration: BoxDecoration(
                  color: s.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _fallbackCenter(),
                        zoom: 15,
                      ),
                      polygons: _polygons(s),
                      markers: _markers(s),
                      onMapCreated: (c) => _map = c,
                      onTap: widget.isOwner && _addingDangerPoint
                          ? (pos) async {
                        final desc = await _askDangerDescription(s);
                        if (desc == null) {
                          if (mounted) setState(() => _addingDangerPoint = false);
                          return;
                        }

                        setState(() {
                          _dangerPoints.add(_DangerPoint(pos: pos, desc: desc));
                          _addingDangerPoint = false;
                        });
                        await _save();
                      }
                          : null,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    ),

                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _addingDangerPoint ? s.destructive : s.primary,
                          foregroundColor: _addingDangerPoint ? s.destructiveForeground : s.primaryForeground,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(_addingDangerPoint ? Icons.close : Icons.warning_amber_rounded),
                        label: Text(
                          widget.isOwner
                              ? (_addingDangerPoint ? 'Toque no mapa e descreva' : 'Marcar ponto de atenção')
                              : 'Pontos de atenção',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        onPressed: widget.isOwner
                            ? () => setState(() => _addingDangerPoint = !_addingDangerPoint)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              Text(
                widget.isOwner
                    ? "Dica: marque no mapa e descreva por que é um ponto de atenção (rua escura, trânsito, cães soltos etc)."
                    : "Pontos marcados pelo dono do território.",
                style: TextStyle(color: s.mutedForeground),
              ),

              const SizedBox(height: 12),

              _card(
                s,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚡ Poderes do território',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: s.cardForeground,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Usar pontos',
                              style: TextStyle(fontWeight: FontWeight.w800, color: s.cardForeground),
                            ),
                            subtitle: Text(
                              _loadingPoints ? 'Carregando...' : 'Você tem $_myPoints pontos',
                              style: TextStyle(color: s.mutedForeground),
                            ),
                            value: _usePoints,
                            onChanged: (v) async {
                              setState(() => _usePoints = v);
                              if (v) await _loadMyPoints();
                            },
                            activeColor: s.primary,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Atualizar saldo',
                          onPressed: _loadMyPoints,
                          icon: Icon(Icons.refresh, color: s.foreground),
                        )
                      ],
                    ),

                    const SizedBox(height: 10),

                    AnimatedOpacity(
                      opacity: _usePoints ? 1 : 0.45,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_usePoints,
                        child: Column(
                          children: [
                            _powerButton(
                              s: s,
                              label: '🛡️ Proteção 24h',
                              cost: 120,
                              onTap: () async {
                                final ok = await PointsService().buyProtection(
                                  territoryId: widget.territoryId,
                                  hours: 24,
                                  cost: 120,
                                );
                                if (ok) {
                                  await _loadMyPoints();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Proteção 24h ativada ✅')),
                                    );
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 10),

                            _powerButton(
                              s: s,
                              label: '🛡️ Proteção 48h',
                              cost: 220,
                              onTap: () async {
                                final ok = await PointsService().buyProtection(
                                  territoryId: widget.territoryId,
                                  hours: 48,
                                  cost: 220,
                                );
                                if (ok) {
                                  await _loadMyPoints();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Proteção 48h ativada ✅')),
                                    );
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 10),

                            _powerButton(
                              s: s,
                              label: '🔥 Aumentar dificuldade (24h)',
                              cost: 160,
                              onTap: () async {
                                final ok = await PointsService().buyDifficultyBoost(
                                  territoryId: widget.territoryId,
                                  hours: 24,
                                  extraDifficulty: 1,
                                  cost: 160,
                                );
                                if (ok) {
                                  await _loadMyPoints();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Dificuldade aumentada ✅')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
