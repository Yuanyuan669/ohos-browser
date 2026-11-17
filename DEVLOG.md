# ohos-browser DEVLOG

> 目的：记录设计、踩坑与状态，上下文压缩后可续接。
> 路线图：`D:\ohos-device\docs\APP-ROADMAP.md` Phase 3

## 2026-11-17 M0：工程空壳 + Web 验证

- 工程：`com.local.browser`，由快传模板复制，compileSdk 10。
- 页面：`Web` + `$rawfile('home.html')` 本地主页；地址栏 + 打开；标题/状态/进度；偏好保存 lastUrl。
- 实测：
  - 本地主页首帧 **45ms**；`https://example.com` **226ms**；`https://cn.bing.com` **228ms**。
  - 自定义 UA 生效：`Mozilla/5.0 (Phone; OpenHarmony 4.1) ... HomeBrowser/0.1`（首页显示 navigator.userAgent）。
  - 偏好：`lastUrl` 写入并在重启后读回。
  - RSS：Bing 首页加载后 `hidumper --mem` PSS ≈ **108 MiB**（M6 目标 ≤300 MiB 有余量）。
- 未做：picker/request 导入验证（M4 下载前再引入）。

## 踩坑

1. **ArkTS 不支持正则字面量**（`arkts-no-regexp-literals`）：IP 判断改成首字符数字判断。
2. **不能用对象字面量当类型**（`arkts-no-obj-literals-as-types`）：Web 回调参数要定义 `interface PageEvent/ProgressEvent/TitleEvent`。
   - `onProgressChange` 参数是 `{newProgress}`，`onTitleReceive` 是 `{title}`，不是裸值。
3. **`onPageEnd` 对 rawfile 返回 `resource://rawfile/home.html`**：曾把该值写进地址栏和 preferences；现在过滤 `resource://`。
4. **example.com 在 Web 里文字发黑**（Bing 正常）：已设置 `darkMode(WebDarkMode.Off)` + `forceDarkAccess(false)`，Bing 显示正常；example.com 可能自身暗色 CSS/透明画布叠加，M2 再复查。
5. 模板里 Logger 的 TAG 仍是 `HomeKiosk`，已改为 `HomeBrowser`。
6. 每次 `hdc install` 会重置默认输入法为 Kika，测试后恢复 homeime。

## 状态

- M0 完成，等待 M1（导航按钮/停止/错误页）。
- GitHub 仓库尚未创建（本地 git 已初始化，无 remote）。


## 2026-11-17 M1：导航与错误页

- 新增：后退/前进（含可用态灰显）、刷新/停止（加载中显示“停止”）、主页、URL 规范化（无 scheme 补 https；IP/localhost/带端口补 http）。
- 错误页：`onErrorReceive` 仅处理主框架，覆盖层显示错误码/信息 + 重试/回主页。
- 外部拉起：`aa start ... --ps url <url>` 通过 AppStorage.startUrl 传参；等本地主页 `onPageEnd` 后再 loadUrl，避免与初始 rawfile 加载竞态。
- 实测：
  - 后退回本地主页（13ms），前进回 example 命中缓存（1ms）。
  - 错误页：`https://nonexistent.invalid` → `-105 ERR_NAME_NOT_RESOLVED`，覆盖层正常。
  - HTTP + IP:端口：`http://192.168.31.175:8080/` 22ms 打开。
  - 刷新：example 219ms。
  - 冷启动：本地 37ms；example 冷加载 1.2~3.1s（首次 DNS/TLS）。
- 踩坑：
  1. `↻/⌂` 字形在该设备字体缺失，按钮显示空白 → 改为中文“刷新/停止/主页”。
  2. startUrl 在 `onControllerAttached` 里立即 loadUrl 会被初始 rawfile 覆盖；改为首页 `onPageEnd` 后加载。
  3. example.com 深色下黑底黑字是站点自身 `background:light-dark(#eee,#222)` 且未设 color，不是浏览器 bug；Web 已 `darkMode(Off)+forceDarkAccess(false)`。
  4. `Web` 背景设为白色，避免无背景页透出应用深色底（对纯文本/无 CSS 页面更接近默认浏览器）。

## 状态

- M1 完成；停止按钮因测试 URL 立刻失败未做有效验证，代码路径已实现。
- 下一步 M2：3 标签上限、非活动销毁、会话恢复。
