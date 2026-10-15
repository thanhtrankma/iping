import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/geocode_service.dart';
import '../services/location_service.dart';
import '../services/trip_analyzer.dart' show distanceBetween;
import '../theme.dart';
import '../utils/directions.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'dm_screen.dart';
import 'home_screen.dart' show BatteryPill;
import 'member_screen.dart';
import 'moderation_sheets.dart';

/// Chạm vào ghim trên bản đồ: hiện thẻ thông tin ngay tại chỗ (không chuyển trang).
Future<void> showMemberPopup(BuildContext context, {required String groupId, required MemberLocation location}) {
  final me = LocationService.instance.lastPosition.value;
  return showGlassSheet<void>(
    context,
    builder: (ctx) => MemberPopup(
      groupId: groupId,
      location: location,
      myUid: FirebaseAuth.instance.currentUser?.uid,
      myLat: me?.latitude,
      myLng: me?.longitude,
    ),
  );
}

class MemberPopup extends StatelessWidget {
  const MemberPopup({
    super.key,
    required this.groupId,
    required this.location,
    required this.myUid,
    this.myLat,
    this.myLng,
  });
  final String groupId;
  final MemberLocation location;
  final String? myUid;
  final double? myLat;
  final double? myLng;

  @override
  Widget build(BuildContext context) {
    final l = location;
    final isMe = l.uid == myUid;
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    final distance = (isMe || myLat == null || myLng == null) ? null : distanceBetween(myLat!, myLng!, l.lat, l.lng);
    final moving = l.speed != null && l.speed! > 2;
    final nav = Navigator.of(context);

    void open(Widget page) {
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => page));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MemberAvatar(uid: l.uid, name: l.name, radius: 28, dimmed: !l.sharing, online: isFresh(l.updatedAt)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              color: AppColors.brand.withValues(alpha: 0.12),
                            ),
                            child: const Text('Bạn',
                                style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 12.5)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        l.sharing ? timeAgo(l.updatedAt) : 'Đã tắt chia sẻ · ${timeAgo(l.updatedAt)}',
                        if (distance != null) 'cách ${distanceLabel(distance).replaceAll('.', ',')}',
                        if (moving) '${(l.speed! * 3.6).round()} km/h',
                      ].join(' · '),
                      style: TextStyle(color: secondary, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              if (l.battery != null) BatteryPill(level: l.battery!),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_rounded, size: 18, color: secondary),
              const SizedBox(width: 6),
              Expanded(child: AddressText(l.lat, l.lng, style: TextStyle(fontSize: 15, color: scheme.onSurface))),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GlassTile(
                  icon: Icons.person_rounded,
                  color: AppColors.brand,
                  label: 'Chi tiết',
                  onTap: () => open(MemberScreen(groupId: groupId, uid: l.uid)),
                ),
              ),
              if (!isMe) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: GlassTile(
                    icon: Icons.turn_right_rounded,
                    color: AppColors.online,
                    label: 'Chỉ đường',
                    onTap: () => openDirections(context, l.lat, l.lng),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassTile(
                    icon: Icons.chat_bubble_rounded,
                    color: AppColors.indigo,
                    label: 'Nhắn tin',
                    onTap: () => open(DmScreen(groupId: groupId, otherUid: l.uid, otherName: l.name)),
                  ),
                ),
              ],
            ],
          ),
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: secondary, visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: const Text('Báo cáo / Chặn', style: TextStyle(fontSize: 13.5)),
                  onPressed: () {
                    final outer = nav.context;
                    nav.pop();
                    showUserModerationSheet(outer, uid: l.uid, name: l.name, groupId: groupId);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
