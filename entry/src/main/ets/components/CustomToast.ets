
/**
 * 自定义 Toast 组件
 * 使用方法：
 * 1. 在组件中添加状态：@State toastController: ToastController = new ToastController()
 * 2. 在 build 中添加：CustomToast({ controller: this.toastController })
 * 3. 调用：this.toastController.show('提示消息')
 */

/**
 * Toast 控制器
 */
export class ToastController {
  private showCallback?: (message: string) => void;

  /**
   * 注册显示回调
   */
  register(callback: (message: string) => void) {
    this.showCallback = callback;
  }

  /**
   * 显示 Toast
   */
  show(message: string) {
    if (this.showCallback) {
      this.showCallback(message);
    } else {
      console.warn('⚠️ ToastController 未注册，请在 build 中添加 CustomToast 组件');
    }
  }
}

/**
 * Toast 组件
 */
@Component
export struct CustomToast {
  @ObjectLink controller: ToastController;
  @State private message: string = '';
  @State private visible: boolean = false;
  private hideTimer: number = -1;

  aboutToAppear() {
    // 注册显示回调
    this.controller.register((message: string) => {
      this.showToast(message);
    });
  }

  /**
   * 显示 Toast
   */
  private showToast(message: string) {
    console.log('📢 Toast:', message);

    // 清除之前的定时器
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
    }

    // 显示新消息
    this.message = message;
    this.visible = true;

    // 2秒后自动隐藏
    this.hideTimer = setTimeout(() => {
      this.visible = false;
      this.hideTimer = -1;
    }, 2000);
  }

  /**
   * 手动隐藏
   */
  private hide() {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
    this.visible = false;
  }

  build() {
    Stack() {
      if (this.visible) {
        // Toast 消息框
        Row() {
          Text(this.message)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#333333DD')
        .borderRadius(8)
        .shadow({ radius: 10, color: '#00000033' })
        .onClick(() => {
          this.hide();
        })
        .transition({
          type: TransitionType.Insert,
          opacity: 0,
          translate: { y: 20 }
        })
        .transition({
          type: TransitionType.Delete,
          opacity: 0,
          translate: { y: 20 }
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
    .padding({ bottom: 80 })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
