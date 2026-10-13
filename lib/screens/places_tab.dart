import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PlacesTab extends StatefulWidget {
  const PlacesTab({super.key, required this.group});
  final Group group;

  @override
  State<PlacesTab> createState() => _PlacesTabState();
}

class _PlacesTabState extends State<PlacesTab> {
  late final Stream<List<Place>> _places = GroupService.instance.places(widget.group.id);

  Future<void> _delete(Place p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xoá "${p.name}"?'),
        content: const Text('Cả nhóm sẽ không còn nhận thông báo đến/rời địa điểm này.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok == true) await GroupService.instance.deletePlace(widget.group.id, p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-place',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AddPlaceScreen(groupId: widget.group.id),
        )),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Thêm địa điểm'),
      ),
      body: StreamBuilder<List<Place>>(
        stream: _places,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final places = snap.data!;
          if (places.isEmpty) {
            return const EmptyState(
              icon: Icons.add_location_alt_rounded,
              title: 'Chưa có địa điểm nào',
              text: 'Thêm Nhà, Trường, Công ty...\nNhóm sẽ nhận thông báo khi ai đó đến hoặc rời đi.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            itemCount: places.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final p = places[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_iconFor(p.name), color: AppColors.brand),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text('Bán kính ${p.radius.round()} m · Báo khi đến/rời',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Xoá',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(p),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('nhà') || n.contains('home')) return Icons.home_rounded;
  if (n.contains('trường') || n.contains('học')) return Icons.school_rounded;
  if (n.contains('công ty') || n.contains('văn phòng') || n.contains('làm')) return Icons.work_rounded;
  if (n.contains('gym') || n.contains('tập')) return Icons.fitness_center_rounded;
  return Icons.place_rounded;
}

class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key, required this.groupId});
  final String groupId;

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _name = TextEditingController();
  final _map = MapController();
  late LatLng _point;
  double _radius = 200;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = LocationService.instance.lastPosition.value;
    _point = p != null ? LatLng(p.latitude, p.longitude) : defaultCenter;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Hãy đặt tên cho địa điểm');
      return;
    }
    setState(() => _saving = true);
    await GroupService.instance.addPlace(widget.groupId,
        name: name, lat: _point.latitude, lng: _point.longitude, radius: _radius);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thêm địa điểm'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              onPressed: _saving ? null : _save,
              child: const Text('Lưu'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _point,
                    initialZoom: 16,
                    onTap: (_, p) => setState(() => _point = p),
                  ),
                  children: [
                    osmTileLayer(),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: _point,
                        radius: _radius,
                        useRadiusInMeter: true,
                        color: AppColors.brand.withValues(alpha: 0.18),
                        borderColor: AppColors.brand,
                        borderStrokeWidth: 2,
                      ),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: _point,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_pin, size: 44, color: AppColors.brand),
                      ),
                    ]),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    shadowColor: Colors.black26,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: AppColors.brand),
                        SizedBox(width: 8),
                        Text('Chạm vào bản đồ để chọn vị trí'),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Tên địa điểm (vd: Nhà, Trường học)',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Bán kính', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${_radius.round()} m',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand)),
                    ],
                  ),
                  Slider(
                    value: _radius,
                    min: 100,
                    max: 1000,
                    divisions: 18,
                    label: '${_radius.round()} m',
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
