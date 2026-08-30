## Build nhanh để chạy thử trên máy (dòng lệnh)

Nếu bạn chỉ muốn build rồi chạy thử bản vừa sửa, dùng script:

```
cd Sources/OhMyKey/macOS
./scripts/build-and-install.sh          # Release
./scripts/build-and-install.sh Debug    # Debug
```

Script build rồi cài thẳng vào `/Applications/OhMyKey.app`, sau đó chạy bằng
`open -a OhMyKey`.

Vì sao cài vào `/Applications` thay vì bấm Run trong Xcode: OhMyKey cần quyền
Accessibility, mà macOS gắn quyền này với **chữ ký** và **đường dẫn** của ứng dụng.
Xcode build vào thư mục DerivedData thay đổi liên tục nên lần nào cũng phải cấp
quyền lại.

Lưu ý: bản build này chỉ được ký ad-hoc (`CODE_SIGN_IDENTITY=-`), mà chữ ký ad-hoc
được tính từ chính file binary — nên **mỗi lần build lại là một danh tính mới** và
macOS sẽ không nhận quyền đã cấp trước đó. Khi ứng dụng vừa mở đã tắt ngay, cấp lại
quyền như sau:

```
tccutil reset Accessibility com.hungdoansy.ohmykey
open -a OhMyKey     # bấm "Cấp quyền", rồi bật OhMyKey trong danh sách
```

Ký bằng chứng chỉ Developer ID thật thì quyền sẽ giữ nguyên qua các lần build.

Ngoài ra, nhớ **tắt hẳn bộ gõ khác** (OpenKey, EVKey, UniKey...) trước khi chạy, vì
hai bộ gõ chạy cùng lúc sẽ tranh nhau từng phím gõ.

## Cách build cho macOS:

Vì một số lý do mà OhMyKey không thể đưa lêp Mac App Store được, nếu các bạn không yên tâm về file build chính thức từ tác giả, các bạn có thể tải mã nguồn về tự build lấy OhMyKey cho mình.

Yêu cầu:

- macOS Mojave trở lên.
- XCode 10 trở lên.

Tải mã nguồn từ dự án OhMyKey trên GitHub về, mở dự án OhMyKey bằng cách vào:
<img width="808" alt="Screen Shot 2022-06-01 at 13 34 39" src="https://user-images.githubusercontent.com/7700801/171342552-46c391a7-9160-4677-bb8a-9d8cececcfe6.png">

Dự án OhMyKey sẽ hiện ra:
<img width="1522" alt="Screen Shot 2022-06-01 at 13 37 36" src="https://user-images.githubusercontent.com/7700801/171343050-aa2f9629-4670-4c1e-a3c0-0c25acefa42d.png">

Giờ bạn vào menu Product -> Archive để Xcode tiến hành build OhMyKey ở dạng Production (có thể dùng được), sau khi build xong hộp thoại sẽ xuất hiện, bấm vào Distribute App
<img width="1112" alt="Screen Shot 2022-06-01 at 13 45 50" src="https://user-images.githubusercontent.com/7700801/171344111-540b66cb-556f-48cf-ad3b-0f44ab208d1a.png">

Nó sẽ ra:
<img width="1112" alt="Screen Shot 2022-06-01 at 13 48 53" src="https://user-images.githubusercontent.com/7700801/171344529-12eed723-4e66-4818-8502-fa693b269dba.png">

Bấm Next để chọn nơi lưu trữ file Build. Vậy là xong, bạn đã có ứng dụng OhMyKey.app của riêng bạn.

Lưu ý: trong quá trình build, nếu XCode bão lỗi `invalid in C99`, khả năng cao là ở trong file `MJAccessibilityUtils.m`, dòng 26 `isEnabled = AXAPIEnabled();`, bạn lên đầu file thêm khai báo `extern BOOL AXAPIEnabled();` là sẽ build được.

Chúc các bạn Build OhMyKey cho macOS thành công!

## Phát triển giao diện

Giao diện được viết bằng SwiftUI (yêu cầu macOS 13 trở lên). Vì macOS gắn quyền
Accessibility với chữ ký của ứng dụng, mà chữ ký ad-hoc lại thay đổi sau mỗi lần build,
nên bản vừa build luôn thoát ngay khi khởi động để xin quyền lại. Để xem giao diện mà
không phải cấp quyền:

```bash
cd Sources/OhMyKey/macOS
./scripts/preview-ui.sh              # build Debug, chụp ảnh cả 4 cửa sổ
./scripts/preview-ui.sh --lang en    # xem bản tiếng Anh
```

Chế độ này (`OMK_UI_ONLY=1`) bỏ qua phần xin quyền, bỏ qua event tap và bỏ qua kiểm tra
"đã chạy rồi", nên nó chạy song song với bản đang dùng và không gõ được gì.

Chạy unit test:

```bash
./scripts/run-tests.sh
```
