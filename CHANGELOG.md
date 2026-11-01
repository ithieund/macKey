# Nhật ký thay đổi macKey

## macKey — Chưa phát hành

### Bố cục và giao diện

- Viết lại giao diện macOS bằng SwiftUI. Settings, Compatibility, gõ tắt, chuyển mã và About nay
  dùng cửa sổ co giãn theo nội dung thay cho storyboard cũ có 118 control đặt kích thước cố định.
- Thay giao diện tab có khung bằng segmented control gọn hơn và grouped form đáp ứng tốt hơn, để
  nhãn vẫn dễ đọc ở các cỡ chữ hệ thống khác nhau.
- Thêm bản địa hoá giao diện tiếng Anh và tiếng Việt, có thể cấu hình qua tuỳ chọn ngôn ngữ giao
  diện macOS.
- Làm mới icon ứng dụng và thanh menu, đồng thời chỉ hiển thị icon Dock khi một cửa sổ macKey đang
  mở.

### Tính năng mới và cải tiến

- Thêm cửa sổ Compatibility có thể chỉnh sửa, với các chế độ gửi phím theo từng ứng dụng để xử lý
  lỗi với trình duyệt, Chromium, Office và layout không phải QWERTY.
- Thêm phương án dự phòng Secure Input để tạm chuyển sang input source tiếng Việt của macOS khi
  macKey không thể nhận phím gõ.
- Thêm trình chỉnh sửa gõ tắt riêng, hỗ trợ tạo, cập nhật, xoá, import và export.
- Thêm script UI-only preview, build-and-install, local signing và unit test chuyên biệt để phát
  triển, test an toàn và thuận tiện hơn.
- Chuyển các tuỳ chọn OpenKey, macro và mục Smart Switch ở lần chạy đầu mà không thay đổi cài đặt
  OpenKey gốc.

### Dự án

- macKey là bản fork của OhMyKey của hungdoansy; OhMyKey lại dựa trên OpenKey.
- Đổi tên ứng dụng macOS thành macKey. Ứng dụng đổi bundle ID sang `vn.ithieund.mackey`. và chỉ giữ lại mã nguồn macOS trong repository.
- Do bundle ID thay đổi, macOS coi đây là ứng dụng mới: bạn cần **cấp lại quyền Accessibility** trong *System Settings -> Privacy & Security -> Accessibility*.

##### Đổi tên thành OhMyKey (30/08/2026) - hungdoansy:
- OhMyKey là bản fork của OpenKey. Ứng dụng đổi bundle ID sang `com.hungdoansy.ohmykey`.
- Thiết lập, macro và dữ liệu chuyển chế độ thông minh được **tự động chuyển** từ bản OpenKey cũ trong lần chạy đầu tiên.
- Biểu tượng trên thanh menu được vẽ lại để dễ nhìn hơn trên nền sáng.

##### Lịch sử của OpenKey (bản gốc) ở phía dưới:

##### OpenKey cho Linux: (đang phát triển)

##### Version 1.2 RC5: (26/08/2019)
- Sửa lỗi không gõ được chữ "quởn".
- Không kiểm tra chính tả khi sử dụng dấu "[ ] { }".

##### Version 1.2 RC4: (24/08/2019)
- Bảng gõ tắt tiện lợi hơn, thêm tính năng Sửa từ.
- Cải thiện khả năng bỏ dấu, tốc độ nhanh hơn.
- Tự phục hồi dấu câu khi xóa ký tự (chữ “tuỳa” xóa “a” sẽ thành “tùy”,… )
- Sửa lỗi không gõ được từ “quét” khi bật chức năng tự phục hồi phím.
- Sửa lỗi ư và ơ khi gõ font Palatino trong MS Word.
- Sửa lỗi bảng mã VNI khi xóa ký tự, không thể gõ tiếng việt tiếp.

##### Version 1.2 RC3: (16/08/2019)
- Không gõ được "dui9, duoi96".
- Không gõ được "tuyps".

##### Version 1.2 RC2: (15/08/2019)
- Sửa lỗi không gõ được d i e u 9 6.
- Sửa lỗi không gõ tắt được khi dùng chế độ tiếng Anh với từ bắt đầu bằng.
- Sửa lỗi tự nhảy dấu khi gõ sai.
- Thêm thông tin phiên bản trong bảng giới thiệu.

##### Version 1.2 RC1: (13/08/2019)
- Chuyển chế độ thông minh: Bạn đang dùng chế độ gõ Tiếng Việt trên ứng dụng A, bạn chuyển qua ứng dụng B trước đó bạn dùng chế độ gõ Tiếng Anh, OpenKey sẽ tự động chuyển qua chế độ gõ Tiếng Anh cho bạn, khi bạn quay lại ứng dụng A, OpenKey tất nhiên sẽ chuyển lại chế độ gõ tiếng Việt, rất cơ động.
- Viết Hoa chữ cái đầu câu: Khi gõ văn bản dài, đôi khi bạn quên ghi hoa chữ cái đầu câu khi kết thúc một câu hoặc khi xuống hàng, tính năng này sẽ tự ghi hoa chữ cái đầu câu cho bạn, thật tuyệt vời.
Khôi phục phím với từ sai: hỗ trợ thêm các dấu ngắt câu như dấu chấm, phẩy,...
Sửa vài lỗi nho nhỏ khác.

##### Version 1.1 RC: (12/08/2019)
- Chế độ “Gửi từng phím”: OpenKey bản mới (1.1) mặc định dùng kỹ thuật mới gửi dữ liệu 1 lần thay vì gửi nhiều lần cho chuỗi ký tự, nên nếu có ứng dụng nào không tương thích, hãy bật tính năng này lên, mặc định thì nên tắt vì kỹ thuật mới sẽ chạy nhanh hơn.
- Phục hồi phím với từ sai.
- Nâng cao khả năng check chính tả.
- Sửa lỗi thanh địa chỉ trình duyệt (on/off).
- Bỏ tính năng "cho phép bỏ dấu tự do".
- Gõ tắt: bao gồm bật/tắt, bảng soạn các từ gõ tắt, hỗ trợ ký tự bất kỳ, bảng mã bất kỳ. Khi soạn thảo các từ gõ tắt, bạn phải nhập ở bảng mã Unicode dựng sẵn.
- Gõ tắt ngay khi trong chế độ gõ tiếng Anh (on/off).
- Sửa lỗi trên một số phần mềm.

##### Version 1.0.20: (06/08/2019)
- Sửa lỗi phím tắt chuyển chế độ, phím tắt của ứng dụng khác vẫn hoạt động nếu bị trùng.
- Cho phép gõ “Đ” ngay sau phụ âm.
- Không hiện Icon trên thanh Dock mục recent app.
- Sửa lỗi “oăc” ra “ooạc” trong kiểu gõ VNI.
- Sửa vài lỗi nhỏ xíu khác.

##### Version 1.0.19: (04/08/2019)
- Sửa lỗi không gõ được chữ “gì” khi dùng bỏ dấu kiểu cũ.
- Sửa lỗi không gõ được Unicode tổ hợp trên ứng dụng Stickies.
- Sửa lỗi gõ các âm "oong, ooc".

##### Version 1.0.18: (01/08/2019)
- Không sử dụng w -> ư trong Simple Telex.
- Bật tắt kêu beep khi chuyển chế độ.
- Thêm phím chuyển Shift, giờ có thể sử dụng Ctrl + Shift hoặc Command + Shift.
- Sửa vài lỗi khác.
- Hỗ trợ cho macOS bản cũ.

##### Version 1.0.17: (31/07/2019)
- Thêm chế độ Simple Telex.
- Icon đen/trắng trên thanh menu.
- Cải thiện phím Space và Backspace.
- Chính tả kiểu mới.
- Tuỳ chỉnh phím chuyển.
- Gõ nhanh Telex (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- Hỗ trợ TextWrangler.

##### Version 1.0.14: (09/04/2019)
- Thêm trường hợp "uýt".
- Cải thiện việc gõ English trong chế độ tiếng Việt.

##### Version 1.0.11: (27/02/2019)
- Thêm trường hợp "chú thòong", "gòong".

##### Version 1.0.10: (26/02/2019)
- Sửa trường hợp "duocd".

##### Version 1.0.9: (22/02/2019)
- Sửa từ sai khi chuyển ngôn ngữ mà không bấm phím Space.

##### Version 1.0.8: (19/02/2019)
- Phím chuyển: Control + Command + Space  --> Control + Z

##### Version 1.0.7: (15/02/2019)
- Sửa trường hợp "duongd".
- Sửa phụ âm cuối "t".

##### Version 1.0.6: (15/02/2019)
- Sửa trường hợp "quatw".

##### Version 1.0.5: (13/02/2019)
- Cải thiện chính tả.
- Sửa icon thanh menu 1x.

##### Version 1.0.3: (11/02/2019)
- Sửa auto correct trên Chrome.

##### Version 1.0: (11/02/2019)
- Phát hành lần đầu.



# OpenKey lịch sử

##### Version 1.0.17: (31/07/2019)
- Thêm chế độ Simple Telex.
- Icon trắng đen trên menu bar.
- Lỡ bấm phím Space, xoá space vẫn có thể bỏ dấu.
- Bỏ dấu kiểu cũ/mới: òa, úy | oà, uý.
- Tuỳ chọn phím chuyển.
- Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- Hỗ trợ TextWrangler.

##### Version 1.0.11: (27/02/2019)
- Thêm trường hợp "chú thòong", "gòong".

##### Version 1.0.10: (26/02/2019)
- Sửa lỗi "duocd".

##### Version 1.0.9: (22/02/2019)
- Sửa lỗi từ sai khi đổi chế độ mà không bấm phím Space.

##### Version 1.0.8: (19/02/2019)
- Phím chuyển: Control + Command + Space  --> Control + Z

##### Version 1.0.7: (15/02/2019)
- Sửa lỗi "duongd".
- Sửa lỗi phụ âm cuối "t".

##### Version 1.0.6: (15/02/2019)
- Sửa lỗi "quatw".

##### Version 1.0.5: (13/02/2019)
- Nâng cao chính tả.
- Sửa icon cho màn hình non-retina.

##### Version 1.0.3: (11/02/2019)
- Sửa lỗi thanh địa chỉ trên Chrome.

##### Version 1.0: (11/02/2019)
- Phát hành lần đầu.
