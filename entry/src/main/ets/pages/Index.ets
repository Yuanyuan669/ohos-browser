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

const HOME_URL: string = 'resource://rawfile/home.html';
const MAX_TABS: number = 3;

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
      const t = this.tabs[this.active];
      this.title = t.title;
      this.address = t.url;
      if (this.pendingUrl.length === 0 && t.url.length > 0) {
        this.pendingUrl = t.url;
      }
      Log.info('session restored ' + this.tabs.length + ' tabs');
    } catch (e) {
      Log.warn('session load failed');
    }
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
          .layoutWeight(1)
          .height(30)
          .padding({ left: 8, right: 8 })
          .backgroundColor(i === this.active ? '#1E2B40' : '#111720')
          .borderRadius(8)
          .onClick(() => {
            this.switchTab(i);
          })
        }, (t: TabInfo, i: number) => i.toString() + t.url + t.title)
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
        Button('打开')
          .height(40)
          .fontSize(13)
          .backgroundColor('#3D7BFF')
          .onClick(() => {
            this.openAddress();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('←')
          .height(34)
          .layoutWeight(1)
          .fontSize(16)
          .backgroundColor('#151D29')
          .fontColor(this.canBack ? '#DCE7F7' : '#4A586B')
          .enabled(this.canBack)
          .onClick(() => {
            if (this.canBack) {
              this.controller.backward();
            }
          })
        Button('→')
          .height(34)
          .layoutWeight(1)
          .fontSize(16)
          .backgroundColor('#151D29')
          .fontColor(this.canForward ? '#DCE7F7' : '#4A586B')
          .enabled(this.canForward)
          .onClick(() => {
            if (this.canForward) {
              this.controller.forward();
            }
          })
        Button(this.loading ? '停止' : '刷新')
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#151D29')
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.refreshOrStop();
          })
        Button('主页')
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#151D29')
          .fontColor('#DCE7F7')
          .onClick(() => {
            this.goHome();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.title)
          .fontSize(11)
          .fontColor('#9FB2CC')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.status)
          .fontSize(10)
          .fontColor('#6E8098')
      }
      .width('100%')

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
              try {
                this.controller.setCustomUserAgent(
                  'Mozilla/5.0 (Phone; OpenHarmony 4.1) AppleWebKit/537.36 (KHTML, like Gecko) HomeBrowser/0.1');
              } catch (e) {
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
