import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  static const _orange = Color(0xFFFF6D00);

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

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
    // ✅ inicializa só uma vez (para não “desfazer” o que você escolhe na UI)
    if (_didInitFromDoc) return;
    _didInitFromDoc = true;

    final customName = (data['customName'] ?? '').toString().trim();
    _nameCtrl.text = customName;

    final d = data['difficulty'];
    if (d is num) {
      _difficulty = d.toInt().clamp(1, 5);
    } else {
      _difficulty = 1;
    }

    final s = (data['safety'] ?? 'safe').toString();
    _safety = (s == 'danger' || s == 'safe') ? s : 'safe';

    // Polígono
    final pts = (data['points'] as List?) ?? const [];
    _polygon = pts
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(_toLatLng)
        .whereType<LatLng>()
        .toList();

    // Pontos perigosos com descrição
    _dangerPoints.clear();
    final dp = (data['dangerPoints'] as List?) ?? const [];
    for (final item in dp) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final ll = _toLatLng(m);
        if (ll != null) {
          _dangerPoints.add(
            _DangerPoint(
              pos: ll,
              desc: (m['desc'] ?? '').toString().trim(),
            ),
          );
        }
      }
    }
  }

  Future<void> _save() async {
    if (!widget.isOwner) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(widget.territoryId)
          .set({
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

  Set<Polygon> _polygons() {
    if (_polygon.length < 3) return {};
    return {
      Polygon(
        polygonId: const PolygonId('territory'),
        points: _polygon,
        strokeWidth: 2,
        strokeColor: _orange,
        fillColor: _orange.withOpacity(0.12),
      )
    };
  }

  Future<String?> _askDangerDescription({String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Descrever ponto de atenção',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 120,
              decoration: const InputDecoration(
                hintText: 'Ex: Rua escura / cruzamento perigoso / cães soltos...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
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

  Set<Marker> _markers() {
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
              // editar/remover
              final action = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit),
                        title: const Text('Editar descrição'),
                        onTap: () => Navigator.pop(ctx, 'edit'),
                      ),
                      ListTile(
                        leading:
                        const Icon(Icons.delete, color: Colors.red),
                        title: const Text('Remover ponto',
                            style: TextStyle(color: Colors.red)),
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
                final desc =
                await _askDangerDescription(initial: p.desc);
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

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance
        .collection('territorios')
        .doc(widget.territoryId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do território'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
            )
        ],
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? {};
          _initFromDocOnce(data); // ✅ não reseta _safety/_difficulty toda hora

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personalize este território',
                      style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _nameCtrl,
                      enabled: widget.isOwner,
                      decoration: const InputDecoration(
                        labelText: 'Nome do território',
                        hintText: 'Ex: Pista do Aterro',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ✅ SLIDER DIFICULDADE
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Dificuldade',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          _difficultyLabel(_difficulty),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _orange,
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
                      onChanged: widget.isOwner
                          ? (v) => setState(() => _difficulty = v.round())
                          : null,
                      activeColor: _orange,
                    ),

                    const SizedBox(height: 6),

                    // ✅ SAFETY (agora funciona)
                    const Text(
                      'Segurança do local',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Tranquilo'),
                            selected: _safety == 'safe',
                            onSelected: widget.isOwner
                                ? (_) => setState(() => _safety = 'safe')
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Perigoso'),
                            selected: _safety == 'danger',
                            onSelected: widget.isOwner
                                ? (_) => setState(() => _safety = 'danger')
                                : null,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _fallbackCenter(),
                        zoom: 15,
                      ),
                      polygons: _polygons(),
                      markers: _markers(),
                      onMapCreated: (c) => _map = c,
                      onTap: widget.isOwner && _addingDangerPoint
                          ? (pos) async {
                        // ✅ pede descrição antes de salvar
                        final desc = await _askDangerDescription();
                        if (desc == null) {
                          // cancelou
                          if (mounted) {
                            setState(() => _addingDangerPoint = false);
                          }
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
                          backgroundColor:
                          _addingDangerPoint ? Colors.red : _orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(_addingDangerPoint
                            ? Icons.close
                            : Icons.warning_amber_rounded),
                        label: Text(
                          widget.isOwner
                              ? (_addingDangerPoint
                              ? 'Toque no mapa e descreva'
                              : 'Marcar ponto de atenção')
                              : 'Pontos de atenção',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        onPressed: widget.isOwner
                            ? () => setState(
                                () => _addingDangerPoint = !_addingDangerPoint)
                            : null,
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 10),
              Text(
                widget.isOwner
                    ? "Dica: marque no mapa e descreva por que é um ponto de atenção (rua escura, trânsito, cães soltos etc)."
                    : "Pontos marcados pelo dono do território.",
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          );
        },
      ),
    );
  }
}
