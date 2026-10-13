import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

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
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok == true) await GroupService.instance.deletePlace(widget.group.id, p.id);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _FloatingAction(
        icon: Icons.add_location_alt_rounded,
        label: 'Thêm địa điểm',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AddPlaceScreen(groupId: widget.group.id),
        )),
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
          final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
          return ListView(
            padding: EdgeInsets.only(top: mq.padding.top + 12, bottom: mq.padding.bottom + 110),
            children: [
              GlassSection(
                header: 'Địa điểm của nhóm',
                footer: 'Cả nhóm nhận thông báo khi có người đến hoặc rời các địa điểm này.',
                dividerIndent: 66,
                children: [
                  for (final p in places)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                      child: Row(
                        children: [
                          GlassIconBadge(icon: _iconFor(p.name), color: _colorFor(p.name), size: 36),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: -0.2)),
                                const SizedBox(height: 2),
                                Text('Bán kính ${p.radius.round()} m · Báo khi đến/rời',
                                    style: TextStyle(color: secondary, fontSize: 13)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Xoá',
                            icon: Icon(Icons.delete_outline_rounded, color: secondary),
                            onPressed: () => _delete(p),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Nút hành động chính nổi dạng viên thuốc kính có màu thương hiệu.
class _FloatingAction extends StatelessWidget {
  const _FloatingAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      tint: AppColors.brand,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

Color _colorFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('nhà') || n.contains('home')) return AppColors.orange;
  if (n.contains('trường') || n.contains('học')) return AppColors.indigo;
  if (n.contains('công ty') || n.contains('văn phòng') || n.contains('làm')) return AppColors.teal;
  if (n.contains('gym') || n.contains('tập')) return AppColors.pink;
  return AppColors.brand;
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
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
          ),
          // Thanh trên nổi: nút quay lại + gợi ý.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  GlassButton(
                    size: 46,
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Quay lại',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Glass(
                      capsule: true,
                      opacity: 0.65,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: AppColors.brand),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text('Chạm vào bản đồ để chọn vị trí',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bảng nổi phía dưới: tên, bán kính và nút lưu.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Glass(
                  radius: 34,
                  opacity: 0.78,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 12),
                          child: Text('Thêm địa điểm',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ),
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Tên địa điểm (vd: Nhà, Trường học)',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              const Text('Bán kính', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: ShapeDecoration(
                                  shape: const StadiumBorder(),
                                  color: AppColors.brand.withValues(alpha: 0.12),
                                ),
                                child: Text('${_radius.round()} m',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                              ),
                            ],
                          ),
                        ),
                        Slider(
                          value: _radius,
                          min: 100,
                          max: 1000,
                          divisions: 18,
                          label: '${_radius.round()} m',
                          onChanged: (v) => setState(() => _radius = v),
                        ),
                        const SizedBox(height: 4),
                        FilledButton.icon(
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded),
                          label: const Text('Lưu'),
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
