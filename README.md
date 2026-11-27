# 配货清单 Flutter 版（Android / iOS）

这是鸿蒙 ArkTS 版的 Flutter 跨平台重写工程，目标是在 Android 和 iOS 上提供同样的配货清单流程。

## 已实现

- 首页配货清单：相机/相册多图（最多 9 张）、图片预览缩略图、删除；
- 本地 OCR：Google ML Kit 中文文字识别；
- 服务端 OCR：请求现有 Python `/ocr` 接口，单张超时 120 秒，上传前压缩到 2000px；
- 本地优先：本地数据缺失时弹窗询问是否使用服务端；多张图部分失败时保留成功结果；
- 识别结果：物料代码后 4 位红色、供应商、LPN、识别来源、数量、每箱数量；
- 完成标记：每行「完成」按钮，完成后整行变灰；
- 分配：按每箱数量显示「整箱 + 零头」，并给出「拿几箱、剩/去几个」建议；
- 合并：相同供应商 + 物料代码逐组询问合并，保留 `5+5+2` 明细；
- 查看数据：`供应商-后4位-数量`，复制格式 `后4位-数量`；
- 识别历史：本地保存最近 7 天，点击整行恢复，支持删除/清空；每页 10 条，可上一页/下一页；
- 货品配置：查看、搜索（供应商/物料代码后 4 位）、新增、编辑、删除、查重；
- 货品图片字段：新增/编辑时可拍照或从相册上传最多 3 张货品照片，压缩到 800px 后保存到应用目录，列表显示缩略图；
  点击缩略图可全屏缩放查看，点击画笔按钮可在图片上标注/涂画；
  箱贴识别按钮只用于自动填字段，不保存识别图片；
- 供应商：查看、新增、编辑、删除；
- 箱贴识别：新增货品时最多 3 张图片，压缩到 1200px 后用本地 OCR 回填代码/描述/LPN/包装数量；
- 计算器：四则运算、括号、每箱数量、整箱/零头。
- 货品库存统计：打开即为库存列表页，右上角支持同步/新增/导出；新增通过弹窗表单完成，含拍图识别、供应商下拉、数字键盘和计算器；
- 库存列表：每页 10 条，支持开始/结束日期范围、供应商筛选、物料代码后 4 位搜索（与供应商条件同一行）、编辑、删除；
- 库存同步：一键把库存中有、货品配置中没有的货品补进配置；新增库存时也会自动同步到货品配置；
- 库存 Excel 导出：按制造商包含的供应商简称匹配「供应商编码」，不再导出制造商原文；
- 货品配置每行「编辑」左侧增加装箱计算器，自动带入每箱数量，实时显示整箱+零头；
- UI 已统一为浅色卡片设计，修复 Android 底部黑色导航栏，状态栏/导航栏改为透明；
- 货品标签 OCR：最长边 1800px，字段不完整时自动尝试 90/180/270 度旋转并选最优；
- 配货清单本地 OCR：最长边 2400px，多列单元格按坐标聚合。

## 运行

需要 Flutter SDK（建议官方 Flutter 3.35+）。当前机器安装的是 Flutter OHOS 分支；本机已安装 Android SDK 和 JDK 17，并成功构建 APK。

```bash
cd E:\wechat\goods_flutter
flutter pub get
flutter analyze
flutter test
```

Android：

```bash
flutter run -d <android-device>
# 或
flutter build apk --release --split-per-abi
```

iOS（需要 macOS + Xcode）：

```bash
cd ios
pod install
cd ..
flutter run -d <iphone>
```

Android APK（本机已构建）：

- arm64：`E:\wechat\goods\dist\goods-flutter-arm64.apk`（约 32MB）
- armv7：`E:\wechat\goods\dist\goods-flutter-armv7.apk`（约 26MB）
- 通用包：`E:\wechat\goods\dist\goods-flutter-universal.apk`（约 65 MB）

iOS 说明：`ios/Podfile` 已加入 `GoogleMLKit/TextRecognitionChinese`，在 macOS 上执行 `pod install` 后即可使用中文识别；否则会回退到拉丁识别器。

## 库存统计与 Excel

- 入口：首页右上角库存箱图标；
- 拍图/相册后复用箱贴 OCR，回填代码、包装数量、描述、XS 批次号、制造商，并自动匹配供应商；
- 系统库存、实际库存手动录入；实际库存使用算式解析，例如 `30+20+35` 显示合计 85；
- 保存记录后按录入时间倒序显示；
- 导出生成真正的 `.xlsx`，列为：录入时间、系统库存、实际库存、物料代码、包装数量、物料描述、XS批次号、供应商编码；
- Android 通过原生 `ACTION_SEND` 分享文件；iOS 未实现原生分享时会提示文件路径。

## 本地 OCR

Android 端已显式加入 `com.google.mlkit:text-recognition-chinese:16.0.1`，否则插件只包含通用识别器，中文会失败。

使用 `google_mlkit_text_recognition`：

- Android/iOS 原生 ML Kit 中文识别；
- 图片先压缩到最长边 2000px（箱贴 1200px）；
- 不依赖服务端。

ML Kit 在模拟器/桌面/Web 上不可用；当前 Web 只用于 UI 预览，OCR 会提示不支持。

## 服务端 OCR

首页「服务设置」填写：

```text
https://your-ocr-server.example.com/ocr
```

也可以使用局域网地址或 `http://127.0.0.1:8000/ocr`（USB 转发时）。

## 验证结果

```text
flutter analyze  -> No issues found
flutter test     -> 20 tests passed
flutter build web --release --no-wasm-dry-run -> build/web 生成成功
flutter build apk --debug -> app-debug.apk 成功
flutter build apk --release --split-per-abi -> arm64/armv7/x86_64 三个 release APK 成功
```

Android APK 已在本机使用 E:\android-sdk + JDK 17 成功构建；iOS IPA 需要 macOS + Xcode。

## 与鸿蒙版的差异

- 鸿蒙版本地 OCR 使用 CoreVisionKit；Flutter 使用 ML Kit，识别结果和表格解析需要针对真实单据继续调参；
- 鸿蒙版的复杂透视/单行容差逻辑已简化，Flutter 版优先依赖服务端兜底；
- 历史行点击、完成变灰、查看数据/复制、供应商/货品管理已实现；
- 服务端协议、供应商/货品数据格式保持一致。

## 目录

```text
lib/
  main.dart
  models.dart
  repository.dart
  calculator.dart
  ocr_service.dart
  widgets.dart
  screens/home_screen.dart
  screens/calculator_screen.dart
  screens/catalog_screen.dart
assets/goods_catalog.json
```
