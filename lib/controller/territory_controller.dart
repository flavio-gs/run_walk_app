import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:run_walk_app/enums/territory_mode.dart';

class TerritoryController {
  TerritoryController({required this.currentUserId});

  final String currentUserId;
  final Set<Polygon> territoryPolygons = {};
  final List<_Territory> territories = [];

  static const double _fillOpacity = 0.22;

  // ✅ sua cor fixa
  static const Color kMyTerritoryColor = Color(0xFF00C853); // verde

// ✅ paleta para outros jogadores (repete se acabar)
  static const List<Color> kEnemyPalette = [
    Colors.deepOrangeAccent,
    Colors.cyanAccent,
    Colors.purpleAccent,
    Colors.amberAccent,
    Colors.pinkAccent,
    Colors.lightBlueAccent,
    Colors.limeAccent,
    Colors.redAccent,
  ];

// ✅ cache de cores por dono (mesmo dono => mesma cor sempre)
  final Map<String, Color> _ownerColors = {};

// ✅ atribui cor estável para cada ownerId
  Color _colorForOwner(String ownerId) {
    if (ownerId.isEmpty) return Colors.white24;

    // você sempre na mesma cor
    final myId = FirebaseAuth.instance.currentUser?.uid;
    if (myId != null && ownerId == myId) return kMyTerritoryColor;

    // já tem cor definida? devolve
    final existing = _ownerColors[ownerId];
    if (existing != null) return existing;

    // cria uma nova cor de forma estável
    // (usa hash do ownerId pra pegar índice fixo na paleta)
    final idx = ownerId.hashCode.abs() % kEnemyPalette.length;
    final c = kEnemyPalette[idx];

    _ownerColors[ownerId] = c;
    return c;
  }




  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  MapTerritoryMode mode = MapTerritoryMode.global;

  void dispose() {
    _sub?.cancel();
  }

  Future<void> setMode(
      MapTerritoryMode newMode, {
        required VoidCallback onUpdate,
        VoidCallback? onFree,
        VoidCallback? onGlobal,
      }) async {
    if (mode == newMode) return;
    mode = newMode;

    if (mode == MapTerritoryMode.livre) {
      await _sub?.cancel();
      territories.clear();
      territoryPolygons.clear();

      onFree?.call();   // ✅ pede pra tela limpar polyTerritoryModeTogglelines/markers/etc
      onUpdate();
      return;
    }

    onGlobal?.call();   // ✅ pede pra tela recarregar overlays se quiser
    _listenTerritories(onUpdate);
  }


  void _listenTerritories(VoidCallback onUpdate) async {
    await _sub?.cancel();

    _sub = FirebaseFirestore.instance
        .collection('territorios')
        .snapshots()
        .listen((snap) {
      territories
        ..clear()
        ..addAll(snap.docs.map((d) {
          final data = d.data();
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
          );
        }));

      territoryPolygons
        ..clear()
        ..addAll(
          territories.map((t) {
            final base = _colorForOwner(t.ownerId);

            return Polygon(
              polygonId: PolygonId('territorio_${t.id}'),
              points: t.points,
              strokeColor: base.withOpacity(0.85),
              strokeWidth: 2,
              fillColor: base.withOpacity(_fillOpacity),
            );
          }),
        );

      onUpdate();
    });
  }


}

/// modelo interno
class _Territory {
  final String id;
  final String ownerId;
  final List<LatLng> points;

  const _Territory({
    required this.id,
    required this.ownerId,
    required this.points,
  });
}
