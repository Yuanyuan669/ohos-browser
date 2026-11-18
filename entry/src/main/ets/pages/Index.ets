import webview from '@ohos.web.webview';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
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

interface TabInfo {
  url: string;
  title: string;
}

interface LinkItem {
  url: string;
  title: string;
  time: number;
}

const HOME_URL: string = 'resource://rawfile/home.html';
const MAX_TABS: number = 3;
const MAX_HISTORY: number = 100;
const UA_MOBILE: string = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const UA_DESKTOP: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

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
  @State panelMode: string = '';
  @State uaMode: string = 'mobile';
  @State showDebug: boolean = false;

  aboutToAppear(): void {
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

  private saveLinks(key: string, items: LinkItem[]): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.put(key, JSON.stringify(items));
      this.prefs.flush();
    } catch (e) {
      Log.warn('links save failed ' + key);
    }
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
    if (this.prefs !== null) {
      try {
        this.prefs.put('uaMode', this.uaMode);
        this.prefs.flush();
      } catch (e) {
        Log.warn('ua save failed');
      }
    }
    this.applyUserAgent();
    const url = this.currentHttpUrl();
    this.load(url);
    this.status = this.uaMode === 'desktop' ? '电脑版 UA' : '手机版 UA';
    Log.info('ua mode ' + this.uaMode);
  }

  private setShowDebug(on: boolean): void {
    this.showDebug = on;
    if (this.prefs !== null) {
      try {
        this.prefs.put('showDebug', on);
        this.prefs.flush();
      } catch (e) {
        Log.warn('debug save failed');
      }
    }
  }

  private tabWidth(): number {
    const n = this.tabs.length;
    if (n <= 1) {
      return 110;
    }
    return Math.max(58, Math.floor((226 - (n - 1) * 6) / n));
  }

  private saveSession(): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.put('tabs', JSON.stringify(this.tabs));
      this.prefs.put('active', this.active);
      this.prefs.flush();
    } catch (e) {
      Log.warn('session save failed');
    }
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
    }
  }

  private panelItems(): LinkItem[] {
    return this.panelMode === 'bookmarks' ? this.bookmarks : this.history;
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
            .darkMode(WebDarkMode.Off)
            .forceDarkAccess(false)
            .onControllerAttached(() => {
              this.applyUserAgent();
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

        if (this.panelMode.length > 0) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Button('书签 ' + this.bookmarks.length)
                .height(32)
                .fontSize(12)
                .backgroundColor(this.panelMode === 'bookmarks' ? '#3D7BFF' : '#151D29')
                .fontColor('#E8F0FB')
                .onClick(() => {
                  this.panelMode = 'bookmarks';
                })
              Button('历史 ' + this.history.length)
                .height(32)
                .fontSize(12)
                .backgroundColor(this.panelMode === 'history' ? '#3D7BFF' : '#151D29')
                .fontColor('#E8F0FB')
                .onClick(() => {
                  this.panelMode = 'history';
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

            if (this.panelItems().length === 0) {
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
