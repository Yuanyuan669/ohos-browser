import webview from '@ohos.web.webview';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import { BusinessError } from '@ohos.base';
import Want from '@ohos.app.ability.Want';
import { Log } from '../common/Logger';

interface PageEvent {
  url: string;
}

interface ProgressEvent {
  newProgress: number;
}

interface TitleEvent {
  title: string;
}

interface ErrorEvent {
  request: WebResourceRequest;
  error: WebResourceError;
}

interface WindowNewEvent {
  isAlert: boolean;
  isUserTrigger: boolean;
  targetUrl: string;
  handler: ControllerHandler;
}

interface FileSelectorEvent {
  result: FileSelectorResult;
  fileSelector: FileSelectorParam;
}

interface SslErrorEvent {
  handler: SslErrorHandler;
  error: SslError;
}

interface LoadInterceptEvent {
  data: WebResourceRequest;
}

interface TabInfo {
  url: string;
  title: string;
}

interface LinkItem {
  url: string;
  title: string;
  time: number;
}

interface DownloadRow {
  guid: string;
  name: string;
  url: string;
  path: string;
  mime: string;
  state: number;
  percent: number;
  received: number;
  total: number;
  speed: number;
}

const HOME_URL: string = 'resource://rawfile/home.html';
const MAX_TABS: number = 3;
const MAX_HISTORY: number = 100;
const UA_MOBILE: string = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const UA_DESKTOP: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const IMAGE_EXTENSIONS: string[] = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg', '.svgz', '.ico',
  '.heic', '.heif', '.avif', '.apng', '.jfif', '.pjpeg', '.pjp', '.tif', '.tiff', '.xbm'];
const VIDEO_EXTENSIONS: string[] = ['.mp4', '.m4v', '.mov', '.mkv', '.webm', '.avi', '.3gp', '.3g2', '.ts', '.flv'];

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State tabs: TabInfo[] = [{ url: '', title: '主页' }];
  @State active: number = 0;
  @State address: string = '';
  @State title: string = '浏览器';
  @State status: string = '就绪';
  @State progress: number = 0;
  @State errText: string = '';
  @State loading: boolean = false;
  @State canBack: boolean = false;
  @State canForward: boolean = false;
  private pageStart: number = 0;
  private pendingUrl: string = '';
  private prefs: preferences.Preferences | null = null;
  @State webNonce: number = 0;
  @State webSrc: string = '';
  @State bookmarks: LinkItem[] = [];
  @State history: LinkItem[] = [];
  @State downloads: DownloadRow[] = [];
  @State downloadNonce: number = 0;
  @State panelMode: string = '';
  @State uaMode: string = 'mobile';
  @State showDebug: boolean = false;
  @State darkMode: string = 'off';
  @State allowMixed: boolean = false;
  @State sslText: string = '';
  private sslHandler: SslErrorHandler | null = null;
  private uploadPending: boolean = false;
  private downloadDelegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private downloadItems: Map<string, webview.WebDownloadItem> = new Map();
  private downloadReady: boolean = false;
  private progressTimer: number = -1;

  aboutToAppear(): void {
    this.initDownloadDelegate();
    const su: string | undefined = AppStorage.get<string>('startUrl');
    if (su !== undefined && su.length > 0) {
      this.pendingUrl = su;
      this.address = su;
    }
    this.loadSession();
  }

  private async loadSession(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      this.prefs = await preferences.getPreferences(ctx, 'browser');
      const raw = await this.prefs.get('tabs', '') as string;
      if (raw.length > 2) {
        const arr = JSON.parse(raw) as TabInfo[];
        if (arr.length > 0) {
          this.tabs = arr.slice(0, MAX_TABS);
        }
      }
      const a = await this.prefs.get('active', 0) as number;
      this.active = a >= 0 && a < this.tabs.length ? a : 0;
      this.bookmarks = this.decodeLinks(await this.prefs.get('bookmarks', '') as string);
      this.history = this.decodeLinks(await this.prefs.get('history', '') as string);
      const ua = await this.prefs.get('uaMode', 'mobile') as string;
      this.uaMode = ua === 'desktop' ? 'desktop' : 'mobile';
      const dbg = await this.prefs.get('showDebug', false) as boolean;
      this.showDebug = dbg === true;
      const dm = await this.prefs.get('darkMode', 'off') as string;
      this.darkMode = dm === 'on' || dm === 'auto' ? dm : 'off';
      const mix = await this.prefs.get('allowMixed', false) as boolean;
      this.allowMixed = mix === true;
      this.applyUserAgent();
      const t = this.tabs[this.active];
      this.title = t.title;
      this.address = t.url;
      if (this.pendingUrl.length === 0 && t.url.length > 0) {
        this.pendingUrl = t.url;
      }
      Log.info('session restored ' + this.tabs.length + ' tabs, ' +
        this.bookmarks.length + ' bookmarks, ' + this.history.length + ' history');
    } catch (e) {
      Log.warn('session load failed');
    }
  }

  private decodeLinks(raw: string): LinkItem[] {
    const out: LinkItem[] = [];
    if (raw.length < 3) {
      return out;
    }
    try {
      const arr = JSON.parse(raw) as LinkItem[];
      for (let i = 0; i < arr.length; i++) {
        const it = arr[i];
        if (it !== undefined && typeof it.url === 'string' && it.url.length > 0) {
          out.push({
            url: it.url,
            title: typeof it.title === 'string' && it.title.length > 0 ? it.title : it.url,
            time: typeof it.time === 'number' ? it.time : 0
          });
        }
      }
    } catch (e) {
      Log.warn('links decode failed');
    }
    return out;
  }

  private savePref(key: string, value: string | number | boolean): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.put(key, value).catch((e: Error) => {
      Log.warn('pref put failed ' + key + ' ' + e.message);
    });
    this.prefs.flush().catch((e: Error) => {
      Log.warn('pref flush failed ' + key + ' ' + e.message);
    });
  }

  private saveLinks(key: string, items: LinkItem[]): void {
    this.savePref(key, JSON.stringify(items));
  }

  private applyUserAgent(): void {
    try {
      this.controller.setCustomUserAgent(this.uaMode === 'desktop' ? UA_DESKTOP : UA_MOBILE);
    } catch (e) {
      Log.warn('ua apply failed ' + this.uaMode);
    }
  }

  private toggleUa(): void {
    this.uaMode = this.uaMode === 'desktop' ? 'mobile' : 'desktop';
    this.savePref('uaMode', this.uaMode);
    this.applyUserAgent();
    const url = this.currentHttpUrl();
    this.load(url);
    this.status = this.uaMode === 'desktop' ? '电脑版 UA' : '手机版 UA';
    Log.info('ua mode ' + this.uaMode);
  }

  private setShowDebug(on: boolean): void {
    this.showDebug = on;
    this.savePref('showDebug', on);
  }

  private darkModeValue(): WebDarkMode {
    if (this.darkMode === 'on') {
      return WebDarkMode.On;
    }
    if (this.darkMode === 'auto') {
      return WebDarkMode.Auto;
    }
    return WebDarkMode.Off;
  }

  private darkModeLabel(): string {
    if (this.darkMode === 'on') {
      return '开启';
    }
    if (this.darkMode === 'auto') {
      return '跟随系统';
    }
    return '关闭';
  }

  private cycleDarkMode(): void {
    if (this.darkMode === 'off') {
      this.darkMode = 'auto';
    } else if (this.darkMode === 'auto') {
      this.darkMode = 'on';
    } else {
      this.darkMode = 'off';
    }
    this.savePref('darkMode', this.darkMode);
    this.status = '网页深色：' + this.darkModeLabel();
    Log.info('web dark mode ' + this.darkMode);
  }

  private mixedModeValue(): MixedMode {
    return this.allowMixed ? MixedMode.Compatible : MixedMode.None;
  }

  private setAllowMixed(on: boolean): void {
    this.allowMixed = on;
    this.savePref('allowMixed', on);
    this.status = on ? '允许 HTTPS 页面加载 HTTP 内容' : '禁止混合内容';
  }

  private clearBrowsingData(): void {
    try {
      this.controller.removeCache(true);
    } catch (e) {
      Log.warn('removeCache failed');
    }
    try {
      webview.WebStorage.deleteAllData();
    } catch (e) {
      Log.warn('deleteAllData failed');
    }
    try {
      webview.WebCookieManager.clearAllCookies().catch((e: Error) => {
        Log.warn('clearAllCookies failed ' + e.message);
      });
    } catch (e) {
      Log.warn('clearAllCookies call failed');
    }
    this.status = '已清除缓存、Cookie 与站点数据';
    Log.info('browsing data cleared');
  }

  private isWebScheme(url: string): boolean {
    const lower = url.toLowerCase();
    return lower.indexOf('http://') === 0 ||
      lower.indexOf('https://') === 0 ||
      lower.indexOf('resource://') === 0 ||
      lower.indexOf('file://') === 0 ||
      lower.indexOf('about:') === 0 ||
      lower.indexOf('data:') === 0 ||
      lower.indexOf('blob:') === 0 ||
      lower.indexOf('javascript:') === 0;
  }

  private blockForeignScheme(event?: LoadInterceptEvent): boolean {
    if (event === undefined) {
      return false;
    }
    try {
      if (!event.data.isMainFrame()) {
        return false;
      }
      const url = event.data.getRequestUrl();
      if (url.length === 0 || this.isWebScheme(url)) {
        return false;
      }
      this.status = '已拦截外部协议';
      Log.warn('blocked scheme ' + url.substring(0, 80));
      return true;
    } catch (e) {
      return false;
    }
  }

  private openNewWindow(event?: WindowNewEvent): void {
    if (event === undefined) {
      return;
    }
    const url = event.targetUrl;
    Log.info('windowNew url=' + url + ' alert=' + event.isAlert);
    if (url.length === 0) {
      this.status = '已拦截空白弹窗';
      return;
    }
    if (this.tabs.length >= MAX_TABS) {
      this.address = url;
      this.title = '新窗口';
      this.load(url);
      this.status = '新窗口已载入当前标签';
    } else {
      this.openInNewTab(url);
      this.status = '新窗口已在新标签打开';
    }
  }

  private openInNewTab(url: string): void {
    this.persistCurrent();
    this.tabs.push({ url: url, title: '新标签' });
    this.active = this.tabs.length - 1;
    this.address = url;
    this.title = '新标签';
    this.resetWeb(url);
    this.saveSession();
  }

  private beginUpload(event?: FileSelectorEvent): boolean {
    if (event === undefined) {
      return false;
    }
    if (this.uploadPending) {
      this.status = '已有文件选择窗口';
      return true;
    }
    const multiple = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode;
    const accept = event.fileSelector.getAcceptType();
    const result = event.result;
    this.uploadPending = true;
    this.status = '请选择要上传的文件';
    Log.info('fileSelector accept=[' + accept.join(',') + '] mode=' + event.fileSelector.getMode());
    try {
      const media = this.isMediaAccept(accept);
      if (media !== 0) {
        const photoOptions: picker.PhotoSelectOptions = {
          MIMEType: media === 1 ? picker.PhotoViewMIMETypes.VIDEO_TYPE : picker.PhotoViewMIMETypes.IMAGE_TYPE,
          maxSelectNumber: multiple ? 8 : 1
        };
        const pv = new picker.PhotoViewPicker();
        pv.select(photoOptions).then((res: picker.PhotoSelectResult) => {
          this.uploadPending = false;
          this.finishUpload(result, res.photoUris);
        }).catch((e: Error) => {
          this.uploadPending = false;
          this.cancelUpload(result, e);
        });
      } else {
        const options: picker.DocumentSelectOptions = {
          maxSelectNumber: multiple ? 8 : 1
        };
        const dp = new picker.DocumentViewPicker();
        dp.select(options).then((uris: string[]) => {
          this.uploadPending = false;
          this.finishUpload(result, uris);
        }).catch((e: Error) => {
          this.uploadPending = false;
          this.cancelUpload(result, e);
        });
      }
    } catch (e) {
      this.uploadPending = false;
      this.status = '无法打开文件选择器';
      return false;
    }
    return true;
  }

  // nweb turns accept="image/*" into an extension list (".png,.jpg,..."), so match both.
  // 0 = not media (use document picker), 1 = video, 2 = image.
  private isMediaAccept(accept: string[]): number {
    if (accept === undefined || accept.length === 0) {
      return 0;
    }
    let image = false;
    let video = false;
    for (let i = 0; i < accept.length; i++) {
      const a = accept[i].toLowerCase();
      if (a.indexOf('image') >= 0) {
        image = true;
      } else if (a.indexOf('video') >= 0) {
        video = true;
      } else if (a.charAt(0) === '.') {
        if (IMAGE_EXTENSIONS.indexOf(a) >= 0) {
          image = true;
        } else if (VIDEO_EXTENSIONS.indexOf(a) >= 0) {
          video = true;
        }
      }
    }
    if (image) {
      return 2;
    }
    return video ? 1 : 0;
  }

  private finishUpload(result: FileSelectorResult, uris: string[]): void {
    try {
      if (uris !== undefined && uris.length > 0) {
        const local = this.localizeUploadUris(uris);
        result.handleFileList(local);
        this.status = '已选择 ' + uris.length + ' 个文件';
        Log.info('upload files ' + uris.length);
      } else {
        result.handleFileList([]);
        this.status = '未选择文件';
      }
    } catch (e) {
      this.status = '上传选择结果失败';
    }
  }

  private cancelUpload(result: FileSelectorResult, e: Error): void {
    try {
      result.handleFileList([]);
    } catch (e2) {
    }
    this.status = '已取消上传';
    Log.warn('upload picker cancelled ' + e.message);
  }

  private localizeUploadUris(uris: string[]): string[] {
    const out: string[] = [];
    let dir = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      dir = ctx.getApplicationContext().filesDir + '/upload';
    } catch (e) {
      const err = e as BusinessError;
      Log.warn('upload dir unresolved code=' + err.code + ' msg=' + err.message);
      return uris;
    }
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      // 13900015 = EEXIST: the cache dir is already there, keep going.
      const err = e as BusinessError;
      if (err.code !== 13900015) {
        Log.warn('upload cache dir failed ' + dir + ' code=' + err.code + ' msg=' + err.message);
        return uris;
      }
    }
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      // nweb can open media URIs directly, keep them (the app may only get a one-shot grant).
      if (uri.indexOf('file://media/') === 0) {
        out.push(uri);
        Log.info('upload pass-through media uri=' + uri);
        continue;
      }
      let name = uri.substring(uri.lastIndexOf('/') + 1);
      const q = name.indexOf('?');
      if (q >= 0) {
        name = name.substring(0, q);
      }
      let safe = '';
      for (let j = 0; j < name.length; j++) {
        const ch = name.charAt(j);
        if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?' ||
          ch === '"' || ch === '<' || ch === '>' || ch === '|' || ch.charCodeAt(0) < 32) {
          safe += '_';
        } else {
          safe += ch;
        }
      }
      if (safe.length === 0) {
        safe = 'upload.bin';
      }
      const dest = dir + '/' + i.toString() + '_' + safe;
      try {
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        fs.copyFileSync(src.fd, dest);
        fs.closeSync(src);
        const size = fs.statSync(dest).size;
        const destUri = fileUri.getUriFromPath(dest);
        out.push(dest);
        Log.info('upload localized ' + safe + ' ' + size + ' bytes uri=' + destUri);
      } catch (e) {
        const err = e as BusinessError;
        out.push(uri);
        Log.warn('upload localize failed ' + safe + ' uri=' + uri + ' code=' + err.code + ' msg=' + err.message);
      }
    }
    return out;
  }

  private sslErrorLabel(code: SslError): string {
    if (code === SslError.HostMismatch) {
      return '证书域名不匹配';
    }
    if (code === SslError.DateInvalid) {
      return '证书未生效或已过期';
    }
    if (code === SslError.Untrusted) {
      return '证书不受信任';
    }
    return '证书错误';
  }

  private onSslError(event?: SslErrorEvent): void {
    if (event === undefined) {
      return;
    }
    this.sslHandler = event.handler;
    this.sslText = this.sslErrorLabel(event.error);
    Log.warn('ssl error ' + event.error.toString());
  }

  private confirmSsl(accept: boolean): void {
    const handler = this.sslHandler;
    this.sslHandler = null;
    this.sslText = '';
    if (handler === null) {
      return;
    }
    try {
      if (accept) {
        handler.handleConfirm();
        this.status = '已继续访问（证书不受信任）';
        Log.warn('ssl confirmed by user');
      } else {
        handler.handleCancel();
        this.status = '已取消不受信任的证书';
      }
    } catch (e) {
      Log.warn('ssl handler failed');
    }
  }

  private initDownloadDelegate(): void {
    if (this.downloadReady) {
      return;
    }
    this.downloadReady = true;
    this.downloadDelegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      this.beginDownload(item);
    });
    this.downloadDelegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      this.downloadItems.set(item.getGuid(), item);
      this.syncDownload(item);
    });
    this.downloadDelegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.downloadItems.set(item.getGuid(), item);
      this.finalizeDownload(item);
      this.syncDownload(item);
      this.status = '下载完成 ' + item.getSuggestedFileName();
    });
    this.downloadDelegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.syncDownload(item);
      this.status = '下载失败 ' + item.getSuggestedFileName();
    });
  }

  private downloadDir(): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    return ctx.getApplicationContext().filesDir + '/downloads';
  }

  private safeFileName(suggested: string, url: string): string {
    let name = suggested.trim();
    if (name.length === 0) {
      const q = url.indexOf('?');
      const clean = q >= 0 ? url.substring(0, q) : url;
      const slash = clean.lastIndexOf('/');
      name = slash >= 0 ? clean.substring(slash + 1) : 'download';
    }
    let out = '';
    for (let i = 0; i < name.length; i++) {
      const ch = name.charAt(i);
      if (ch === '\\' || ch === '/' || ch === ':' || ch === '*' || ch === '?' ||
        ch === '"' || ch === '<' || ch === '>' || ch === '|' || ch.charCodeAt(0) < 32) {
        out += '_';
      } else {
        out += ch;
      }
    }
    name = out.trim();
    if (name.length === 0) {
      name = 'download';
    }
    if (name.length > 100) {
      name = name.substring(name.length - 100);
    }
    return name;
  }

  private uniqueDownloadPath(name: string): string {
    const dir = this.downloadDir();
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      Log.warn('download mkdir failed ' + dir);
    }
    const dot = name.lastIndexOf('.');
    const stem = dot > 0 ? name.substring(0, dot) : name;
    const ext = dot > 0 ? name.substring(dot) : '';
    let candidate = name;
    let n = 1;
    while (n < 100) {
      if (!fs.accessSync(dir + '/' + candidate)) {
        break;
      }
      candidate = stem + '_' + n + ext;
      n++;
    }
    return dir + '/' + candidate;
  }

  private beginDownload(item: webview.WebDownloadItem): void {
    const guid = item.getGuid();
    if (this.downloadItems.has(guid)) {
      return;
    }
    const name = this.safeFileName(item.getSuggestedFileName(), item.getUrl());
    const path = this.uniqueDownloadPath(name);
    let total = -1;
    let mime = '';
    let url = '';
    try {
      total = item.getTotalBytes();
      mime = item.getMimeType();
      url = item.getUrl();
    } catch (e) {
    }
    this.downloadItems.set(guid, item);
    this.downloads.unshift({
      guid: guid, name: name, url: url, path: path, mime: mime,
      state: webview.WebDownloadState.PENDING,
      percent: 0, received: 0, total: total, speed: 0
    });
    this.downloads = this.downloads.slice(0, this.downloads.length);
    this.panelMode = 'downloads';
    this.startProgressTimer();
    try {
      item.start(path);
      this.status = '开始下载 ' + name;
      Log.info('download start ' + path);
    } catch (e) {
      this.updateDownloadState(guid, webview.WebDownloadState.INTERRUPTED);
      this.status = '下载启动失败';
      Log.warn('download start failed');
    }
  }

  private startProgressTimer(): void {
    if (this.progressTimer >= 0) {
      return;
    }
    this.progressTimer = setInterval(() => {
      let active = 0;
      for (let i = 0; i < this.downloads.length; i++) {
        const row = this.downloads[i];
        if (row.state === webview.WebDownloadState.IN_PROGRESS ||
          row.state === webview.WebDownloadState.PENDING) {
          active++;
          const item = this.downloadItems.get(row.guid);
          if (item !== undefined) {
            this.syncDownload(item);
          }
          try {
            const stat = fs.statSync(row.path);
            if (stat.size > 0) {
              row.received = stat.size;
              row.state = webview.WebDownloadState.IN_PROGRESS;
              if (row.total > 0) {
                row.percent = Math.min(100, Math.floor(stat.size * 100 / row.total));
              }
            }
          } catch (e) {
          }
        }
      }
      this.downloads = this.downloads.slice(0, this.downloads.length);
      this.downloadNonce++;
      if (active === 0) {
        clearInterval(this.progressTimer);
        this.progressTimer = -1;
      }
    }, 500);
  }

  private downloadIndex(guid: string): number {
    for (let i = 0; i < this.downloads.length; i++) {
      if (this.downloads[i].guid === guid) {
        return i;
      }
    }
    return -1;
  }

  private updateDownloadState(guid: string, state: number): void {
    const idx = this.downloadIndex(guid);
    if (idx >= 0) {
      this.downloads[idx].state = state;
      this.downloads = this.downloads.slice(0, this.downloads.length);
      this.downloadNonce++;
    }
  }

  private syncDownload(item: webview.WebDownloadItem): void {
    const guid = item.getGuid();
    const idx = this.downloadIndex(guid);
    if (idx < 0) {
      return;
    }
    try {
      const row = this.downloads[idx];
      row.state = item.getState();
      const p = item.getPercentComplete();
      row.percent = p < 0 ? 0 : p;
      row.received = item.getReceivedBytes();
      row.total = item.getTotalBytes();
      row.speed = item.getCurrentSpeed();
      this.downloads = this.downloads.slice(0, this.downloads.length);
      this.downloadNonce++;
    } catch (e) {
      Log.warn('download sync failed');
    }
  }

  private finalizeDownload(item: webview.WebDownloadItem): void {
    const idx = this.downloadIndex(item.getGuid());
    if (idx < 0) {
      return;
    }
    const row = this.downloads[idx];
    let source = '';
    try {
      source = item.getFullPath();
    } catch (e) {
      return;
    }
    if (source.length === 0 || source === row.path) {
      return;
    }
    try {
      fs.mkdirSync(this.downloadDir(), true);
      fs.copyFileSync(source, row.path);
      Log.info('download copied ' + source + ' -> ' + row.path);
    } catch (e) {
      row.path = source;
      Log.warn('download copy failed ' + source);
    }
  }

  private pauseDownload(row: DownloadRow): void {
    const item = this.downloadItems.get(row.guid);
    if (item === undefined) {
      return;
    }
    try {
      item.pause();
      this.updateDownloadState(row.guid, webview.WebDownloadState.PAUSED);
      this.status = '已暂停 ' + row.name;
    } catch (e) {
      this.status = '暂停失败';
    }
  }

  private resumeDownload(row: DownloadRow): void {
    const item = this.downloadItems.get(row.guid);
    if (item === undefined) {
      return;
    }
    try {
      item.resume();
      this.updateDownloadState(row.guid, webview.WebDownloadState.IN_PROGRESS);
      this.startProgressTimer();
      this.status = '继续下载 ' + row.name;
    } catch (e) {
      try {
        webview.WebDownloadManager.resumeDownload(item);
        this.status = '继续下载 ' + row.name;
      } catch (e2) {
        this.status = '继续失败';
      }
    }
  }

  private cancelDownload(row: DownloadRow): void {
    const item = this.downloadItems.get(row.guid);
    if (item === undefined) {
      return;
    }
    try {
      item.cancel();
      this.updateDownloadState(row.guid, webview.WebDownloadState.CANCELED);
      this.status = '已取消 ' + row.name;
    } catch (e) {
      this.status = '取消失败';
    }
  }

  private openDownload(row: DownloadRow): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileUri.getUriFromPath(row.path),
        type: row.mime.length > 0 ? row.mime : '*/*'
      };
      ctx.startAbility(want);
    } catch (e) {
      this.status = '无法打开文件';
      Log.warn('open download failed');
    }
  }

  private clearDownloads(): void {
    const keep: DownloadRow[] = [];
    for (let i = 0; i < this.downloads.length; i++) {
      const state = this.downloads[i].state;
      if (state === webview.WebDownloadState.IN_PROGRESS ||
        state === webview.WebDownloadState.PENDING ||
        state === webview.WebDownloadState.PAUSED) {
        keep.push(this.downloads[i]);
      }
    }
    this.downloads = keep;
  }

  private formatSize(bytes: number): string {
    if (bytes < 0) {
      return '未知大小';
    }
    if (bytes < 1024) {
      return bytes.toString() + ' B';
    }
    if (bytes < 1024 * 1024) {
      return Math.round(bytes / 1024).toString() + ' KB';
    }
    return (Math.round(bytes / (1024 * 1024) * 10) / 10).toString() + ' MB';
  }

  private downloadStateText(row: DownloadRow): string {
    if (row.state === webview.WebDownloadState.COMPLETED) {
      return '已完成 · ' + this.formatSize(row.total);
    }
    if (row.state === webview.WebDownloadState.PAUSED) {
      return '已暂停 · ' + Math.round(row.percent).toString() + '%';
    }
    if (row.state === webview.WebDownloadState.CANCELED) {
      return '已取消';
    }
    if (row.state === webview.WebDownloadState.INTERRUPTED) {
      return '下载失败';
    }
    if (row.state === webview.WebDownloadState.PENDING) {
      return '等待中';
    }
    return '下载中 ' + Math.round(row.percent).toString() + '% · ' +
      this.formatSize(row.received) + ' / ' + this.formatSize(row.total);
  }

  private tabWidth(): number {
    const n = this.tabs.length;
    if (n <= 1) {
      return 110;
    }
    return Math.max(58, Math.floor((226 - (n - 1) * 6) / n));
  }

  private saveSession(): void {
    this.savePref('tabs', JSON.stringify(this.tabs));
    this.savePref('active', this.active);
  }

  private currentHttpUrl(): string {
    if (this.address.indexOf('http://') === 0 || this.address.indexOf('https://') === 0) {
      return this.address;
    }
    const u = this.activeTabUrl();
    if (u.indexOf('http://') === 0 || u.indexOf('https://') === 0) {
      return u;
    }
    return '';
  }

  private linkIndex(items: LinkItem[], url: string): number {
    for (let i = 0; i < items.length; i++) {
      if (items[i].url === url) {
        return i;
      }
    }
    return -1;
  }

  private isBookmarked(): boolean {
    const url = this.currentHttpUrl();
    return url.length > 0 && this.linkIndex(this.bookmarks, url) >= 0;
  }

  private toggleBookmark(): void {
    const url = this.currentHttpUrl();
    if (url.length === 0) {
      this.status = '当前页不能收藏';
      return;
    }
    const idx = this.linkIndex(this.bookmarks, url);
    if (idx >= 0) {
      this.bookmarks.splice(idx, 1);
      this.bookmarks = this.bookmarks.slice(0, this.bookmarks.length);
      this.status = '已取消收藏';
    } else {
      const title = this.title.length > 0 && this.title !== '浏览器' ? this.title : url;
      this.bookmarks.unshift({ url: url, title: title, time: Date.now() });
      this.bookmarks = this.bookmarks.slice(0, this.bookmarks.length);
      this.status = '已收藏';
    }
    this.saveLinks('bookmarks', this.bookmarks);
  }

  private recordHistory(url: string, title: string): void {
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return;
    }
    const idx = this.linkIndex(this.history, url);
    if (idx >= 0) {
      this.history.splice(idx, 1);
    }
    this.history.unshift({
      url: url,
      title: title.length > 0 ? title : url,
      time: Date.now()
    });
    if (this.history.length > MAX_HISTORY) {
      this.history.splice(MAX_HISTORY, this.history.length - MAX_HISTORY);
    }
    this.history = this.history.slice(0, this.history.length);
    this.saveLinks('history', this.history);
  }

  private openLink(item: LinkItem): void {
    this.panelMode = '';
    this.address = item.url;
    this.load(item.url);
  }

  private deleteLink(index: number): void {
    if (this.panelMode === 'bookmarks') {
      this.bookmarks.splice(index, 1);
      this.bookmarks = this.bookmarks.slice(0, this.bookmarks.length);
      this.saveLinks('bookmarks', this.bookmarks);
    } else if (this.panelMode === 'history') {
      this.history.splice(index, 1);
      this.history = this.history.slice(0, this.history.length);
      this.saveLinks('history', this.history);
    }
  }

  private clearPanel(): void {
    if (this.panelMode === 'bookmarks') {
      this.bookmarks = [];
      this.saveLinks('bookmarks', this.bookmarks);
      this.status = '书签已清空';
    } else if (this.panelMode === 'history') {
      this.history = [];
      this.saveLinks('history', this.history);
      this.status = '历史已清空';
    } else if (this.panelMode === 'downloads') {
      this.clearDownloads();
      this.status = '已清理下载记录';
    }
  }

  private panelItems(): LinkItem[] {
    if (this.panelMode === 'bookmarks') {
      return this.bookmarks;
    }
    if (this.panelMode === 'history') {
      return this.history;
    }
    return [];
  }

  private touch(): void {
    this.tabs = this.tabs.slice(0, this.tabs.length);
  }

  private activeTabUrl(): string {
    if (this.active < 0 || this.active >= this.tabs.length) {
      return '';
    }
    return this.tabs[this.active].url;
  }

  private resetWeb(url: string): void {
    this.pendingUrl = '';
    this.webSrc = url;
    this.controller = new webview.WebviewController();
    this.webNonce++;
  }

  private load(url: string): void {
    this.errText = '';
    try {
      if (url.length > 0) {
        this.controller.loadUrl(url);
      } else {
        this.controller.loadUrl(HOME_URL);
      }
    } catch (e) {
      this.status = '打开失败';
    }
  }

  private persistCurrent(): void {
    if (this.active < 0 || this.active >= this.tabs.length) {
      return;
    }
    if (this.address.indexOf('http') === 0) {
      this.tabs[this.active].url = this.address;
    }
    this.tabs[this.active].title = this.title;
    this.touch();
  }

  private switchTab(i: number): void {
    if (i === this.active || i < 0 || i >= this.tabs.length) {
      return;
    }
    this.persistCurrent();
    this.active = i;
    const t = this.tabs[i];
    this.address = t.url;
    this.title = t.title;
    this.resetWeb(t.url);
    this.saveSession();
  }

  private newTab(): void {
    if (this.tabs.length >= MAX_TABS) {
      this.status = '最多 3 个标签';
      return;
    }
    this.persistCurrent();
    this.tabs.push({ url: '', title: '新标签' });
    this.active = this.tabs.length - 1;
    this.address = '';
    this.title = '新标签';
    this.resetWeb('');
    this.saveSession();
  }

  private closeTab(): void {
    if (this.tabs.length <= 1) {
      this.tabs = [{ url: '', title: '主页' }];
      this.active = 0;
      this.address = '';
      this.title = '主页';
      this.resetWeb('');
      this.saveSession();
      return;
    }
    this.tabs.splice(this.active, 1);
    if (this.active >= this.tabs.length) {
      this.active = this.tabs.length - 1;
    }
    const t = this.tabs[this.active];
    this.address = t.url;
    this.title = t.title;
    this.resetWeb(t.url);
    this.saveSession();
  }

  private normalize(input: string): string {
    const s = input.trim();
    if (s.length === 0) {
      return '';
    }
    if (s.indexOf('http://') === 0 || s.indexOf('https://') === 0) {
      return s;
    }
    const first = s.charAt(0);
    const c0 = first >= '0' && first <= '9';
    if (c0 || s.indexOf('localhost') === 0 || first === '[') {
      return 'http://' + s;
    }
    const colon = s.indexOf(':');
    const slash = s.indexOf('/');
    if (colon > 0 && (slash < 0 || colon < slash)) {
      return 'http://' + s;
    }
    return 'https://' + s;
  }

  private openAddress(): void {
    const url = this.normalize(this.address);
    if (url.length === 0) {
      return;
    }
    this.address = url;
    this.load(url);
  }

  private goHome(): void {
    this.address = '';
    this.title = '主页';
    if (this.active >= 0 && this.active < this.tabs.length) {
      this.tabs[this.active].url = '';
      this.tabs[this.active].title = '主页';
      this.touch();
      this.saveSession();
    }
    this.load('');
  }

  private updateNav(): void {
    try {
      this.canBack = this.controller.accessBackward();
      this.canForward = this.controller.accessForward();
    } catch (e) {
      this.canBack = false;
      this.canForward = false;
    }
  }

  private refreshOrStop(): void {
    try {
      if (this.loading) {
        this.controller.stop();
        this.loading = false;
        this.status = '已停止';
      } else {
        this.controller.refresh();
      }
    } catch (e) {
      Log.warn('refresh failed');
    }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        ForEach(this.tabs, (t: TabInfo, i: number) => {
          Row({ space: 4 }) {
            Text(t.title.length > 0 ? t.title : '新标签')
              .fontSize(10)
              .fontColor(i === this.active ? '#E8F0FB' : '#8295AD')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width(this.tabWidth())
          .height(30)
          .padding({ left: 8, right: 8 })
          .backgroundColor(i === this.active ? '#1E2B40' : '#111720')
          .borderRadius(8)
          .onClick(() => {
            this.switchTab(i);
          })
        }, (t: TabInfo, i: number) => i.toString() + t.url + t.title)
        Blank()
        Button('+')
          .height(30)
          .width(42)
          .fontSize(16)
          .backgroundColor('#151D29')
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.newTab();
          })
        Button('关')
          .height(30)
          .width(46)
          .fontSize(11)
          .backgroundColor('#151D29')
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.closeTab();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.address, placeholder: '输入网址或搜索' })
          .height(40)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor('#E8F0FB')
          .placeholderColor('#6C7C93')
          .backgroundColor('#151D29')
          .borderRadius(9)
          .onChange((v: string) => {
            this.address = v;
          })
          .onSubmit(() => {
            this.openAddress();
          })
        Button(this.isBookmarked() ? '★' : '☆')
          .height(40)
          .width(44)
          .fontSize(21)
          .padding(0)
          .backgroundColor('#151D29')
          .borderRadius(9)
          .fontColor(this.isBookmarked() ? '#FFD166' : '#9FB2CC')
          .onClick(() => {
            this.toggleBookmark();
          })
        Button('打开')
          .height(40)
          .width(58)
          .fontSize(13)
          .padding(0)
          .backgroundColor('#3D7BFF')
          .onClick(() => {
            this.openAddress();
          })
      }
      .width('100%')

      Row({ space: 3 }) {
        Button('←')
          .height(32)
          .layoutWeight(1)
          .padding(0)
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .fontColor(this.canBack ? '#DCE7F7' : '#4A586B')
          .enabled(this.canBack)
          .onClick(() => {
            if (this.canBack) {
              this.controller.backward();
            }
          })
        Button('→')
          .height(32)
          .layoutWeight(1)
          .padding(0)
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .fontColor(this.canForward ? '#DCE7F7' : '#4A586B')
          .enabled(this.canForward)
          .onClick(() => {
            if (this.canForward) {
              this.controller.forward();
            }
          })
        Button(this.loading ? '停止' : '刷新')
          .height(32)
          .layoutWeight(1)
          .padding(0)
          .fontSize(11)
          .backgroundColor(Color.Transparent)
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.refreshOrStop();
          })
        Button('主页')
          .height(32)
          .layoutWeight(1)
          .padding(0)
          .fontSize(11)
          .backgroundColor(Color.Transparent)
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.goHome();
          })
        Button('书签')
          .height(32)
          .layoutWeight(1)
          .padding(0)
          .fontSize(11)
          .backgroundColor(this.panelMode.length > 0 ? '#263A57' : Color.Transparent)
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.panelMode = this.panelMode.length > 0 ? '' : 'bookmarks';
          })
        Button(this.uaMode === 'desktop' ? '电脑UA' : '手机UA')
          .height(32)
          .layoutWeight(1)
          .padding(0)
          .fontSize(10)
          .backgroundColor(this.uaMode === 'desktop' ? '#263A57' : Color.Transparent)
          .fontColor(this.uaMode === 'desktop' ? '#8FB8FF' : '#DCE7F7')
          .onClick(() => {
            this.toggleUa();
          })
      }
      .width('100%')
      .padding(4)
      .backgroundColor('#111720')
      .borderRadius(12)

      if (this.showDebug) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(11)
            .fontColor('#9FB2CC')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.status + ' · ' + (this.uaMode === 'desktop' ? 'PC UA' : 'Mobile UA'))
            .fontSize(10)
            .fontColor('#6E8098')
        }
        .width('100%')
      }

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color('#3D7BFF')
          .backgroundColor('#1A2331')
      }

      Stack({ alignContent: Alignment.Center }) {
        ForEach([this.active], (i: number) => {
          Web({ src: this.webSrc.length > 0 ? this.webSrc : $rawfile('home.html'), controller: this.controller })
            .width('100%')
            .height('100%')
            .backgroundColor('#FFFFFF')
            .domStorageAccess(true)
            .fileAccess(false)
            .darkMode(this.darkModeValue())
            .forceDarkAccess(this.darkMode !== 'off')
            .mixedMode(this.mixedModeValue())
            .multiWindowAccess(true)
            .onControllerAttached(() => {
              this.applyUserAgent();
              try {
                this.controller.setDownloadDelegate(this.downloadDelegate);
              } catch (e) {
                Log.warn('download delegate set failed');
              }
            })
            .onPageBegin((event?: PageEvent) => {
              this.pageStart = Date.now();
              this.loading = true;
              this.status = '加载中…';
              this.progress = 0;
              this.errText = '';
            })
            .onPageEnd((event?: PageEvent) => {
              const ms = this.pageStart > 0 ? (Date.now() - this.pageStart) : 0;
              this.loading = false;
              this.status = '完成 ' + ms + 'ms';
              if (event !== undefined && event.url.length > 0) {
                if (event.url.indexOf('resource://') !== 0) {
                  this.address = event.url;
                  if (this.active >= 0 && this.active < this.tabs.length) {
                    this.tabs[this.active].url = event.url;
                  }
                } else {
                  this.address = '';
                  if (this.active >= 0 && this.active < this.tabs.length) {
                    this.tabs[this.active].url = '';
                  }
                  if (this.pendingUrl.length > 0) {
                    const u = this.pendingUrl;
                    this.pendingUrl = '';
                    this.controller.loadUrl(u);
                  }
                }
              }
              this.title = this.controller.getTitle();
              if (this.active >= 0 && this.active < this.tabs.length) {
                this.tabs[this.active].title = this.title;
              }
              if (event !== undefined && (event.url.indexOf('http://') === 0 || event.url.indexOf('https://') === 0)) {
                this.recordHistory(event.url, this.title);
              }
              this.touch();
              this.saveSession();
              this.updateNav();
              Log.info('pageEnd ' + ms + 'ms');
            })
            .onProgressChange((event?: ProgressEvent) => {
              this.progress = event !== undefined ? event.newProgress : 0;
              if (this.progress >= 100) {
                this.loading = false;
              }
              this.updateNav();
            })
            .onTitleReceive((event?: TitleEvent) => {
              if (event !== undefined && event.title.length > 0) {
                this.title = event.title;
                if (this.active >= 0 && this.active < this.tabs.length) {
                  this.tabs[this.active].title = event.title;
                  this.touch();
                }
              }
            })
            .onErrorReceive((event?: ErrorEvent) => {
              if (event === undefined) {
                return;
              }
              try {
                if (!event.request.isMainFrame()) {
                  return;
                }
                const code = event.error.getErrorCode();
                const info = event.error.getErrorInfo();
                this.errText = '错误 ' + code + '：' + info;
                this.loading = false;
                this.status = '加载失败';
                Log.warn('page error ' + code + ' ' + info);
              } catch (e) {
                this.errText = '页面加载失败';
              }
            })
            .onShowFileSelector((event?: FileSelectorEvent) => {
              return this.beginUpload(event);
            })
            .onWindowNew((event?: WindowNewEvent) => {
              this.openNewWindow(event);
            })
            .onSslErrorEventReceive((event: SslErrorEvent) => {
              this.onSslError(event);
            })
            .onLoadIntercept((event: LoadInterceptEvent) => {
              return this.blockForeignScheme(event);
            })

        }, (i: number) => i.toString() + '_' + this.webNonce)

        if (this.errText.length > 0) {
          Column({ space: 12 }) {
            Text('无法打开页面')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#EAF1FB')
            Text(this.errText)
              .fontSize(12)
              .fontColor('#FF9C9C')
              .textAlign(TextAlign.Center)
            Row({ space: 10 }) {
              Button('重试')
                .height(36)
                .fontSize(13)
                .backgroundColor('#3D7BFF')
                .onClick(() => {
                  this.openAddress();
                })
              Button('回主页')
                .height(36)
                .fontSize(13)
                .backgroundColor('#243247')
                .onClick(() => {
                  this.goHome();
                })
            }
          }
          .width('88%')
          .padding(18)
          .backgroundColor('#151D29')
          .borderRadius(14)
          .border({ width: 1, color: '#2A3A52' })
        }

        if (this.sslText.length > 0) {
          Column({ space: 12 }) {
            Text('证书不受信任')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFD166')
            Text(this.sslText)
              .fontSize(12)
              .fontColor('#EAF1FB')
              .textAlign(TextAlign.Center)
            Text('继续访问会跳过证书校验，仅在你信任该站点时使用。')
              .fontSize(11)
              .fontColor('#8295AD')
              .textAlign(TextAlign.Center)
            Row({ space: 10 }) {
              Button('取消')
                .height(36)
                .fontSize(13)
                .backgroundColor('#243247')
                .onClick(() => {
                  this.confirmSsl(false);
                })
              Button('继续访问')
                .height(36)
                .fontSize(13)
                .backgroundColor('#8A5A00')
                .onClick(() => {
                  this.confirmSsl(true);
                })
            }
          }
          .width('88%')
          .padding(18)
          .backgroundColor('#151D29')
          .borderRadius(14)
          .border({ width: 1, color: '#5A4315' })
        }

        if (this.panelMode.length > 0) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Button('书签 ' + this.bookmarks.length)
                .height(30)
                .fontSize(11)
                .padding({ left: 6, right: 6 })
                .backgroundColor(this.panelMode === 'bookmarks' ? '#3D7BFF' : '#151D29')
                .fontColor('#E8F0FB')
                .onClick(() => {
                  this.panelMode = 'bookmarks';
                })
              Button('历史 ' + this.history.length)
                .height(30)
                .fontSize(11)
                .padding({ left: 6, right: 6 })
                .backgroundColor(this.panelMode === 'history' ? '#3D7BFF' : '#151D29')
                .fontColor('#E8F0FB')
                .onClick(() => {
                  this.panelMode = 'history';
                })
              Button('下载 ' + this.downloads.length)
                .height(30)
                .fontSize(11)
                .padding({ left: 6, right: 6 })
                .backgroundColor(this.panelMode === 'downloads' ? '#3D7BFF' : '#151D29')
                .fontColor('#E8F0FB')
                .onClick(() => {
                  this.panelMode = 'downloads';
                })
              Blank()
              Button('清空')
                .height(32)
                .fontSize(11)
                .backgroundColor('#2A1B1F')
                .fontColor('#FF9C9C')
                .onClick(() => {
                  this.clearPanel();
                })
              Button('关闭')
                .height(32)
                .fontSize(11)
                .backgroundColor('#243247')
                .fontColor('#E8F0FB')
                .onClick(() => {
                  this.panelMode = '';
                })
            }
            .width('100%')

            if (this.panelMode === 'downloads') {
              if (this.downloads.length === 0) {
                Column({ space: 6 }) {
                  Text('暂无下载')
                    .fontSize(13)
                    .fontColor('#8295AD')
                  Text('网页触发下载后自动出现在这里')
                    .fontSize(11)
                    .fontColor('#5E718A')
                }
                .width('100%')
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
              } else {
                List({ space: 6 }) {
                  ForEach(this.downloads, (d: DownloadRow, idx: number) => {
                    ListItem() {
                      Column({ space: 5 }) {
                        Row({ space: 6 }) {
                          Column({ space: 3 }) {
                            Text(d.name)
                              .fontSize(12)
                              .fontColor('#E8F0FB')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .width('100%')
                            Text(this.downloadStateText(d) + (this.downloadNonce >= 0 ? '' : ''))
                              .fontSize(10)
                              .fontColor('#8295AD')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .width('100%')
                          }
                          .layoutWeight(1)
                          .alignItems(HorizontalAlign.Start)

                          if (d.state === webview.WebDownloadState.IN_PROGRESS ||
                            d.state === webview.WebDownloadState.PENDING) {
                            Button('暂停')
                              .width(40)
                              .height(28)
                              .fontSize(10)
                              .padding(0)
                              .backgroundColor('#243247')
                              .fontColor('#DCE7F7')
                              .onClick(() => {
                                this.pauseDownload(d);
                              })
                            Button('取消')
                              .width(40)
                              .height(28)
                              .fontSize(10)
                              .padding(0)
                              .backgroundColor('#2A1B1F')
                              .fontColor('#FF9C9C')
                              .onClick(() => {
                                this.cancelDownload(d);
                              })
                          } else if (d.state === webview.WebDownloadState.PAUSED) {
                            Button('继续')
                              .width(40)
                              .height(28)
                              .fontSize(10)
                              .padding(0)
                              .backgroundColor('#243247')
                              .fontColor('#DCE7F7')
                              .onClick(() => {
                                this.resumeDownload(d);
                              })
                            Button('取消')
                              .width(40)
                              .height(28)
                              .fontSize(10)
                              .padding(0)
                              .backgroundColor('#2A1B1F')
                              .fontColor('#FF9C9C')
                              .onClick(() => {
                                this.cancelDownload(d);
                              })
                          } else if (d.state === webview.WebDownloadState.COMPLETED) {
                            Button('打开')
                              .width(40)
                              .height(28)
                              .fontSize(10)
                              .padding(0)
                              .backgroundColor('#243247')
                              .fontColor('#DCE7F7')
                              .onClick(() => {
                                this.openDownload(d);
                              })
                          } else {
                            Button('重试')
                              .width(40)
                              .height(28)
                              .fontSize(10)
                              .padding(0)
                              .backgroundColor('#243247')
                              .fontColor('#DCE7F7')
                              .onClick(() => {
                                this.resumeDownload(d);
                              })
                          }
                        }
                        .width('100%')

                        if (d.state === webview.WebDownloadState.IN_PROGRESS ||
                          d.state === webview.WebDownloadState.PAUSED ||
                          d.state === webview.WebDownloadState.PENDING) {
                          Progress({ value: d.percent + (this.downloadNonce >= 0 ? 0 : 0), total: 100, type: ProgressType.Linear })
                            .width('100%')
                            .height(2)
                            .color('#3D7BFF')
                            .backgroundColor('#253346')
                        }
                      }
                      .width('100%')
                      .padding(10)
                      .backgroundColor('#151D29')
                      .borderRadius(8)
                    }
                  }, (d: DownloadRow, idx: number) => d.guid + '_' + d.state.toString())
                }
                .width('100%')
                .layoutWeight(1)
                .scrollBar(BarState.Off)
              }
            } else if (this.panelItems().length === 0) {
              Column({ space: 6 }) {
                Text(this.panelMode === 'bookmarks' ? '暂无书签' : '暂无历史')
                  .fontSize(13)
                  .fontColor('#8295AD')
                Text(this.panelMode === 'bookmarks' ? '点地址栏 ☆ 收藏当前页' : '打开网页后自动记录')
                  .fontSize(11)
                  .fontColor('#5E718A')
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              List({ space: 6 }) {
                ForEach(this.panelItems(), (it: LinkItem, idx: number) => {
                  ListItem() {
                    Row({ space: 8 }) {
                      Column({ space: 3 }) {
                        Text(it.title)
                          .fontSize(13)
                          .fontColor('#E8F0FB')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .textAlign(TextAlign.Start)
                        Text(it.url)
                          .fontSize(10)
                          .fontColor('#8295AD')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .textAlign(TextAlign.Start)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      .onClick(() => {
                        this.openLink(it);
                      })
                      Button('删')
                        .width(42)
                        .height(30)
                        .fontSize(11)
                        .backgroundColor('#2A1B1F')
                        .fontColor('#FF9C9C')
                        .onClick(() => {
                          this.deleteLink(idx);
                        })
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor('#151D29')
                    .borderRadius(8)
                  }
                }, (it: LinkItem, idx: number) => it.url + '_' + idx.toString() + '_' + this.panelMode)
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Off)
            }

            Row({ space: 8 }) {
              Text('网页深色模式')
                .fontSize(11)
                .fontColor('#8295AD')
                .layoutWeight(1)
              Button(this.darkModeLabel())
                .height(30)
                .fontSize(11)
                .padding({ left: 10, right: 10 })
                .backgroundColor('#243247')
                .fontColor('#DCE7F7')
                .onClick(() => {
                  this.cycleDarkMode();
                })
            }
            .width('100%')
            .height(32)

            Row({ space: 8 }) {
              Text('HTTPS 页面允许加载 HTTP 内容')
                .fontSize(11)
                .fontColor('#8295AD')
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.allowMixed })
                .selectedColor('#3D7BFF')
                .onChange((on: boolean) => {
                  this.setAllowMixed(on);
                })
            }
            .width('100%')
            .height(32)

            Row({ space: 8 }) {
              Text('缓存 / Cookie / 站点数据')
                .fontSize(11)
                .fontColor('#8295AD')
                .layoutWeight(1)
              Button('清除')
                .height(30)
                .fontSize(11)
                .padding({ left: 10, right: 10 })
                .backgroundColor('#2A1B1F')
                .fontColor('#FF9C9C')
                .onClick(() => {
                  this.clearBrowsingData();
                })
            }
            .width('100%')
            .height(32)

            Row({ space: 8 }) {
              Text('显示页面信息与加载耗时')
                .fontSize(11)
                .fontColor('#8295AD')
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.showDebug })
                .selectedColor('#3D7BFF')
                .onChange((on: boolean) => {
                  this.setShowDebug(on);
                })
            }
            .width('100%')
            .height(32)
          }
          .width('100%')
          .height('100%')
          .padding(12)
          .backgroundColor('#0B0F16')
          .justifyContent(FlexAlign.Start)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    .backgroundColor('#0B0F16')
  }
}
