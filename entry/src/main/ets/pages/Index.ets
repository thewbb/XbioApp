/**
 * 首页 - 主框架（包含 Tab 切换）+ 自动刷新支持
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { CurrentUser, LocalUser, LocalUsers, UserInfo, TokenVerifyRequest, TokenVerifyResponse } from '../types';
import MainTab from './MainTab';
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

  // ✅ 用于子组件控制筛选
  @State missionFilterType: number = 0; // 0=全部, 1=待执行, 2=进行中
  @State logFilterType: number = 0; // 0=全部, 1=未上传, 2=已上传

  // ✅ 新增：项目筛选
  @State selectedProjectId: number = 0; // 0=全部项目，其他=指定项目ID

  // ✅ 刷新标志（切换 Tab 时递增）
  @State mainTabRefreshFlag: number = 0;
  @State missionTabRefreshFlag: number = 0;
  @State logTabRefreshFlag: number = 0;

  private tabController: TabsController = new TabsController();

  async aboutToAppear() {
    console.log('========== Index 页面加载 ==========');
    await storage.init();
    await this.checkLoginStatus();
  }

  /**
   * ✅ 页面显示时触发刷新
   */
  onPageShow() {
    console.log('========== Index 页面显示 ==========');
    if (this.isLoggedIn) {
      this.refreshCurrentTab();
    }
  }

  /**
   * ✅ 刷新当前 Tab
   */
  refreshCurrentTab() {
    console.log('🔄 刷新 Tab:', this.currentTabIndex);

    switch (this.currentTabIndex) {
      case 0:
        this.mainTabRefreshFlag++;
        console.log('  - MainTab refreshFlag:', this.mainTabRefreshFlag);
        break;
      case 1:
        this.missionTabRefreshFlag++;
        console.log('  - MissionTab refreshFlag:', this.missionTabRefreshFlag);
        break;
      case 2:
        this.logTabRefreshFlag++;
        console.log('  - LogTab refreshFlag:', this.logTabRefreshFlag);
        break;
    }
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

      if (!token) {
        console.log('❌ Token 为空，跳转到登录页');
        this.checkingLogin = false;
        setTimeout(() => {
          router.replaceUrl({ url: 'pages/UserPage' });
        }, 100);
        return;
      }

      // ✅ 步骤3: 如果在线，验证 Token 有效性
      console.log('步骤3: 检查网络并验证 Token...');
      let isOnline = await http.isOnline();
      console.log('网络状态:', isOnline ? '在线' : '离线');

      if (isOnline) {
        console.log('正在验证 Token 有效性...');
        let tokenValid = await this.verifyToken(token);

        if (!tokenValid) {
          console.log('❌ Token 验证失败，跳转到登录页');
          await storage.remove(StorageKeys.CURRENT_USER);
          this.checkingLogin = false;
          setTimeout(() => {
            router.replaceUrl({ url: 'pages/UserPage' });
          }, 100);
          return;
        }

        console.log('✅ Token 验证成功');
      } else {
        console.log('⚠️ 离线状态，跳过 Token 验证');
      }

      // 步骤4: 获取用户信息
      console.log('步骤4: 获取用户信息...');
      let localUsersStr: string = await storage.get(StorageKeys.LOCAL_USERS);

      if (localUsersStr) {
        let localUsers: LocalUsers = LocalUsers.fromJSON(localUsersStr);
        let localUser: LocalUser | undefined = localUsers.get(this.currentUsername);

        if (localUser && localUser.userInfo) {
          this.userInfo = localUser.userInfo;
          console.log('✅ 用户信息获取成功:', this.userInfo.name || this.userInfo.real_name);
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
   * ✅ 验证 Token 有效性
   */
  async verifyToken(token: string): Promise<boolean> {
    try {
      const request: TokenVerifyRequest = {
        token: token
      };

      console.log('发送 Token 验证请求...');
      let response = await http.post('/mobile/info.json', request);
      console.log('Token 验证响应:', JSON.stringify(response));

      if (response.code === 0 && response.dataMap) {
        let verifyData = response.dataMap as TokenVerifyResponse;
        console.log('✅ Token 有效，用户:', verifyData.username, verifyData.real_name);

        await this.updateLocalUserInfo(verifyData);

        return true;
      } else {
        console.log('❌ Token 无效，code:', response.code, 'message:', response.message);
        return false;
      }
    } catch (e) {
      console.error('❌ Token 验证异常:', e);
      return true;
    }
  }

  /**
   * ✅ 更新本地用户信息
   */
  async updateLocalUserInfo(verifyData: TokenVerifyResponse) {
    try {
      let localUsersStr: string = await storage.get(StorageKeys.LOCAL_USERS);
      if (!localUsersStr) {
        return;
      }

      let localUsers: LocalUsers = LocalUsers.fromJSON(localUsersStr);
      let localUser: LocalUser | undefined = localUsers.get(this.currentUsername);

      if (localUser) {
        localUser.userInfo.real_name = verifyData.real_name;
        localUser.userInfo.mobile = verifyData.mobile;
        localUser.userInfo.utime = verifyData.utime;

        localUsers.set(this.currentUsername, localUser);
        await storage.set(StorageKeys.LOCAL_USERS, localUsers.toJSON());

        this.userInfo = localUser.userInfo;

        console.log('✅ 本地用户信息已更新');
      }
    } catch (e) {
      console.error('更新本地用户信息失败:', e);
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

          Text('验证登录状态...')
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
          Tabs({
            barPosition: BarPosition.End,
            controller: this.tabController,
            index: this.currentTabIndex  // ✅ 添加这一行
          }) {
            // ✅ Tab 0: 主页
            TabContent() {
              MainTab({
                currentUsername: this.currentUsername,
                currentToken: this.currentToken,
                userInfo: this.userInfo,
                currentTabIndex: $currentTabIndex,
                missionFilterType: $missionFilterType,
                logFilterType: $logFilterType,
                selectedProjectId: $selectedProjectId,  // ✅ 新增
                refreshFlag: this.mainTabRefreshFlag
              })
            }
            .tabBar(this.tabBuilder(0, '主页', $r('app.media.home'), $r('app.media.home_selected')))

            // ✅ Tab 1: 任务
            TabContent() {
              MissionTab({
                currentUsername: this.currentUsername,
                currentToken: this.currentToken,
                filterType: $missionFilterType,
                selectedProjectId: $selectedProjectId,  // ✅ 新增
                refreshFlag: this.missionTabRefreshFlag
              })
            }
            .tabBar(this.tabBuilder(1, '任务', $r('app.media.file'), $r('app.media.file_selected')))

            // ✅ Tab 2: 记录
            TabContent() {
              MissionLogTab({
                currentUsername: this.currentUsername,
                currentToken: this.currentToken,
                filterType: $logFilterType,
                refreshFlag: this.logTabRefreshFlag
              })
            }
            .tabBar(this.tabBuilder(2, '记录', $r('app.media.log'), $r('app.media.log_selected')))

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
            .tabBar(this.tabBuilder(3, '我的', $r('app.media.user'), $r('app.media.user_selected')))
          }
          .width('100%')
          .height('100%')
          .barMode(BarMode.Fixed)
          .padding(0)
          .onChange((index: number) => {
            this.currentTabIndex = index;
            console.log('切换到 Tab:', index);

            // ✅ 切换 Tab 时触发刷新
            this.refreshCurrentTab();
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
  tabBuilder(index: number, title: string, icon: Resource, iconSelected: Resource) {
    Column() {
      Image(this.currentTabIndex === index ? iconSelected : icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)

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