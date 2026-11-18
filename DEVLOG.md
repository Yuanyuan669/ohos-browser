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


## 2026-11-17 M2：多标签与会话恢复

- 3 标签上限（第 4 个提示“最多 3 个标签”）；新建/关闭/切换；标签标题跟随页面标题。
- 非活动销毁：切换标签时重建 Web 节点与 `WebviewController`，旧页面不常驻；新 Web 直接用 `src` 加载目标 URL（避免先加载主页再跳转）。
- 会话恢复：`preferences` 存 `tabs`(JSON) + `active`；重启恢复标签与激活项，并加载激活页 URL。
- 实测：2→3 标签创建正常；第 4 个被拦截；切换示例页直载 379ms；重启后 2 标签与标题恢复。
- **RSS 限制**：切走 5s 后 PSS 仍约 106MB（example 105645 → home 105955），Web 渲染进程/缓存不随节点销毁释放；API 11 只有 `clearHistory()`，无 purge 接口。当前内存不随标签数增长（同一时刻只加载一页），但达不到“明显下降”的验收，记录为引擎限制。
- 坑：ForEach 的 key 必须包含标题，否则标签标题变更不刷新；`+`/`关` 按钮宽 34vp 时文字被挤成省略号，改 42/46vp。

## 状态

- M2 完成（RSS 一项受引擎限制）。
- 下一步 M3：书签/历史（preferences）。


## 2026-11-18 M3：书签与历史

- 书签：地址栏 `☆/★` 一键收藏/取消；按 URL 去重；标题取当前页标题，空标题回退 URL。
- 历史：主框架 HTTP(S) 页面 `onPageEnd` 自动记录；按 URL 去重并置顶，最多 100 条；主页 `resource://` 不记录。
- 面板：工具栏“列表”打开覆盖层，不销毁 Web（保留页面状态）；书签/历史分页、条数、单项删除、清空、点击条目直接打开。
- 持久化：`preferences` 键 `bookmarks` / `history`，JSON 数组 `{url,title,time}`；启动与标签会话一起恢复。
- 实测：
  - `https://example.com` 打开后点星：书签 1、历史 1，状态“已收藏”，星变黄。
  - 杀进程重启：日志 `session restored 1 tabs, 1 bookmarks, 1 history`；页面、星标、面板列表均恢复。
  - 面板内删书签：书签 0、星恢复空心、显示“暂无书签”；清空历史：历史 0、显示“暂无历史”。
  - 清空后刷新页面：历史重新记为 1；点击历史条目可关闭面板并重新加载该 URL。
  - 构建：unsigned 1,045,383 bytes；signed 1,048,000 bytes；API 10 安装正常。
- 坑：
  1. 面板列表原来用 `Scroll > Column`，单项内容在剩余空间里垂直居中；改用 `List` + 面板 `justifyContent(FlexAlign.Start)`，列表从顶部开始。
  2. 删除按钮不能放在整行 `onClick` 里，避免“删”触发打开；点击区域只放在标题列。
- 状态：M3 完成；M4（下载）仍受 API 11 升级/卸载重装约束。

## M4 预研：下载可行性（2026-11-17）

- **API 11 WebDownloadDelegate（推荐）**：`controller.setDownloadDelegate(delegate)`，`WebDownloadItem` 提供
  `getPercentComplete/getReceivedBytes/getTotalBytes/getState/pause/resume/cancel/getFullPath`；能复用 Web 的 cookie/UA。
  本项目 compileSdk=10，需升 11（会触发 9568282，需卸载重装）。
- **API 10 备选**：`Web.onDownloadStart` 取 url/userAgent/contentDisposition/mimetype/contentLength，交给
  `@ohos.request.downloadFile`（需 INTERNET，已有）。缺点：不带 Web 会话 cookie、无暂停/续传 UI 集成。
- 待确认：下载目录（delegate 默认路径 + `getFullPath` 导出）、`blob:/data:` 链接不支持、断点续传服务器要求。
