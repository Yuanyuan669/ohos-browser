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

const HOME_URL: string = 'resource://rawfile/home.html';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
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

  aboutToAppear(): void {
    const su: string | undefined = AppStorage.get<string>('startUrl');
    if (su !== undefined && su.length > 0) {
      this.pendingUrl = su;
      this.address = su;
    }
    this.loadPrefs();
  }

  private async loadPrefs(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const p = await preferences.getPreferences(ctx, 'browser');
      const last = await p.get('lastUrl', '') as string;
      if (last.indexOf('http://') === 0 || last.indexOf('https://') === 0) {
        this.address = last;
        Log.info('lastUrl ' + last);
      }
    } catch (e) {
      Log.warn('prefs load failed');
    }
  }

  private saveUrl(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      preferences.getPreferences(ctx, 'browser').then((p: preferences.Preferences) => {
        p.put('lastUrl', url);
        p.flush();
      });
    } catch (e) {
      Log.warn('prefs save failed');
    }
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
    this.errText = '';
    try {
      this.controller.loadUrl(url);
    } catch (e) {
      this.status = '打开失败';
    }
  }

  private goHome(): void {
    this.errText = '';
    this.address = '';
    try {
      this.controller.loadUrl(HOME_URL);
    } catch (e) {
      Log.warn('load home failed');
    }
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

  private goBack(): void {
    if (this.canBack) {
      this.controller.backward();
    }
  }

  private goForward(): void {
    if (this.canForward) {
      this.controller.forward();
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
            this.goBack();
          })
        Button('→')
          .height(34)
          .layoutWeight(1)
          .fontSize(16)
          .backgroundColor('#151D29')
          .fontColor(this.canForward ? '#DCE7F7' : '#4A586B')
          .enabled(this.canForward)
          .onClick(() => {
            this.goForward();
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
        Web({ src: $rawfile('home.html'), controller: this.controller })
          .width('100%')
          .height('100%')
          .backgroundColor('#0B0F16')
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
                this.saveUrl(event.url);
              } else {
                this.address = '';
                if (this.pendingUrl.length > 0) {
                  const u = this.pendingUrl;
                  this.pendingUrl = '';
                  this.controller.loadUrl(u);
                }
              }
            }
            this.title = this.controller.getTitle();
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
