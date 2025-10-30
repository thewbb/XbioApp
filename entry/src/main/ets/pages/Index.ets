
/**
 * 首页 - 主框架（包含 Tab 切换）
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import { CurrentUser, LocalUser, LocalUsers, UserInfo } from '../types';
import MissionTab from './MissionTab';
import MissionLogTab from './MissionLogTab';
import ProfileTab from './ProfileTab';

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0;
  @State isLoggedIn: boolean = false;
  @State checkingLogin: boolean = true;
  @State currentUsername: string = '';
  @State currentToken: string = '';
  @State userInfo: UserInfo | null = null;

  private tabController: TabsController = new TabsController();

  async aboutToAppear() {
    console.log('========== Index 页面加载 ==========');
    await storage.init();
    await this.checkLoginStatus();
  }

  /**
   * 检查登录状态
   */
  async checkLoginStatus() {
    try {
      console.log('步骤1: 开始检查登录状态...');

      // 获取当前用户
      let currentUserStr: string = await storage.get(StorageKeys.CURRENT_USER);
      console.log('CURRENT_USER:', currentUserStr ? '已找到' : '未找到');

      if (!currentUserStr) {
        console.log('❌ 未找到当前用户，跳转到登录页');
        this.checkingLogin = false;
        setTimeout(() => {
          router.replaceUrl({ url: 'pages/UserPage' });
        }, 100);
        return;
      }

      // 解析当前用户
      let currentUserObj: Object = JSON.parse(currentUserStr);
      let currentUser: CurrentUser = currentUserObj as CurrentUser;

      console.log('当前用户:', currentUser.username);
      console.log('keepLogin:', currentUser.keepLogin);

      if (!currentUser.username) {
        console.log('❌ 用户名为空，跳转到登录页');
        this.checkingLogin = false;
        setTimeout(() => {
          router.replaceUrl({ url: 'pages/UserPage' });
        }, 100);
        return;
      }

      this.currentUsername = currentUser.username;

      // 步骤2: 获取 Token
      console.log('步骤2: 获取用户 Token...');
      let token: string = await storage.getUserData(this.currentUsername, StorageKeys.USER_TOKEN);
      this.currentToken = token;
      console.log('Token:', token ? '已获取' : '未获取');

      // 步骤3: 获取用户信息
      console.log('步骤3: 获取用户信息...');
      let localUsersStr: string = await storage.get(StorageKeys.LOCAL_USERS);

      if (localUsersStr) {
        let localUsers: LocalUsers = LocalUsers.fromJSON(localUsersStr);
        let localUser: LocalUser | undefined = localUsers.get(this.currentUsername);

        if (localUser && localUser.userInfo) {
          this.userInfo = localUser.userInfo;
          console.log('✅ 用户信息获取成功:', this.userInfo.name);
        }
      }

      // 显示主页
      this.isLoggedIn = true;
      this.checkingLogin = false;
      console.log('✅ 登录状态检查完成，显示主页');

    } catch (e) {
      console.error('❌ 检查登录状态失败:', e);
      this.checkingLogin = false;
      setTimeout(() => {
        router.replaceUrl({ url: 'pages/UserPage' });
      }, 100);
    }
  }

  /**
   * 退出登录
   */
  async handleLogout() {
    console.log('执行退出登录...');
    try {
      await storage.remove(StorageKeys.CURRENT_USER);
      console.log('✅ 已清除登录状态');

      setTimeout(() => {
        router.replaceUrl({ url: 'pages/UserPage' });
      }, 100);
    } catch (e) {
      console.error('❌ 退出登录失败:', e);
    }
  }

  build() {
    Column() {
      if (this.checkingLogin) {
        // 加载中
        Column() {
          Text('🏥')
            .fontSize(80)
            .margin({ bottom: 20 })

          Text('加载中...')
            .fontSize(18)
            .fontColor('#666666')

          LoadingProgress()
            .width(40)
            .height(40)
            .margin({ top: 20 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFFFFF')

      } else if (this.isLoggedIn) {
        // 主页内容
        Column() {
          // 顶部标题栏
          Row() {
            Text('随访系统')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .justifyContent(FlexAlign.Center)

          // Tab 内容
          Tabs({ barPosition: BarPosition.End, controller: this.tabController }) {
            // Tab 1: 任务
            TabContent() {
              MissionTab({
                currentUsername: this.currentUsername,
                currentToken: this.currentToken
              })
            }
            .tabBar(this.tabBuilder(0, '任务', '📋'))

            // Tab 2: 记录
            TabContent() {
              MissionLogTab({
                currentUsername: this.currentUsername,
                currentToken: this.currentToken
              })
            }
            .tabBar(this.tabBuilder(1, '记录', '📝'))

            // Tab 3: 我的
            TabContent() {
              ProfileTab({
                currentUsername: this.currentUsername,
                userInfo: this.userInfo,
                onLogout: () => {
                  this.handleLogout();
                }
              })
            }
            .tabBar(this.tabBuilder(2, '我的', '👤'))
          }
          .width('100%')
          .layoutWeight(1)
          .barMode(BarMode.Fixed)
          .onChange((index: number) => {
            this.currentTabIndex = index;
            console.log('切换到 Tab:', index);
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F5F5')
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * Tab 标签构建器
   */
  @Builder
  tabBuilder(index: number, title: string, icon: string) {
    Column() {
      Text(icon)
        .fontSize(24)
        .fontColor(this.currentTabIndex === index ? '#FF6B00' : '#999999')

      Text(title)
        .fontSize(12)
        .fontColor(this.currentTabIndex === index ? '#FF6B00' : '#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }
}
