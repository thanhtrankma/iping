# QA: so sánh IPing với iSharing

Mục đích: kiểm tra IPing đã có đủ chức năng chính của iSharing chưa, và từng chức năng có chạy đúng không.

Cách dùng:
1. Đọc **Phần A** để biết tính năng nào đã có, còn thiếu hoặc mới làm một phần.
2. Chạy các ca test ở **Phần B**. Đánh `[x]` khi đạt; nếu lỗi thì ghi vào cột *Ghi chú* hoặc **Phần C**.

Ký hiệu: ✅ đã có · ⚠️ có một phần · ❌ chưa có · ➕ IPing có, iSharing không có

---

## Phần A. Bảng so sánh tính năng

Cột *IPing* được điền bằng cách đọc code (commit `c6f1e18`), chưa chạy thật. Danh sách tính năng của iSharing lấy theo bản phổ biến gần đây; trước khi chốt nên mở app iSharing ra đối chiếu lại.

| # | Tính năng của iSharing | IPing | Nằm ở đâu / còn thiếu gì |
|---|---|---|---|
| 1 | Bản đồ vị trí thời gian thực của cả nhóm | ✅ | `home_screen.dart`, `location_service.dart` |
| 2 | Hiện địa chỉ cụ thể | ✅ | `geocode_service.dart` |
| 3 | Hiện % pin của thành viên | ✅ | `battery_plus` → field `battery` |
| 4 | **Cảnh báo pin yếu** (báo cả nhóm khi pin < 15–20%) | ✅ | `battery_alert_service.dart` (≤ 15%), push qua `onGroupEvent` |
| 5 | Tốc độ hiện tại | ✅ | `member_screen.dart` |
| 6 | Lịch sử vị trí (bản trả phí lưu 30 ngày) | ✅ | `history_screen.dart`, TTL 30 ngày |
| 7 | Dòng thời gian dừng / di chuyển | ✅ | `trip_analyzer.dart` |
| 8 | Báo cáo lái xe, cảnh báo chạy quá tốc độ | ✅ | Có báo cáo + điểm an toàn, và push ngay khi chạy > 80 km/h: `SpeedingTracker` (2 lần đo liên tiếp, cooldown 10 phút) → event `speeding` (rules kiểm tra speed 81–400), khoá cảnh báo `speeding` |
| 9 | Phát hiện va chạm (crash detection) | ⚠️ | **Beta**, mặc định tắt (Menu → "Phát hiện va chạm (beta)"). `CrashDetector`: gia tốc > 4g trong 30 giây sau khi đi > 25 km/h (sensors_plus) → màn đếm ngược 30 giây ("Tôi ổn, huỷ" / "Gửi SOS ngay") → SOS tới các nhóm không tạm ẩn. Chỉ chạy khi app còn hoạt động; chưa thử va chạm thật, cần hiệu chỉnh ngưỡng trên máy thật |
| 10 | Đến/rời địa điểm (geofence) + push | ✅ | `geofence_service.dart`, `onGroupEvent` |
| 11 | Lịch sử ra/vào địa điểm theo từng người | ✅ | `PlaceHistoryScreen` trong `driving_screen.dart` |
| 12 | Nút SOS / panic (push khẩn kèm vị trí) | ✅ | `GroupActions.sos` |
| 13 | SOS **hú còi** trên máy người nhận | ✅ | Android: kênh `sos` (MainActivity) với tiếng còi `res/raw/sos_siren`, usage ALARM. iOS: `sos_siren.caf` trong bundle. Push SOS / quá giờ Về an toàn dùng âm này; app đang mở thì `SosAlarmService` hú còi (tối đa 30 giây, nút "Tắt còi"). Còi tự tổng hợp, không dùng file có bản quyền |
| 14 | Chat nhóm | ✅ | `chat_tab.dart` |
| 15 | Chat 1-1 | ✅ | Màn thành viên → "Nhắn tin" → `DmScreen` (dùng lại giao diện chat). `dms/{uidA_uidB}` + `messages`; rules: chỉ 2 người trong cuộc, tạo được khi cùng nhóm. Push `onDmMessage` (khoá cảnh báo `message`), bấm push mở đúng cuộc trò chuyện. Chưa thử trên máy (cần 2 tài khoản) |
| 16 | Tin nhắn nhanh / ping | ✅ | 6 loại ping, `onPing` |
| 17 | **Yêu cầu cập nhật vị trí** (đánh thức máy người kia) | ✅ | Ping `locate` + `locate_background.dart` (BUG-01 đã sửa) |
| 18 | Tạo nhóm, nhiều nhóm, chuyển nhóm | ✅ | `groups_screen.dart`, `pickGroup` |
| 19 | Mời bằng mã | ✅ | Mã 6 ký tự |
| 20 | Mời bằng link / SMS / share sheet | ✅ | Bảng mời có QR (`qr_flutter`), mã 6 ký tự, sao chép và share sheet (`share_plus`). Link `iping://join?code=…` (`app_links`) mở hộp thoại tham gia; ô nhập mã nhận cả link và có quét QR (`mobile_scanner`). Đã thử trên emulator |
| 21 | Chủ nhóm xoá thành viên | ✅ | `removeMember` / `unblockMember`, `member_admin.dart`. Có thêm chặn thành viên |
| 22 | Đổi tên nhóm | ✅ | Chủ nhóm: Quản lý nhóm → ⋯ → "Đổi tên nhóm" (`GroupActions.rename`, 1–50 ký tự, khớp rules) |
| 23 | Bật/tắt chia sẻ vị trí (ẩn vị trí) | ✅ | Nút "Bật chia sẻ"; mặc định tắt |
| 24 | Tạm ẩn vị trí trong một khoảng thời gian | ✅ | `privacy_screen.dart`: ẩn theo từng nhóm 1h / 8h / tới sáng / vô hạn |
| 25 | Chỉ đường tới thành viên / mở Google Maps | ✅ | Màn thành viên → ô khoảng cách → mở chỉ đường: Apple Maps trên iOS, Google Maps trên Android (`url_launcher`, `utils/directions.dart`) |
| 26 | Đăng nhập Email | ✅ | |
| 27 | Đăng nhập Google / Apple / số điện thoại | ✅ | Google, số điện thoại (OTP) và Sign in with Apple (chỉ hiện trên iOS, `AppleAuthProvider`, entitlement `com.apple.developer.applesignin`). Apple cần ký bằng tài khoản Apple Developer khi build lên máy/App Store |
| 28 | Quên mật khẩu | ✅ | Link "Quên mật khẩu?" → `sendPasswordResetEmail` (`account_dialogs.dart`) |
| 29 | Xoá tài khoản | ✅ | Hồ sơ → Xoá tài khoản (gõ XOÁ để xác nhận) → callable `deleteAccount`: rời mọi nhóm, xoá users/{uid}, ảnh Storage, tài khoản Auth |
| 30 | Ảnh đại diện, tên hiển thị | ✅ | `profile_screen.dart` |
| 31 | Bấm vào push thì mở đúng màn hình | ✅ | `push_router.dart`: `onMessageOpenedApp` + `getInitialMessage`, điều hướng theo `groupId`/`type` (thành viên, chat, khoảnh khắc, meetup, Về an toàn) |
| 32 | Cài đặt bật/tắt từng loại thông báo | ✅ | `alert_settings_screen.dart` + lọc phía server `alert_prefs.js`. Chưa tắt được `checkin` và `locate` |
| 33 | Báo khi thành viên mất kết nối hoặc tắt định vị | ✅ | Scheduled `checkStaleLocations` (15 phút): đang chia sẻ mà `lastSeenAt` > 4 giờ (client heartbeat 15 phút, kể cả đứng yên) → event `offline` + push "chưa thấy hoạt động" (một lần mỗi đợt). Client gửi `location_off` khi GPS tắt / quyền bị thu hồi. Khoá cảnh báo `offline` |
| 34 | Vệ tinh / bản đồ thường | ✅ | `toggleMapStyle` |
| 35 | Khoảnh khắc (ảnh + vị trí, hết hạn sau 24h) | ➕ | `moments_screen.dart` |
| 36 | Meetup / điểm hẹn | ➕ | `meetup_screen.dart` |
| 37 | Khám phá (bản đồ sương mù, % khu vực, bảng xếp hạng) | ➕ | `explore_screen.dart` |
| 38 | Về an toàn (hẹn giờ tới nơi, báo nhóm khi quá giờ) | ➕ | `safe_trip_screen.dart`, function `checkSafeTrips` |
| 39 | Check-in kèm địa chỉ | ➕ | `all_friends_actions.dart` |
| 40 | Xem Tất cả bạn bè (gộp mọi nhóm) | ➕ | `all_friends_service.dart` |

**Tóm tắt (cập nhật 14/10, HEAD `90e74e0`):** 40 dòng gồm 33 ✅, 1 ⚠️ (phát hiện va chạm, bản beta), 0 ❌, 6 ➕. Cả 16 bug ở Phần C đã sửa (mới kiểm tra bằng đọc code và test tự động).

Nên làm trước, vì ảnh hưởng tới việc lên store hoặc là tính năng iSharing hay được nhắc tới:
- Xoá tài khoản (#29), quên mật khẩu (#28)
- Bấm push mở đúng màn hình (#31)
- Yêu cầu cập nhật vị trí (#17), cảnh báo pin yếu (#4)
- Đổi tên nhóm (#22): rules đã có, chỉ cần thêm giao diện

---

## Phần B. Ca test

### Chuẩn bị
- **3 tài khoản**: A (chủ nhóm), B, C. Có ít nhất **2 máy thật**, vì push và định vị nền không test được trên Simulator.
- Đã deploy rules và functions: `firebase deploy --only firestore,functions,storage`.
- Ghi lại phiên bản app, OS và model máy vào Phần C.

### B1. Đăng nhập & tài khoản

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| AU-01 | Đăng ký bằng email mới, mật khẩu ≥ 6 ký tự | Vào được màn chính "Bắt đầu với IPing" | [ ] | |
| AU-02 | Đăng ký với email đã có | Hiện lỗi dễ hiểu, không bị crash | [ ] | |
| AU-03 | Đăng nhập sai mật khẩu | Hiện lỗi, vẫn ở màn đăng nhập | [ ] | |
| AU-04 | Kill app rồi mở lại | Vẫn đăng nhập, mở đúng nhóm đã chọn lần trước | [ ] | |
| AU-05 | Menu → Đăng xuất | Về màn đăng nhập; máy này không nhận push của tài khoản cũ nữa | [ ] | |
| AU-06 | Hồ sơ → đổi tên hiển thị | Tên mới hiện trên bản đồ, danh sách và chat của máy khác | [ ] | |
| AU-07 | Hồ sơ → chụp ảnh / chọn ảnh từ thư viện | Avatar cập nhật trên marker ở cả 2 máy | [ ] | |
| AU-08 | Hồ sơ → Xoá ảnh đại diện | Trở về avatar chữ cái đầu | [ ] | |
| AU-09 | Quên mật khẩu | *Chưa có (#28)*: ghi FAIL | [ ] | |
| AU-10 | Xoá tài khoản | *Chưa có (#29)*: ghi FAIL | [ ] | |

### B2. Nhóm & lời mời

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| GR-01 | A tạo nhóm "Gia đình" | Nhóm được tạo và chọn sẵn, A là thành viên duy nhất | [ ] | |
| GR-02 | A bấm Mời → Sao chép mã | Hiện mã 6 ký tự, sao chép được | [ ] | |
| GR-03 | B nhập mã đúng (thử cả chữ thường) | B vào nhóm; A nhận push "B đã tham gia nhóm" | [ ] | |
| GR-04 | B nhập mã sai hoặc không tồn tại | Hiện lỗi, không vào nhóm | [ ] | |
| GR-05 | B nhập lại mã của nhóm đã ở trong đó | Không bị nhân đôi thành viên | [ ] | |
| GR-06 | A tạo thêm nhóm thứ 2, chuyển qua lại giữa 2 nhóm | Bản đồ, danh sách và chat đổi theo nhóm đang chọn | [ ] | |
| GR-07 | C rời nhóm | C không còn thấy nhóm; A và B không còn thấy C | [ ] | |
| GR-08 | Chủ nhóm A rời nhóm khi còn thành viên khác | Nhóm vẫn hoạt động, quyền chủ nhóm được xử lý hợp lý | [ ] | |
| GR-09 | Thành viên cuối cùng rời nhóm | Nhóm bị xoá, không còn dữ liệu rác | [ ] | |
| GR-10 | Đổi tên nhóm / xoá thành viên | *Chưa có giao diện (#21, #22)* | [ ] | |

### B3. Chia sẻ vị trí & bản đồ

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| LO-01 | Đăng nhập lần đầu | Chia sẻ **tắt** mặc định, có nút "Bật chia sẻ" | [ ] | |
| LO-02 | Bật chia sẻ → cấp quyền "Khi dùng app" | Marker của mình hiện trên máy kia trong ~10 giây | [ ] | |
| LO-03 | Từ chối quyền vị trí | App không crash, có hướng dẫn mở Cài đặt | [ ] | |
| LO-04 | B đi bộ hoặc chạy xe ~200 m | Marker của B trên máy A di chuyển theo | [ ] | |
| LO-05 | Danh sách thành viên | Có địa chỉ, "x phút trước", % pin đúng với máy thật | [ ] | |
| LO-06 | B ở trong địa điểm đã lưu | Dòng của B ghi "Ở <tên địa điểm>" | [ ] | |
| LO-07 | B tắt chia sẻ | Máy A hiện "Đã tắt chia sẻ · …", marker mờ đi | [ ] | |
| LO-08 | Cấp quyền "Luôn luôn", khoá màn hình 15 phút rồi di chuyển | Vị trí vẫn cập nhật khi chạy nền. Android có thông báo foreground, iOS có chỉ báo màu xanh | [ ] | |
| LO-09 | Kill hẳn app rồi di chuyển | Ghi lại hành vi thực tế. iSharing vẫn cập nhật trong trường hợp này | [ ] | |
| LO-10 | Nút đổi kiểu bản đồ | Đổi giữa vệ tinh và bản đồ thường; giữ lựa chọn sau khi khởi động lại | [ ] | |
| LO-11 | Nút "Vị trí của tôi" | Bản đồ về vị trí của mình | [ ] | |
| LO-12 | Bấm vào một thành viên | Mở màn thành viên: địa chỉ, tốc độ, khoảng cách tới mình | [ ] | |
| LO-13 | Bật chế độ máy bay 5 phút rồi tắt | App tự kết nối lại, vị trí tiếp tục cập nhật | [ ] | |
| LO-14 | Pin máy B < 20% | *Chưa có cảnh báo pin yếu (#4)* | [ ] | |
| LO-15 | A yêu cầu B cập nhật vị trí | *Chưa có (#17)* | [ ] | |

### B4. Lịch sử, chuyến đi, lái xe

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| HI-01 | Màn thành viên → Lịch sử | Có chip chọn ngày, tổng quãng đường, số chuyến, thời gian di chuyển | [ ] | |
| HI-02 | Chọn một mục trong dòng thời gian | Bản đồ vẽ đúng đường đi hoặc điểm dừng tương ứng | [ ] | |
| HI-03 | Ngày không có dữ liệu | Hiện "Không có dữ liệu", không crash | [ ] | |
| HI-04 | Đứng yên 1 tiếng | Chỉ có 1 điểm dừng, không bị tách thành nhiều chuyến do GPS trôi | [ ] | |
| HI-05 | Đi xe máy hoặc ô tô > 20 km/h trong 5 km | Xuất hiện chuyến "Lái xe" trong màn Lái xe | [ ] | |
| HI-06 | Chạy > 80 km/h (người khác lái, an toàn) | Số lần quá tốc độ tăng, điểm an toàn giảm | [ ] | |
| HI-07 | Mở chi tiết chuyến | Giờ bắt đầu/kết thúc, quãng đường, tốc độ trung bình và tối đa khớp thực tế (sai số < 10%) | [ ] | |
| HI-08 | Kiểm tra dữ liệu cũ hơn 30 ngày | Firestore TTL policy đã bật cho `points` | [ ] | |
| HI-09 | Unit test: `flutter test` | Tất cả test đều pass | [ ] | |

### B5. Địa điểm & thông báo đến/rời

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| PL-01 | Thêm địa điểm "Nhà": chạm bản đồ, chỉnh bán kính | Lưu xong, cả nhóm đều thấy | [ ] | |
| PL-02 | B đi ra khỏi "Nhà" (vượt bán kính + 30 m) | A nhận push "B đã rời Nhà" | [ ] | |
| PL-03 | B quay về | A nhận push "B đã đến Nhà" | [ ] | |
| PL-04 | B đứng ngay mép bán kính 10 phút | Không bị push lặp đi lặp lại (nhờ vùng đệm) | [ ] | |
| PL-05 | Test PL-02 khi app B chạy nền hoặc đã bị kill | Ghi lại hành vi thực tế | [ ] | |
| PL-06 | Màn thành viên → Địa điểm | Có lịch sử Đến/Rời kèm giờ | [ ] | |
| PL-07 | Xoá địa điểm | Có hộp xác nhận; xoá xong không còn push cho địa điểm đó | [ ] | |
| PL-08 | Menu → Cảnh báo & hoạt động | Liệt kê đủ sự kiện: đến/rời, SOS, tham gia/rời nhóm | [ ] | |

### B6. SOS, ping, chat

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| SO-01 | A bấm SOS → Huỷ | Không gửi gì | [ ] | |
| SO-02 | A bấm SOS → Gửi | B và C nhận push "🚨 SOS từ A" ngay cả khi máy đang khoá | [ ] | |
| SO-03 | Bấm vào push SOS | Mở app tới vị trí của A. *Hiện chưa có (#31)* | [ ] | |
| PI-01 | A gửi lần lượt 6 loại ping cho B | B nhận đúng nội dung push; C **không** nhận | [ ] | |
| PI-02 | Gửi ping liên tục 10 lần | Không crash. Ghi nhận có bị spam hay không | [ ] | |
| CH-01 | A gửi tin nhắn | B thấy ngay trong app; nếu app đang tắt thì nhận push | [ ] | |
| CH-02 | Tin nhắn dài hoặc có emoji | Hiển thị đúng | [ ] | |
| CH-03 | Người gửi không nhận push tin nhắn của chính mình | Đúng | [ ] | |

### B7. Tính năng riêng của IPing

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| MO-01 | Đăng khoảnh khắc có ảnh + vị trí | Cả nhóm nhận push; marker hiện trên bản đồ | [ ] | |
| MO-02 | Thả hoặc bỏ tim | Số tim cập nhật realtime | [ ] | |
| MO-03 | Sau 24 giờ | Khoảnh khắc tự ẩn | [ ] | |
| MO-04 | Xoá khoảnh khắc của mình / thử xoá của người khác | Xoá được của mình; không có nút xoá ở bài người khác | [ ] | |
| ME-01 | Tạo Meetup: chọn điểm, chọn giờ | Cả nhóm nhận push; có thẻ meetup trên màn chính | [ ] | |
| ME-02 | B bấm "Tôi sẽ tới" rồi đi tới điểm hẹn | Trạng thái chuyển Đang tới → Đã tới; nhóm nhận push "đã tới điểm hẹn" | [ ] | |
| ME-03 | Người tạo bấm Kết thúc | Meetup biến mất ở mọi máy | [ ] | |
| EX-01 | Menu → Khám phá | Có bản đồ sương mù; các ô đã đi qua được mở ra | [ ] | |
| EX-02 | Đi sang khu vực mới | % khám phá tăng; xem chi tiết thấy số liệu khớp | [ ] | |
| EX-03 | Mất mạng khi đang tải ranh giới khu vực | Hiện "Thử lại", bấm vào thì tải lại được | [ ] | |
| EX-04 | Bảng xếp hạng | Đổi được giữa Diện tích và % khu vực; dòng của mình có "(Bạn)" | [ ] | |

### B8. Bảo mật & phân quyền (Firestore rules)

Chạy bằng Emulator (`firebase emulators:start`) hoặc thử trực tiếp từ một client trái phép.

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| SE-01 | C (không ở trong nhóm) đọc `groups/{id}/locations` | Bị từ chối | [ ] | |
| SE-02 | B ghi vào `locations/{uidA}` | Bị từ chối | [ ] | |
| SE-03 | B ghi trực tiếp vào `inviteCodes` | Bị từ chối | [ ] | |
| SE-04 | B (không phải chủ nhóm) đổi tên nhóm | Bị từ chối | [ ] | |
| SE-05 | B tạo ping với `type` không hợp lệ | Bị từ chối | [ ] | |
| SE-06 | B đọc `users/{uidA}` (có chứa FCM token) | Bị từ chối | [ ] | |
| SE-07 | B đọc ping giữa A và C | Bị từ chối | [ ] | |

### B9. Phi chức năng

| ID | Bước | Kết quả mong đợi | Đạt | Ghi chú |
|---|---|---|---|---|
| NF-01 | Bật chia sẻ, để máy chạy nền 8 giờ | Hao pin ở mức chấp nhận được (ghi lại %/giờ) | [ ] | |
| NF-02 | Chế độ sáng / tối | Kính mờ dễ đọc, không có chữ trắng trên nền trắng | [ ] | |
| NF-03 | Màn nhỏ (iPhone SE) và cỡ chữ lớn | Không tràn layout | [ ] | |
| NF-04 | Mạng 3G chậm | Có trạng thái loading, không treo | [ ] | |
| NF-05 | Android 14+ | Có foreground service và quyền thông báo được xin đúng | [ ] | |
| NF-06 | Giải thích quyền vị trí "Luôn luôn" | Có câu giải thích lý do trong Info.plist / màn xin quyền (store yêu cầu) | [ ] | |

---

## Phần C. Ghi nhận lỗi

| Ngày | Máy / OS | Mã test | Mô tả lỗi | Mức độ (Cao/TB/Thấp) | Trạng thái |
|---|---|---|---|---|---|
| 14/10 | (đọc code) | LO-15 | **BUG-01** `locate_background.dart`: khi app chạy nền, yêu cầu vị trí bỏ qua việc ẩn vị trí theo nhóm. Code vẫn ghi toạ độ thật kèm `sharing: true` và xoá `pausedUntil` | Cao | Đã sửa |
| 14/10 | (đọc code) | GR-07 | **BUG-02** `functions/index.js` `removeMemberData` không xoá `safeTrips/{uid}`. Người đã rời hoặc bị xoá khỏi nhóm vẫn làm cả nhóm nhận cảnh báo "quá giờ" | TB | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-03** `safe_trip_service.dart:160` thiếu `onError`: bị xoá khỏi nhóm thì phát sinh lỗi permission-denied không được bắt | Thấp | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-04** `safe_arrive` vẫn gửi toạ độ cho nhóm đang ẩn vị trí. Cảnh báo pin yếu cũng vẫn gửi cho nhóm đang ẩn | Thấp | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-05** Rules không kiểm tra `fromName`/`name`, nên một thành viên có thể gửi push SOS hoặc ping mạo danh tên người khác | TB | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-06** Ping `locate` không giới hạn tần suất, có thể spam push và làm hao pin máy người bị yêu cầu | Thấp | Đã sửa |
| 14/10 | (đọc code) | AU-05 | **BUG-07** Đăng xuất khi mất mạng bị treo: `signOut` chờ ghi Firestore trước, không có thông báo lỗi | TB | Đã sửa |
| 14/10 | (đọc code) | SO-02 | **BUG-08** `group_actions.dart` không bắt lỗi khi `leave`/`sos` thất bại, người dùng không thấy báo gì | TB | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-09** Thiếu kiểm tra `mounted` sau `await`: `member_screen._requestLocation`, `profile_screen._changePhoto`, `sign_in_screen` | TB | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-10** Chế độ Tất cả bạn bè: lỗi ở một nhóm làm mất hết marker (`all_friends_service.dart:89`) | TB | Đã sửa |
| 14/10 | (đọc code) | GR-07 | **BUG-11** Menu giữ group cũ sau khi rời nhóm. Màn thành viên quay vòng mãi khi nhóm bị xoá | Thấp | Đã sửa |
| 14/10 | (đọc code) | HI-07 | **BUG-12** `history_screen.dart` tạo `MapController()` trong `build`, nên rebuild là mất vị trí pan/zoom. Nhiều MapController không được dispose | Thấp | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-13** Hồ sơ: lỗi khi lưu tên hoặc xoá ảnh không hiện thông báo. Bắt đầu Về an toàn khi offline thì nút quay mãi | Thấp | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-14** `checkStaleLocations` báo "mất kết nối" nhầm cho người ngồi yên > 1 giờ (distanceFilter 25 m, không có heartbeat). Sửa: client ghi `lastSeenAt` mỗi 15 phút khi đang chia sẻ; server dựa vào `lastSeenAt`, ngưỡng 4 giờ; push ghi "chưa thấy hoạt động" | TB | Đã sửa |
| 14/10 | (đọc code) | — | **BUG-15** Người bị chặn / xoá khỏi nhóm vẫn đọc và gửi chat 1-1, vẫn bắn push. Sửa: rules `dms/messages` yêu cầu cả hai còn trong `groups/{dm.groupId}.memberIds`; `onDmMessage` kiểm tra lại; `ensureThread` chuyển sang nhóm chung hiện tại | TB | Đã sửa |
| 14/10 | (đọc code) | AU-10 | **BUG-16** `deleteAccount` không xoá chat 1-1. Sửa: xoá mọi `dms` có `members` chứa uid (kèm `messages`) | TB | Đã sửa |
