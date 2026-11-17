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

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State address: string = '';
  @State title: string = '浏览器';
  @State status: string = '就绪';
  @State progress: number = 0;
  @State errText: string = '';
  private pageStart: number = 0;
  private savedUrl: string = '';

  aboutToAppear(): void {
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
    const c = s.charAt(0);
    if (c >= '0' && c <= '9') {
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

      if (this.errText.length > 0) {
        Text('加载失败：' + this.errText)
          .fontSize(11)
          .fontColor('#FF8A8A')
          .width('100%')
          .padding(8)
          .backgroundColor('#2A1616')
          .borderRadius(8)
      }

      Web({ src: $rawfile('home.html'), controller: this.controller })
        .width('100%')
        .layoutWeight(1)
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
          this.status = '加载中…';
          this.progress = 0;
          this.errText = '';
        })
        .onPageEnd((event?: PageEvent) => {
          const ms = this.pageStart > 0 ? (Date.now() - this.pageStart) : 0;
          this.status = '完成 ' + ms + 'ms';
          if (event !== undefined && event.url.length > 0) {
            if (event.url.indexOf('resource://') !== 0) {
              this.address = event.url;
              this.savedUrl = event.url;
              this.saveUrl(event.url);
            }
          }
          this.title = this.controller.getTitle();
          Log.info('pageEnd ' + ms + 'ms');
        })
        .onProgressChange((event?: ProgressEvent) => {
          this.progress = event !== undefined ? event.newProgress : 0;
        })
        .onTitleReceive((event?: TitleEvent) => {
          if (event !== undefined && event.title.length > 0) {
            this.title = event.title;
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    .backgroundColor('#0B0F16')
  }
}
