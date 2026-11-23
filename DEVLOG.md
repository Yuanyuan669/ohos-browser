# ohos-browser DEVLOG

> 目的：记录设计、踩坑与状态，上下文压缩后可续接。
> 路线图：`ohos-device/docs/APP-ROADMAP.md` Phase 3

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

## 2026-11-18 M3.1：布局、UA 与调试开关

- 布局参考 Chrome Android / Safari：顶部地址栏，底部集中操作区；标签不再随数量拉满整行。
- 标签宽度按数量自适应：1 个 110vp，2/3 个按剩余空间收缩（下限 58vp），右侧 `+`/`关` 固定；3 标签实测不溢出。
- 地址栏保持 `layoutWeight(1)` 自适应；收藏按钮 44vp、`padding(0)`，星形完整显示；打开按钮 58vp。
- 底部按钮统一放进一个深色圆角工具条：`←` `→` `刷新/停止` `主页` `书签` `手机/电脑`，不再是各自独立的散按钮。
- `列表` 改名 `书签`；面板内仍然是“书签 / 历史”两页，避免入口含义不清。
- UA 切换：
  - 原 UA：`Mozilla/5.0 (Phone; OpenHarmony 4.1) AppleWebKit/537.36 (KHTML, like Gecko) HomeBrowser/0.1`
  - 手机（默认）：`Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36`
  - 电脑：`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36`
  - `uaMode` 持久化；切换后立即 reload，当前按钮显示 `手机`/`电脑`。
- 页面信息/耗时默认隐藏；面板底部新增“显示页面信息与加载耗时”开关，`showDebug` 持久化；打开后才显示标题、完成耗时和当前 UA 档位。
- 实测：单标签紧凑、3 标签不溢出；手机/电脑 UA 在本地主页回显；杀进程重启后 desktop UA 与调试开关状态保持；面板打开/关闭正常。
- 构建：unsigned 1,066,637 bytes；signed 1,072,184 bytes；API 10 安装正常。
- 限制：目前只切 UA，不改 viewport；少数站点仍按实际视口做响应式布局，必要时再补桌面视口模拟。

## 2026-11-18 M4：下载

- 升级 API：`compileSdkVersion` / `compatibleSdkVersion` 10 → 11；实测 `install -r` 报 `9568282 install releaseType target not same`，必须卸载重装。
- 重装前用 hdc 拉取 `preferences/browser`，重装后 push 回并 chown，书签/历史成功保留。
- 下载代理：`WebviewController.setDownloadDelegate(new WebDownloadDelegate())`：
  - `onBeforeDownload` 取建议文件名，清洗非法字符、同名自动加 `_n`，调用 `item.start(path)`。
  - 保存到应用级 `filesDir/downloads`（`getApplicationContext().filesDir`；模块级 `haps/entry/files` 无写权限）。
  - `onDownloadUpdated/Finish/Failed` 更新状态；`finalizeDownload` 在路径不一致时从引擎临时路径复制到目标路径。
- 进度：ArkTS 侧 `WebDownloadItem` 的进度读取不稳定，改为每 500ms `fs.statSync(row.path)` 轮询已写入字节数；稳定 key `guid_state` 避免进度刷新打断按钮点击，文字用 nonce 触发刷新。
- UI：面板新增“下载 n”页；下载行显示文件名、状态、字节进度条、暂停/继续/取消/重试/打开；清空只移除已完成/已取消/失败记录，保留进行中任务。
- 实测：
  - 16MB 文件：进度递增，完成后落到 `files/downloads/m4-test.bin`；源文件与下载文件 SHA256 均为 `080ACF35...9643E`。
  - 128MB 文件：下载到 1% 暂停（已暂停 · 1%），点继续后继续增长；取消后显示“已取消/重试”。
  - 面板三页签与按钮在 1080x2408 实机布局正常。
  - 重装恢复 prefs 后曾出现“历史重启丢失”：只 chown 了文件，`haps/entry/preferences` 目录仍是 root，preferences flush 写临时文件失败且未处理 Promise；`chown -R` 目录后实测 4 条历史重启保留，并把保存封装为 `savePref` 记录 put/flush 失败。
- 构建：unsigned 1,165,135 bytes；signed 1,170,679 bytes。
- 限制：下载记录只在内存，重启后记录清空但文件保留；未做公共 Downloads 导出和断点续传持久化；`打开` 使用 `ohos.want.action.viewData`，无对应查看器时只提示失败。

## M4 预研：下载可行性（2026-11-17）

- **API 11 WebDownloadDelegate（推荐）**：`controller.setDownloadDelegate(delegate)`，`WebDownloadItem` 提供
  `getPercentComplete/getReceivedBytes/getTotalBytes/getState/pause/resume/cancel/getFullPath`；能复用 Web 的 cookie/UA。
  本项目 compileSdk=10，需升 11（会触发 9568282，需卸载重装）。
- **API 10 备选**：`Web.onDownloadStart` 取 url/userAgent/contentDisposition/mimetype/contentLength，交给
  `@ohos.request.downloadFile`（需 INTERNET，已有）。缺点：不带 Web 会话 cookie、无暂停/续传 UI 集成。
- 待确认：下载目录（delegate 默认路径 + `getFullPath` 导出）、`blob:/data:` 链接不支持、断点续传服务器要求。


## 2026-11-23 M5：上传 / window.open / SSL 二次确认 / 深色模式

- 上传（`onFileSelectorShow` + `FileSelectorResult.handleFileList`）：
  - nweb 把 `accept="image/*"` 展开成扩展名列表（`.png,.jpg,...`），按 MIME 前缀和扩展名一起判断；图片/视频走 `PhotoViewPicker`，其余走 `DocumentViewPicker`；支持多选（最多 8）。
  - 媒体 URI（`file://media/Photo/...`）直接交给 nweb（一次授权，实测可读）。
  - 文档 URI 复制到 `filesDir/upload/<序号>_<安全文件名>`，交给 nweb **绝对沙盒路径**（nweb 读 `file://com.local.browser/...` 形式会得到 0 B，勿用该形式）。
  - `mkdirSync` 的 `13900015`（EEXIST）视为成功；复制失败回退原 URI 并记日志。
- `window.open`：`onWindowNew` 拦截；空白弹窗提示拦截；有 URL 时 3 标签内新标签打开，超限则当前标签载入。
- SSL：`onSslErrorEventReceive` 暂停并弹覆盖层（错误码 + 继续/取消）；确认后 `handler.handleSslError(...CONFIRM)` 继续加载，取消则 `CANCEL`。
- 深色：面板三档 `关闭 / 跟随系统 / 开启`（`WebDarkMode.Off/Auto/On` + `forceDarkAccess`），`darkMode` 持久化。
- 外部协议：`onLoadIntercept` 主框架拦截非 web scheme（`weixin://`、`mailto:`、`baiduboxapp://` 等），状态栏提示“已拦截外部协议”。
- 测试页 `rawfile/devtest.html`：图片上传、通用文件上传、`window.open`、外部协议、badssl 四链接；主页加入口。
- 真机实测（LHT16 / OH 4.1.7.5，API 11）：
  - 图片上传：`OhScreen_1795334801749.png`（557,819 bytes）→ 页面回显 `image/png`，前 160 字节 PNG 头可读，字节完整。
  - `window.open`：日志 `windowNew url=resource://rawfile/devtest.html?child=1`，新标签载入正常。
  - 外部协议：`blocked scheme weixin://dl/business`、`mailto:` 均被拦截。
  - SSL：`self-signed.badssl.com` 弹层 → “继续访问” → `ssl error 3` → `ssl confirmed by user` → `pageEnd 236ms`；`expired.badssl.com`（`ssl error 2`）同样可继续。
  - 深色：三档日志 `web dark mode auto/on/off`；`开启` 时 example.com 白底反转为深底浅字，`关闭` 恢复白底。
- 已知限制（平台）：
  - `DocumentViewPicker` 返回的 `file://docs/...` 在本镜像上普通应用读不了（`13900001`；nweb `MediaLibrary Extension:{OpenFile} Permission Denied err=-13`），通用文件上传只能“尽力传原 URI”，本机必然 0 B。
  - `fileShare.persistPermission` 返回 `801 The device doesn't support this api`；提权无收益，已回退 `apl: normal` / `allowed-acls: []`，`module.json5` 只保留 `INTERNET` + `GET_NETWORK_INFO`。

## 2026-11-23 M6：混合内容 / 清数据 / release 验收

- 混合内容：`mixedMode(allowMixed ? MixedMode.Compatible : MixedMode.None)`，面板 Toggle 持久化 `allowMixed`。
  - `https://mixed.badssl.com/`：**开** → 页面中部 HTTP 图片正常显示；**关** → 同位置破图 + “HTTP image” alt 文案。截图 `build-artifacts/mix-on.jpeg` / `mix-off.jpeg`。
- 清数据：`removeCache(true)` + `WebStorage.deleteAllData()` + `WebCookieManager.clearAllCookies()`；日志 `browsing data cleared`；面板书签/历史条数不变（书签 0 / 历史 4），preferences 未被误删。
- 站点抽样（release 包，手机 UA）：
  - `example.com` 冷加载 1171ms；深色开/关对比正常。
  - `cn.bing.com` 361ms，首页完整（横幅、搜索框、资讯流）。
  - `www.baidu.com` 724~1003ms，完整；站内 `baiduboxapp://` 被拦截。
  - `music.163.com` 604~705ms，移动版结构/文字正常（封面图为懒加载占位）。
  - `github.com` 无代理时 10s 内未完成（设备直连不可达），停留在上一页；属网络环境限制，无崩溃。
- 内存（单标签 `music.163.com`，`hidumper --mem`）：应用进程 PSS 112,182 kB + 渲染进程 PSS 103,046 kB = **215,228 kB ≈ 210 MiB**，满足 M6 “单标签 RSS ≤300 MiB”。
- release 构建与安装：
  - `bash scripts/build.sh --release` → unsigned **1,020,310 bytes**；`bash scripts/sign.sh` → signed **1,025,842 bytes**。
  - 覆盖安装报 `9568336 install debug type not same`（debug → release），按预期卸载重装；`bm dump` 显示 `"debug": false`；冷启动首页 `pageEnd 39ms`，无崩溃日志。
  - 卸载重装会清空沙盒，本次验收时已无书签/历史（此前仅测试数据）。
- 脚本修正：
  - `deploy.sh` 原只看 hdc 退出码，hdc 在 `msg:error:` 时仍返回 0，覆盖安装失败会被误报成功；现解析输出中的 `msg:error:`，失败才卸载重装。
  - `make-signing-material.sh` 支持可选 `OHOS_APP_APL` / `OHOS_ACLS`（默认 `normal` / 空），本次未启用提权。
- 产物：`build-artifacts/`（`entry-signed.hap`、`entry-unsigned.hap`、`mix-on/off.jpeg`、`dark-on/off.jpeg`、`clear1/2.jpeg`、`site-*.jpeg`）。
- 结论：M5/M6 功能项全部实机通过；剩余限制为文档 URI 权限与 `persistPermission 801`（平台侧），以及无代理环境下 GitHub 不可达。
