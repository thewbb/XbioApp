
/**
 * 用户登录页面 - 支持离线登录
 */
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import http from '../utils/http';
import storage, { StorageKeys } from '../utils/storage';
import { MD5 } from '../utils/md5';
import { ApiResponse, LoginRequest, LoginResponse, LocalUser, LocalUsers, CurrentUser, UserInfo } from '../types';

// 登录结果类型
class LoginResult {
  success: boolean = false;
  message: string = '';
}

@Entry
@Component
struct UserPage {
  @State username: string = '';
  @State password: string = '';
  @State keepLogin: boolean = false;
  @State loading: boolean = false;

  async aboutToAppear() {
    console.log('UserPage 页面加载...');
    try {
      await storage.init();
      await this.loadLastUsername();
      console.log('UserPage 页面加载完成');
    } catch (e) {
      console.error('UserPage 初始化失败:', e);
    }
  }

  /**
   * 加载上次登录的用户名
   */
  async loadLastUsername() {
    try {
      let currentUserStr: string = await storage.get(StorageKeys.CURRENT_USER);
      if (currentUserStr) {
        let currentUserObj: Object = JSON.parse(currentUserStr);
        let currentUser: CurrentUser = currentUserObj as CurrentUser;

        if (currentUser.username) {
          this.username = currentUser.username;
          this.keepLogin = currentUser.keepLogin;
          console.log('自动填充用户名:', this.username);
        }
      }
    } catch (e) {
      console.error('加载用户名失败:', e);
    }
  }

  /**
   * 显示提示消息
   */
  showMessage(message: string) {
    try {
      promptAction.showToast({
        message: message,
        duration: 2000
      });
    } catch (e) {
      console.error('显示 Toast 失败:', e);
    }
  }

  /**
   * MD5 加密
   */
  md5(text: string): string {
    try {
      const hash = MD5.hash(text);
      console.log('MD5 加密成功:', hash);
      return hash;
    } catch (e) {
      console.error('MD5 加密失败:', e);
      return '';
    }
  }

  /**
   * 在线登录
   */
  async loginOnline(passwordMd5: string): Promise<boolean> {
    console.log('开始在线登录，用户名:', this.username);
    try {
      const loginRequest: LoginRequest = {
        username: this.username,
        password: passwordMd5
      };

      let response: ApiResponse = await http.post('/mobile/login.json', loginRequest);
      console.log('登录响应:', JSON.stringify(response));

      if (response.code === 0 && response.dataMap) {
        let loginResponse = response.dataMap as LoginResponse;

        if (loginResponse.token && loginResponse.userInfo) {
          // 保存用户数据
          await storage.setUserData(this.username, StorageKeys.USER_TOKEN, loginResponse.token);
          await storage.setUserData(this.username, StorageKeys.USER_INFO, JSON.stringify(loginResponse.userInfo));

          // 保存到本地用户列表
          await this.saveToLocalUsers(passwordMd5, loginResponse.token, loginResponse.userInfo);

          // ✅ 关键：必须先设置当前用户
          await this.setCurrentUser();

          console.log('在线登录成功');
          return true;
        }
      }

      console.log('在线登录失败：响应数据无效');
      return false;
    } catch (e) {
      console.error('在线登录异常:', e);
      return false;
    }
  }

  /**
   * 离线登录
   */
  async loginOffline(passwordMd5: string): Promise<boolean> {
    console.log('开始离线登录，用户名:', this.username);
    try {
      let localUsersStr: string = await storage.get(StorageKeys.LOCAL_USERS);
      console.log('本地用户数据:', localUsersStr ? '存在' : '不存在');

      if (!localUsersStr) {
        console.log('离线登录失败：无本地用户数据');
        return false;
      }

      let localUsers: LocalUsers = LocalUsers.fromJSON(localUsersStr);
      let localUser: LocalUser | undefined = localUsers.get(this.username);

      if (!localUser) {
        console.log('离线登录失败：用户不存在');
        return false;
      }

      console.log('找到本地用户，验证密码...');
      console.log('存储的密码 MD5:', localUser.passwordMd5);
      console.log('输入的密码 MD5:', passwordMd5);

      if (localUser.passwordMd5 === passwordMd5) {
        // 更新登录时间和保持登录状态
        localUser.lastLoginTime = Date.now();
        localUser.keepLogin = this.keepLogin;

        localUsers.set(this.username, localUser);
        await storage.set(StorageKeys.LOCAL_USERS, localUsers.toJSON());

        // ✅ 关键：必须设置当前用户
        await this.setCurrentUser();

        console.log('离线登录成功');
        return true;
      }

      console.log('离线登录失败：密码不匹配');
      return false;
    } catch (e) {
      console.error('离线登录异常:', e);
      return false;
    }
  }

  /**
   * 保存到本地用户列表
   */
  async saveToLocalUsers(passwordMd5: string, token: string, userInfo: UserInfo): Promise<void> {
    try {
      let localUsersStr: string = await storage.get(StorageKeys.LOCAL_USERS);
      let localUsers: LocalUsers = new LocalUsers();

      if (localUsersStr) {
        localUsers = LocalUsers.fromJSON(localUsersStr);
      }

      const localUser: LocalUser = {
        username: this.username,
        passwordMd5: passwordMd5,
        userInfo: userInfo,
        token: token,
        lastLoginTime: Date.now(),
        keepLogin: this.keepLogin
      };

      localUsers.set(this.username, localUser);
      await storage.set(StorageKeys.LOCAL_USERS, localUsers.toJSON());

      console.log('保存本地用户成功');
    } catch (e) {
      console.error('保存本地用户失败:', e);
    }
  }

  /**
   * ✅ 设置当前用户（关键方法）
   */
  async setCurrentUser(): Promise<void> {
    try {
      const currentUser: CurrentUser = {
        username: this.username,
        keepLogin: this.keepLogin,  // ✅ 使用用户选择的值
        lastLoginTime: Date.now()
      };

      await storage.set(StorageKeys.CURRENT_USER, JSON.stringify(currentUser));
      console.log('✅ 设置当前用户成功:', JSON.stringify(currentUser));
    } catch (e) {
      console.error('❌ 设置当前用户失败:', e);
      //throw e;
    }
  }

  /**
   * 登录处理 - 核心逻辑
   */
  async doLogin(): Promise<LoginResult> {
    let result: LoginResult = new LoginResult();

    try {
      console.log('步骤1: 加密密码...');
      const passwordMd5: string = this.md5(this.password);
      console.log('密码加密完成:', passwordMd5);

      if (!passwordMd5) {
        result.success = false;
        result.message = '密码加密失败';
        return result;
      }

      console.log('步骤2: 检查网络...');
      let isOnline: boolean = false;

      try {
        isOnline = await http.isOnline();
        console.log('网络状态:', isOnline ? '在线' : '离线');
      } catch (e) {
        console.error('网络检查失败，假定离线:', e);
        isOnline = false;
      }

      let loginSuccess: boolean = false;

      if (isOnline) {
        console.log('步骤3: 尝试在线登录...');
        loginSuccess = await this.loginOnline(passwordMd5);

        if (loginSuccess) {
          result.success = true;
          result.message = '登录成功';
        } else {
          result.success = false;
          result.message = '登录失败，请检查用户名和密码';
        }
      } else {
        console.log('步骤3: 尝试离线登录...');
        loginSuccess = await this.loginOffline(passwordMd5);

        if (loginSuccess) {
          result.success = true;
          result.message = '登录成功（离线）';
        } else {
          result.success = false;
          result.message = '离线登录失败，请先联网登录一次';
        }
      }

      return result;

    } catch (e) {
      console.error('登录过程异常:', e);
      result.success = false;
      result.message = '登录失败，请重试';
      return result;
    }
  }

  /**
   * 页面跳转
   */
  navigateToIndex() {
    try {
      console.log('准备跳转到 Index 页面...');
      router.replaceUrl({
        url: 'pages/Index'
      })
        .then(() => {
          console.log('✅ 跳转成功');
        })
        .catch((err: Error) => {
          console.error('❌ 跳转失败:', err);
        });
    } catch (e) {
      console.error('❌ 页面跳转异常:', e);
    }
  }

  /**
   * 登录按钮处理
   */
  handleLogin() {
    console.log('======== 开始登录 ========');
    console.log('用户名:', this.username);
    console.log('密码长度:', this.password.length);
    console.log('保持登录:', this.keepLogin);

    if (!this.username || !this.password) {
      this.showMessage('请输入用户名和密码');
      console.log('登录失败：输入为空');
      return;
    }

    const that = this;
    this.loading = true;

    // 延迟执行，确保 UI 更新
    setTimeout(() => {
      that.doLogin().then((result: LoginResult) => {
        console.log('登录结果:', JSON.stringify(result));
        that.loading = false;

        if (result.success) {
          console.log('✅ 登录成功，准备跳转...');

          // ✅ 延迟跳转，确保 CURRENT_USER 已保存
          setTimeout(() => {
            that.navigateToIndex();
          }, 200);
        } else {
          console.log('❌ 登录失败:', result.message);
          that.showMessage(result.message);
        }
      }).catch((err: Error) => {
        console.error('❌ 登录异常:', err);
        that.loading = false;
        that.showMessage('登录失败');
      });
    }, 100);

    console.log('======== 登录流程启动 ========');
  }

  build() {
    Column() {
      Column() {
        Text('🏥')
          .fontSize(80)
          .margin({ bottom: 20 })

        Text('随访系统')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 8 })

        Text('Follow-Up System')
          .fontSize(14)
          .fontColor('#999999')
      }
      .width('100%')
      .padding({ top: 60, bottom: 40 })

      Column({ space: 20 }) {
        Column({ space: 8 }) {
          Text('用户名')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')

          TextInput({ placeholder: '请输入用户名', text: this.username })
            .width('100%')
            .height(48)
            .fontSize(16)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .onChange((value: string) => {
              this.username = value;
            })
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Text('密码')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')

          TextInput({ placeholder: '请输入密码', text: this.password })
            .width('100%')
            .height(48)
            .fontSize(16)
            .type(InputType.Password)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .onChange((value: string) => {
              this.password = value;
            })
        }
        .alignItems(HorizontalAlign.Start)

        Row() {
          Checkbox({ name: 'keepLogin' })
            .select(this.keepLogin)
            .onChange((value: boolean) => {
              this.keepLogin = value;
              console.log('保持登录状态改变:', value);
            })

          Text('保持登录（离线可用）')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ left: 8 })
        }
        .width('100%')

        Button(this.loading ? '登录中...' : '登录')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor(this.loading ? '#CCCCCC' : '#FF6B00')
          .borderRadius(8)
          .enabled(!this.loading)
          .onClick(() => {
            this.handleLogin();
          })
      }
      .width('100%')
      .padding({ left: 30, right: 30 })

      Blank()

      Column({ space: 8 }) {
        Text('💡 离线模式说明')
          .fontSize(12)
          .fontColor('#999999')

        Text('勾选"保持登录"后，下次启动可离线使用')
          .fontSize(12)
          .fontColor('#999999')
      }
      .padding({ bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
