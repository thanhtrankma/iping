/// Các quy tắc thuần (không phụ thuộc Firebase / plugin) quyết định khi nào được dùng hoặc gửi vị trí.
/// Tách riêng để kiểm thử.
library;

/// Nhóm được nhận vị trí (toạ độ, lịch sử, sự kiện lộ vị trí, điểm khám phá): người dùng đã đồng ý
/// chia sẻ với nhóm đó ([allowed]) và nhóm không đang tạm ẩn ([paused]).
List<T> writableGroups<T>(
  Iterable<T> groups, {
  required String Function(T) id,
  required bool Function(String gid) allowed,
  required bool Function(String gid) paused,
}) =>
    [
      for (final g in groups)
        if (allowed(id(g)) && !paused(id(g))) g,
    ];

/// Khám phá chỉ ghi nhận vị trí khi: đang bật chia sẻ (cùng phiên dịch vụ nền đang hiện thông báo),
/// hoặc màn Khám phá đang mở và app đang ở tiền cảnh. Khám phá không phải mục đích dùng vị trí nền riêng.
bool exploreMayRecord({required bool sharing, required bool screenVisible, required bool appInForeground}) =>
    sharing || (screenVisible && appInForeground);

/// Đọc trạng thái đồng ý theo nhóm trong isolate nền (push "locate").
/// [raw] là chuỗi lưu tại `GroupConsent.prefKey(uid)`; chưa có dữ liệu đồng ý thì KHÔNG gửi
/// (app chưa từng phát hành nên không có người dùng cũ cần chuyển đổi).
bool backgroundConsentAllows(String? raw, String gid, Set<String> Function(String raw) parse) =>
    raw != null && parse(raw).contains(gid);
