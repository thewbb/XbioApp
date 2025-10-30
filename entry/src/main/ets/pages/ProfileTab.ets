
/**
 * 我的 Tab
 */
import promptAction from '@ohos.promptAction';
import { UserInfo } from '../types';

@Component
export default struct ProfileTab {
  @Prop currentUsername: string = '';
  @Prop userInfo: UserInfo | null = null;
  onLogout: () => void = () => {};

  /**
   * 修改密码
   */
  handleChangePassword() {
    console.log('点击修改密码');
    promptAction.showToast({
      message: '修改密码功能开发中',
      duration: 1500
    });
    // TODO: 跳转到修改密码页面
  }

  /**
   * 退出登录
   */
  handleLogout() {
    console.log('点击退出登录');
    promptAction.showDialog({
      title: '退出登录',
      message: '确定要退出登录吗？',
      buttons: [
        {
          text: '取消',
          color: '#999999'
        },
        {
          text: '退出',
          color: '#FF3B30'
        }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.onLogout();
      }
    });
  }

  build() {
    Column() {
      // 用户信息卡片
      Column() {
        Text('👤')
          .fontSize(60)
          .margin({ bottom: 12 })

        Text(this.userInfo?.name || this.currentUsername)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 4 })

        if (this.userInfo?.organName) {
          Text(this.userInfo.organName)
            .fontSize(14)
            .fontColor('#999999')
            .margin({ bottom: 2 })
        }

        if (this.userInfo?.phone) {
          Text(this.userInfo.phone)
            .fontSize(14)
            .fontColor('#999999')
        }
      }
      .width('100%')
      .padding(30)
      .backgroundColor('#FFFFFF')
      .margin({ bottom: 12 })

      // 功能列表
      Column() {
        // 修改密码
        Row() {
          Text('🔒')
            .fontSize(20)
            .margin({ right: 12 })

          Text('修改密码')
            .fontSize(16)
            .fontColor('#333333')

          Blank()

          Text('›')
            .fontSize(20)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .onClick(() => {
          this.handleChangePassword();
        })

        Divider()
          .strokeWidth(0.5)
          .color('#F0F0F0')

        // 退出登录
        Row() {
          Text('🚪')
            .fontSize(20)
            .margin({ right: 12 })

          Text('退出登录')
            .fontSize(16)
            .fontColor('#FF3B30')

          Blank()

          Text('›')
            .fontSize(20)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .onClick(() => {
          this.handleLogout();
        })
      }
      .width('100%')
      .borderRadius(8)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F5F5F5')
  }
}
