# IPing

App chia sẻ vị trí cho gia đình và bạn bè, có tính năng tương tự iSharing. Viết bằng Flutter, backend là Firebase.

## Tính năng

Giao diện kiểu **liquid glass**: bản đồ vệ tinh tràn màn hình, nút và bảng thông tin dạng kính mờ (`lib/widgets/glass.dart`). Các tính năng trả phí của iSharing đều có sẵn và miễn phí:

| Tính năng | Cách hoạt động |
|---|---|
| Bản đồ thời gian thực | Mỗi thành viên ghi vị trí vào `groups/{id}/locations/{uid}`, kèm % pin, tốc độ, thời điểm cập nhật. Có hai kiểu bản đồ: vệ tinh (Esri) và thường (OpenStreetMap). |
| Địa chỉ cụ thể | Đổi toạ độ ra địa chỉ bằng geocoder của hệ điều hành, không cần API key (`geocode_service.dart`). |
| Lịch sử vị trí 30 ngày | Lưu điểm vào `locations/{uid}/points` khi đi được ≥ 40 m hoặc mỗi 5 phút. Firestore TTL tự xoá điểm cũ hơn 30 ngày. |
| Dòng thời gian & chuyến đi | `trip_analyzer.dart` chia lịch sử thành các lần *dừng* và *chuyến đi* (quãng đường, thời gian, tốc độ). Có test trong `test/trip_analyzer_test.dart`. |
| Báo cáo lái xe | Chuyến có tốc độ trung bình > 20 km/h được tính là lái xe. Ghi nhận số lần chạy > 80 km/h, phanh gấp (giảm tốc ≥ 3.5 m/s²) và chấm điểm an toàn 0–100. |
| Ping nhanh | ❤️ Yêu nhé, 👻 Ú òa, 💩 Chọc, 📍 Tới rồi, 📞 Gọi lại, 🏠 Về nhà chưa: gửi push riêng cho một người (`onPing`). |
| Nhóm & mời | Tạo nhóm, mời bằng mã 6 ký tự, rời nhóm. Chạy qua Cloud Functions. |
| Đến/rời địa điểm | Phát hiện ngay trên điện thoại, có vùng đệm 30 m. Có lịch sử ra/vào riêng cho từng thành viên. |
| SOS, chat nhóm | Push khẩn cấp kèm toạ độ, chat realtime. |
| Quyền riêng tư | Chia sẻ vị trí tắt mặc định. Firestore rules chỉ cho thành viên cùng nhóm đọc dữ liệu của nhau. |

## Cấu trúc

```
lib/
  main.dart, app.dart            khởi động Firebase, cổng đăng nhập
  models/models.dart             Group, MemberLocation, Place, GroupEvent, ChatMessage
  services/                      auth, group, location, geofence, notification,
                                 geocode, settings, trip_analyzer
  screens/                       home (bản đồ + danh sách), member, history,
                                 driving, menu, groups, chat/places/activity
  widgets/                       glass (liquid glass), map_view, common
functions/index.js               createGroup, joinGroup, leaveGroup, push (events, chat, ping)
firestore.rules                  phân quyền
scripts/setup_platforms.sh       tạo ios/android và thêm quyền
```

## Cài đặt

**1. Cài công cụ** (máy bạn hiện chưa có Flutter):

```bash
brew install --cask flutter
```

```bash
npm install -g firebase-tools && dart pub global activate flutterfire_cli
```

Cần cài thêm Xcode (cho iOS) và/hoặc Android Studio.

**2. Tạo thư mục nền tảng và thêm quyền:**

```bash
chmod +x scripts/setup_platforms.sh && ./scripts/setup_platforms.sh
```

**3. Tạo dự án Firebase** tại console.firebase.google.com, rồi:
- Authentication → bật **Email/Password**
- Firestore Database → tạo database
- Nâng lên gói **Blaze** (bắt buộc để chạy Cloud Functions; dùng ít thì gần như miễn phí)
- Push trên iOS: Project settings → Cloud Messaging → tải lên **APNs key** (.p8). Trong Xcode, bật capability *Push Notifications* và *Background Modes*.

**4. Kết nối app với Firebase** (lệnh này ghi đè file tạm `lib/firebase_options.dart`):

```bash
firebase login && flutterfire configure
```

**5. Deploy rules và functions:**

```bash
cd functions && npm install && cd .. && firebase deploy --only firestore,functions
```

**6. Chạy app:**

```bash
flutter pub get && flutter run
```

## Lưu ý

- **Region:** Functions chạy ở `asia-southeast1` (Singapore). Nếu đổi thì sửa cả `functions/index.js` lẫn `lib/services/group_service.dart`.
- **Bản đồ:** ảnh vệ tinh Esri World Imagery và tile OpenStreetMap chỉ phù hợp để phát triển. Khi phát hành cần giấy phép (ArcGIS, MapTiler, Mapbox hoặc Google Maps). Sửa trong `widgets/map_view.dart` và `osmTileLayer()`.
- **Functions** chạy Node.js 22. Node 20 bị Google ngừng hỗ trợ từ 30/10/2026.
- **Vị trí nền:** để nhận thông báo đến/rời khi app đóng, người dùng phải chọn quyền vị trí *Luôn luôn* trong Cài đặt. Apple và Google Play đều yêu cầu giải thích rõ lý do khi xin quyền này lúc nộp app.
- **iOS Simulator** không nhận được push. Hãy test push trên máy thật.
