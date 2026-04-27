/**
 * 用户登录页面 - 支持离线登录 + 服务器配置 + 网络验证
 * 修改点：自动过滤输入的 http:// 或 https:// 前缀
 */
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import http from '../utils/http';
import storage, { StorageKeys } from '../utils/storage';
import { MD5 } from '../utils/md5';
import { ApiResponse, LoginRequest, LoginResponse, LocalUser, LocalUsers, CurrentUser, UserInfo } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';

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
  @State toastController: ToastController = new ToastController();

  // ✅ 服务器配置相关状态
  @State showServerDialog: boolean = false;
  @State serverUrl: string = '';
  @State tempServerUrl: string = '';
  @State isCheckingServer: boolean = false; // 新增：检查服务器中

  async aboutToAppear() {
    console.log('UserPage 页面加载...');
    try {
      await storage.init();
      await this.loadLastUsername();
      await this.loadServerUrl();  // ✅ 加载服务器地址
      console.log('UserPage 页面加载完成');
    } catch (e) {
      console.error('UserPage 初始化失败:', e);
    }
  }

  /**
   * ✅ 加载服务器地址
   */
  async loadServerUrl() {
    try {
      this.serverUrl = await storage.getServerUrl();
      console.log('当前服务器地址:', this.serverUrl);
    } catch (e) {
      console.error('加载服务器地址失败:', e);
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
   * ✅ 打开服务器配置对话框
   */
  openServerConfig() {
    this.tempServerUrl = this.serverUrl;
    this.showServerDialog = true;
  }

  /**
   * ✅ 保存服务器配置（带验证 + 自动过滤前缀）
   */
  async saveServerConfig() {
    // 1. ✅ 自动过滤处理：去除首尾空格，去除 http:// 或 https:// 前缀
    let cleanUrl = this.tempServerUrl.trim();
    // 正则表达式替换：^表示开头，https?表示http或https，i表示忽略大小写
    cleanUrl = cleanUrl.replace(/^https?:\/\//i, '');

    // 更新状态变量，这样输入框里的内容也会自动变干净，给用户直观反馈
    this.tempServerUrl = cleanUrl;

    if (!this.tempServerUrl) {
      this.toastController.show('请输入服务器地址');
      return;
    }

    // 简单格式校验 (可选，简单判断是否包含冒号)
    // if (this.tempServerUrl.indexOf(':') === -1) {
    //   this.toastController.show('请输入正确的 IP:端口 格式');
    //   return;
    // }

    this.isCheckingServer = true; // 显示加载状态

    try {
      // 2. 验证服务器是否可达
      console.log('正在验证服务器:', this.tempServerUrl);

      // 临时保存旧地址以便回滚
      // 注意：这里假设 http 工具类有 getBaseUrl 方法，如果没有，请自行调整
      // 如果 http.baseUrl 是公开属性直接读取即可，或者直接 try-catch 覆盖
      let oldUrl = '';
      try {
        // 尝试获取旧地址，如果工具类不支持获取，可以省略这一步，验证失败不回滚也行，或者依靠 loadServerUrl 恢复
        // 这里为了稳健，假设我们能获取或通过 storage 恢复
        oldUrl = this.serverUrl;
      } catch(e) {}

      // 设置新地址
      await http.setBaseUrl(this.tempServerUrl);

      // 发起测试请求
      try {
        // 使用 http.isOnline() 检测新地址连通性
        let isServerAvailable = await http.isOnline();

        if (!isServerAvailable) {
          throw new Error('服务器无法连接');
        }

        // 验证通过，确认保存
        this.serverUrl = this.tempServerUrl;
        this.showServerDialog = false;
        this.toastController.show('✅ 服务器连接成功并已保存');
        console.log('✅ 服务器地址已更新:', this.serverUrl);

      } catch (err) {
        // 验证失败，回滚地址
        console.error('验证失败:', err);
        if (oldUrl) {
          await http.setBaseUrl(oldUrl); // 恢复旧地址
        }
        this.toastController.show('❌ 无法连接到该服务器，请检查地址');
      }

    } catch (e) {
      console.error('❌ 保存服务器地址过程异常:', e);
      this.toastController.show('验证过程出错');
    } finally {
      this.isCheckingServer = false;
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

          // 设置当前用户
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

      if (localUser.passwordMd5 === passwordMd5) {
        // 更新登录时间和保持登录状态
        localUser.lastLoginTime = Date.now();
        localUser.keepLogin = this.keepLogin;

        localUsers.set(this.username, localUser);
        await storage.set(StorageKeys.LOCAL_USERS, localUsers.toJSON());

        // 设置当前用户
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
   * 设置当前用户
   */
  async setCurrentUser(): Promise<void> {
    try {
      const currentUser: CurrentUser = {
        username: this.username,
        keepLogin: this.keepLogin,
        lastLoginTime: Date.now()
      };

      await storage.set(StorageKeys.CURRENT_USER, JSON.stringify(currentUser));
      console.log('✅ 设置当前用户成功:', JSON.stringify(currentUser));
    } catch (e) {
      console.error('❌ 设置当前用户失败:', e);
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

      if (!passwordMd5) {
        result.success = false;
        result.message = '密码加密失败';
        return result;
      }

      console.log('步骤2: 检查网络...');
      let isOnline: boolean = false;

      try {
        // ✅ 修改：使用 http.isOnline() 并且确保它基于当前配置的服务器地址
        isOnline = await http.isOnline();
        console.log('网络及服务器状态:', isOnline ? '在线' : '离线');
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
          result.message = '无法连接服务器，且无离线记录';
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
    router.replaceUrl({ url: 'pages/Index' });
  }

  /**
   * 登录按钮处理
   */
  handleLogin() {
    if (!this.username || !this.password) {
      this.toastController.show('请输入用户名和密码');
      return;
    }

    const that = this;
    this.loading = true;

    setTimeout(() => {
      that.doLogin().then((result: LoginResult) => {
        that.loading = false;

        if (result.success) {
          this.toastController.show(result.message);
          setTimeout(() => {
            that.navigateToIndex();
          }, 200);
        } else {
          this.toastController.show(result.message);
        }
      }).catch((err: Error) => {
        that.loading = false;
        this.toastController.show('登录失败');
      });
    }, 100);
  }

  build() {
    Stack() {
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

          // ✅ 服务器配置按钮
          Button('⚙️ 服务器配置')
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .onClick(() => {
              this.openServerConfig();
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

          // ✅ 显示当前服务器地址
          if (this.serverUrl) {
            Text(`📡 服务器：${this.serverUrl}`)
              .fontSize(11)
              .fontColor('#CCCCCC')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .padding({ bottom: 30 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      // ✅ 服务器配置对话框
      if (this.showServerDialog) {
        Column() {
          Column() {
            // 标题
            Row() {
              Text('服务器配置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')

              Blank()

              Text('✕')
                .fontSize(24)
                .fontColor('#999999')
                .onClick(() => {
                  if (!this.isCheckingServer) {
                    this.showServerDialog = false;
                  }
                })
            }
            .width('100%')
            .margin({ bottom: 20 })

            // 输入框
            Column({ space: 8 }) {
              Text('服务器地址')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')

              TextInput({
                placeholder: '192.168.1.100:8080',
                text: this.tempServerUrl
              })
                .width('100%')
                .height(48)
                .fontSize(14)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.tempServerUrl = value;
                })

              Text('示例：192.168.48.87:8080')
                .fontSize(12)
                .fontColor('#999999')
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ bottom: 20 })

            // 按钮
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor('#666666')
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .enabled(!this.isCheckingServer) // 检查时禁用
                .onClick(() => {
                  this.showServerDialog = false;
                })

              Button(this.isCheckingServer ? '验证中...' : '保存')
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor('#FFFFFF')
                .backgroundColor(this.isCheckingServer ? '#CCCCCC' : '#FF6B00')
                .borderRadius(8)
                .enabled(!this.isCheckingServer)
                .onClick(() => {
                  this.saveServerConfig();
                })
            }
            .width('100%')
          }
          .width('85%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .shadow({
            radius: 20,
            color: '#00000030',
            offsetX: 0,
            offsetY: 4
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0, 0, 0, 0.5)')
      }
      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}