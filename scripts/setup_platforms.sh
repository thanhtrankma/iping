#!/usr/bin/env bash
# Tạo thư mục ios/ android/ và thêm quyền vị trí, chạy nền, thông báo.
# Chạy từ thư mục gốc dự án: ./scripts/setup_platforms.sh
set -euo pipefail

ORG="${ORG:-com.iping}"

if [ ! -d ios ] || [ ! -d android ]; then
  flutter create --org "$ORG" --project-name gan_nhau --platforms ios,android .
fi

# ---------- iOS ----------
PLIST=ios/Runner/Info.plist
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" 2>/dev/null || true; }

pb "Add :CFBundleDisplayName string IPing"
pb "Set :CFBundleDisplayName IPing"
pb "Add :NSLocationWhenInUseUsageDescription string IPing dùng vị trí để hiển thị bạn trên bản đồ cho các thành viên trong nhóm."
pb "Add :NSLocationAlwaysAndWhenInUseUsageDescription string Cho phép luôn truy cập vị trí để nhóm nhận thông báo khi bạn đến hoặc rời địa điểm, kể cả khi ứng dụng đóng."
pb "Add :UIBackgroundModes array"
for mode in location fetch remote-notification; do
  if ! /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" | grep -q "$mode"; then
    pb "Add :UIBackgroundModes: string $mode"
  fi
done

# Firebase iOS SDK cần iOS 13+.
if [ -f ios/Podfile ]; then
  sed -i '' "s/^# platform :ios, .*/platform :ios, '13.0'/" ios/Podfile
fi

# ---------- Android ----------
MANIFEST=android/app/src/main/AndroidManifest.xml
add_perm() {
  grep -q "$1" "$MANIFEST" || perl -0pi -e "s|(<application)|<uses-permission android:name=\"$1\"/>\n    \$1|" "$MANIFEST"
}
for p in \
  android.permission.INTERNET \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION \
  android.permission.ACCESS_BACKGROUND_LOCATION \
  android.permission.FOREGROUND_SERVICE \
  android.permission.FOREGROUND_SERVICE_LOCATION \
  android.permission.POST_NOTIFICATIONS \
  android.permission.WAKE_LOCK; do
  add_perm "$p"
done
perl -pi -e 's|android:label="gan_nhau"|android:label="IPing"|' "$MANIFEST"

# Firebase cần minSdk 23.
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 23/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 23/' "$f"
done

echo "Xong. Tiếp theo: flutterfire configure (xem README)."
