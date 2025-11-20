/**
 * 任务列表 Tab - 带同步检查 + 项目筛选 + 知情同意书标识
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { FollowUpTask, TaskListRequest } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';

// ✅ 项目选项接口
interface ProjectOption {
  id: number;
  name: string;
}

@Component
export default struct MissionTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @Link filterType: number;  // ✅ 改为 @Link，接收父组件传递的筛选

  @State tasks: FollowUpTask[] = [];
  @State loading: boolean = false;
  @State searchText: string = '';
  @State syncing: boolean = false;
  @State lastSyncTime: string = '';
  @State toastController: ToastController = new ToastController();

  @State currentFilterIndex: number = 0;

  // ✅ 项目筛选相关
  @State projectList: ProjectOption[] = [];
  @State selectedProjectId: number = 0;  // 0 = 全部项目

  // 对话框控制
  @State showSyncConfirmDialog: boolean = false;
  @State pendingUploadCount: number = 0;

  async aboutToAppear() {
    console.log('========== MissionTab 加载 ==========');
    console.log('用户名:', this.currentUsername);
    console.log('Token:', this.currentToken ? '已获取' : '未获取');

    await this.loadTasks();
    await this.loadLastSyncTime();

    // ✅ 根据传入的 filterType 设置初始筛选
    if (this.filterType > 0) {
      this.currentFilterIndex = this.filterType;
    }
  }

  /**
   * ✅ 页面显示时刷新数据（解决详情页返回后状态不更新的问题）
   */
  async onPageShow() {
    console.log('========== MissionTab 显示 ==========');
    // 只有当已经加载过数据时才重新加载，避免首次重复加载
    if (this.tasks.length > 0 || !this.loading) {
      await this.loadTasks();
    }
  }

  /**
   * ✅ 从本地加载任务列表
   */
  async loadTasks() {
    try {
      console.log('从本地加载任务列表...');
      // 注意：这里不设置 this.loading = true，以免每次返回都闪烁 loading
      // 仅在首次加载或显式刷新时控制 loading

      let tasksStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.FOLLOW_UP_TASKS
      );

      if (tasksStr) {
        this.tasks = JSON.parse(tasksStr) as FollowUpTask[];
        console.log('✅ 从本地加载任务:', this.tasks.length, '条');

        // ✅ 提取项目列表
        this.extractProjects();
      } else {
        console.log('本地暂无任务数据');
        this.tasks = [];
        this.projectList = [{ id: 0, name: '全部项目' }];
      }

    } catch (e) {
      console.error('❌ 加载任务失败:', e);
      this.tasks = [];
    }
  }

  /**
   * ✅ 提取项目列表（去重）
   */
  extractProjects() {
    const projectMap = new Map<number, string>();

    this.tasks.forEach(task => {
      if (!projectMap.has(task.project_id)) {
        projectMap.set(task.project_id, task.project_name);
      }
    });

    // 构建项目列表
    this.projectList = [{ id: 0, name: '全部项目' }];

    projectMap.forEach((name, id) => {
      this.projectList.push({ id, name });
    });
  }

  /**
   * 加载最后同步时间
   */
  async loadLastSyncTime() {
    try {
      let timeStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.LAST_SYNC_TIME
      );

      if (timeStr) {
        const timestamp = Number(timeStr);
        const date = new Date(timestamp);
        const month = (date.getMonth() + 1).toString();
        const day = date.getDate().toString();
        const hours = date.getHours().toString();
        const minutes = date.getMinutes().toString().padStart(2, '0');
        this.lastSyncTime = `${month}月${day}日 ${hours}:${minutes}`;
      } else {
        this.lastSyncTime = '';
      }
    } catch (e) {
      console.error('加载同步时间失败:', e);
      this.lastSyncTime = '';
    }
  }

  /**
   * ✅ 检查是否有未上传的本地数据
   */
  async checkPendingUploads(): Promise<number> {
    try {
      let count = 0;

      for (let task of this.tasks) {
        if (task.local_records) {
          const pendingRecords = task.local_records.filter(r => !r.is_uploaded);
          count += pendingRecords.length;
        }
      }

      console.log('未上传的记录数:', count);
      return count;
    } catch (e) {
      console.error('检查未上传数据失败:', e);
      return 0;
    }
  }

  /**
   * 同步任务
   */
  async syncTasks(forceSync: boolean = false) {
    if (!this.currentToken) {
      console.log('❌ Token 为空');
      this.toastController.show('未获取到 Token，请重新登录');
      this.syncing = false;
      return;
    }

    try {
      console.log('========== 开始同步任务 ==========');

      // 检查网络
      let isOnline = await http.isOnline();
      if (!isOnline) {
        console.log('❌ 网络不可用');
        this.toastController.show('网络不可用，无法同步');
        this.syncing = false;
        return;
      }

      // 请求服务器任务列表
      const request: TaskListRequest = {
        token: this.currentToken
      };

      console.log('发送任务列表请求...');
      let response = await http.post('/mobile/taskList.json', request);
      console.log('任务列表响应 code:', response.code);

      if (response.code === 0) {
        const serverTasks: FollowUpTask[] = response.dataList
          ? (response.dataList as FollowUpTask[])
          : [];

        console.log('服务器任务数量:', serverTasks.length);

        // ✅ 如果不是强制同步，保留本地未上传的记录
        if (!forceSync) {
          serverTasks.forEach(serverTask => {
            const localTask = this.tasks.find(t => t.id === serverTask.id);
            if (localTask) {
              // 保留未上传记录
              if (localTask.local_records) {
                const pendingRecords = localTask.local_records.filter(r => !r.is_uploaded);
                if (pendingRecords.length > 0) {
                  serverTask.local_records = pendingRecords;
                  console.log(`任务 ${serverTask.id} 保留了 ${pendingRecords.length} 条未上传记录`);
                }
              }
              // ✅ 保留本地已签署但未同步的知情同意书（如果有这种情况）
              if (localTask.consent_signature && !serverTask.consent_signature) {
                serverTask.consent_signature = localTask.consent_signature;
              }
            }
          });
        }

        // 更新状态
        this.tasks = serverTasks;

        // ✅ 重新提取项目列表
        this.extractProjects();

        // 保存到本地
        await storage.setUserData(
          this.currentUsername,
          StorageKeys.FOLLOW_UP_TASKS,
          JSON.stringify(this.tasks)
        );

        // 更新同步时间
        const now = Date.now();
        await storage.setUserData(
          this.currentUsername,
          StorageKeys.LAST_SYNC_TIME,
          now.toString()
        );

        await this.loadLastSyncTime();

        console.log('✅ 同步成功');

        if (serverTasks.length === 0) {
          this.toastController.show('同步成功，当前无任务');
        } else {
          this.toastController.show(`同步成功，共 ${serverTasks.length} 条任务`);
        }

      } else {
        console.log('❌ 同步失败:', response.message);
        this.toastController.show(response.message || '同步失败');
      }

      this.syncing = false;

    } catch (e) {
      console.error('❌ 同步异常:', e);
      this.toastController.show('同步失败，请检查网络');
      this.syncing = false;
    }
  }

  /**
   * ✅ 触发同步（带检查）
   */
  async handleSync() {
    if (this.syncing) {
      return;
    }

    console.log('🔄 触发同步...');

    this.pendingUploadCount = await this.checkPendingUploads();

    if (this.pendingUploadCount > 0) {
      this.showSyncConfirmDialog = true;
    } else {
      this.syncing = true;
      this.syncTasks(false);
    }
  }

  /**
   * ✅ 确认强制同步
   */
  handleConfirmSync() {
    this.showSyncConfirmDialog = false;
    this.syncing = true;
    this.syncTasks(true);
  }

  /**
   * ✅ 取消同步
   */
  handleCancelSync() {
    this.showSyncConfirmDialog = false;
    this.toastController.show('已取消同步');
  }

  /**
   * ✅ 获取筛选后的任务列表（支持项目筛选）
   */
  getFilteredTasks(): FollowUpTask[] {
    let filteredTasks = this.tasks;

    // 1. 按项目筛选
    if (this.selectedProjectId !== 0) {
      filteredTasks = filteredTasks.filter(task => task.project_id === this.selectedProjectId);
    }

    // 2. 按状态筛选
    if (this.currentFilterIndex === 1) {
      filteredTasks = filteredTasks.filter(task => task.state === 0);
    } else if (this.currentFilterIndex === 2) {
      filteredTasks = filteredTasks.filter(task => task.state === 1);
    } else if (this.currentFilterIndex === 3) {
      filteredTasks = filteredTasks.filter(task => task.state === 2);
    }

    // 3. 按搜索关键字筛选
    if (this.searchText) {
      const keyword = this.searchText.toLowerCase();
      filteredTasks = filteredTasks.filter(task =>
      task.patient_no.toLowerCase().includes(keyword) ||
      task.project_name.toLowerCase().includes(keyword) ||
      task.name.toLowerCase().includes(keyword) ||
      task.creator.toLowerCase().includes(keyword)
      );
    }

    return filteredTasks;
  }

  /**
   * ✅ 获取任务状态文本
   */
  getStateText(state: number): string {
    switch (state) {
      case 0: return '待执行';
      case 1: return '进行中';
      case 2: return '已完成';
      default: return '未知';
    }
  }

  /**
   * ✅ 获取任务状态颜色
   */
  getStateColor(state: number): string {
    switch (state) {
      case 0: return '#FF6B00';
      case 1: return '#1890FF';
      case 2: return '#52C41A';
      default: return '#999999';
    }
  }

  /**
   * ✅ 格式化百分比显示
   */
  getPercentText(percent: string): string {
    const percentNum = Number(percent) || 0;
    return `${Math.round(percentNum)}%`;
  }

  /**
   * ✅ 获取百分比进度条颜色
   */
  getPercentColor(percent: string): string {
    const percentNum = Number(percent) || 0;

    if (percentNum >= 100) {
      return '#52C41A';
    } else if (percentNum >= 50) {
      return '#1890FF';
    } else if (percentNum > 0) {
      return '#FAAD14';
    } else {
      return '#D9D9D9';
    }
  }

  /**
   * ✅ 获取任务的表格统计信息
   */
  getTableStats(task: FollowUpTask): string {
    if (!task.project || !task.project.tables) {
      return '0/0';
    }

    const tables = task.project.tables;
    const totalCount = tables.length;
    const completedCount = tables.filter(table => table.state === 1).length;

    return `${completedCount}/${totalCount}`;
  }

  /**
   * 点击任务，跳转到详情页
   */
  handleTaskClick(task: FollowUpTask) {
    console.log('点击任务:', task.patient_no, '任务ID:', task.id);

    router.pushUrl({
      url: 'pages/MissionPage',
      params: {
        task: task,
        token: this.currentToken,
        username: this.currentUsername
      }
    }).then(() => {
      console.log('✅ 跳转成功');
    }).catch((err: Error) => {
      console.error('❌ 跳转失败:', err);
      this.toastController.show('打开失败');
    });
  }

  @Builder
  ProjectSelector() {
    Column() {
      Text('项目筛选')
        .fontSize(13)
        .fontColor('#999999')
        .margin({ bottom: 8 })
        .alignSelf(ItemAlign.Start)

      // ✅ 使用横向滚动的标签
      Scroll() {
        Row() {
          ForEach(this.projectList, (project: ProjectOption, index: number) => {
            Button(project.name)
              .fontSize(13)
              .height(32)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.selectedProjectId === project.id ? '#FF6B00' : '#FFFFFF')
              .fontColor(this.selectedProjectId === project.id ? '#FFFFFF' : '#666666')
              .borderRadius(16)
              .border({
                width: 1,
                color: this.selectedProjectId === project.id ? '#FF6B00' : '#E5E5E5'
              })
              .margin({ right: 8 })
              .onClick(() => {
                this.selectedProjectId = project.id;
                console.log('选择项目:', project.name);
              })
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column() {
        // 搜索栏和同步按钮
        Row() {
          TextInput({
            placeholder: '搜索患者编号或项目名称',
            text: this.searchText
          })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .onChange((value: string) => {
              this.searchText = value;
            })

          Button(this.syncing ? '同步中...' : '同步')
            .fontSize(14)
            .height(40)
            .margin({ left: 12 })
            .enabled(!this.syncing)
            .backgroundColor(this.syncing ? '#CCCCCC' : '#FF6B00')
            .borderRadius(8)
            .onClick(() => {
              this.handleSync();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F5F5F5')

        // ✅ 使用自定义项目选择器
        this.ProjectSelector()

        // ✅ 状态筛选标签栏
        Row() {
          Button('全部')
            .fontSize(14)
            .height(36)
            .backgroundColor(this.currentFilterIndex === 0 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.currentFilterIndex === 0 ? '#FFFFFF' : '#666666')
            .borderRadius(8)
            .onClick(() => {
              this.currentFilterIndex = 0;
            })

          Button('待执行')
            .fontSize(14)
            .height(36)
            .margin({ left: 12 })
            .backgroundColor(this.currentFilterIndex === 1 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.currentFilterIndex === 1 ? '#FFFFFF' : '#666666')
            .borderRadius(8)
            .onClick(() => {
              this.currentFilterIndex = 1;
            })

          Button('进行中')
            .fontSize(14)
            .height(36)
            .margin({ left: 12 })
            .backgroundColor(this.currentFilterIndex === 2 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.currentFilterIndex === 2 ? '#FFFFFF' : '#666666')
            .borderRadius(8)
            .onClick(() => {
              this.currentFilterIndex = 2;
            })

          Button('已完成')
            .fontSize(14)
            .height(36)
            .margin({ left: 12 })
            .backgroundColor(this.currentFilterIndex === 3 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.currentFilterIndex === 3 ? '#FFFFFF' : '#666666')
            .borderRadius(8)
            .onClick(() => {
              this.currentFilterIndex = 3;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 })
        .backgroundColor('#F5F5F5')

        // 最后同步时间
        if (this.lastSyncTime) {
          Row() {
            Text(`最后同步：${this.lastSyncTime}`)
              .fontSize(12)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 8 })
        }

        // 任务列表
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)

            Text('加载中...')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')

        } else if (this.getFilteredTasks().length === 0) {
          Column() {
            Text('📋')
              .fontSize(60)
              .margin({ bottom: 12 })

            Text(this.searchText || this.selectedProjectId !== 0 ? '没有找到相关任务' : '暂无任务')
              .fontSize(14)
              .fontColor('#999999')

            if (!this.searchText && this.selectedProjectId === 0) {
              Button('点击同步任务')
                .fontSize(14)
                .margin({ top: 20 })
                .backgroundColor('#FF6B00')
                .borderRadius(8)
                .onClick(() => {
                  this.handleSync();
                })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')

        } else {
          List({ space: 12 }) {
            ForEach(this.getFilteredTasks(), (task: FollowUpTask) => {
              ListItem() {
                Column() {
                  // 第一行：患者编号 + 任务状态标签 + 知情同意书标签
                  Row() {
                    Text(task.patient_no)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#333333')

                    Blank()

                    // ✅ 1. 添加知情同意书标签 (仅在已签署时显示)
                    if (task.consent_signature) {
                      Text('已签署')
                        .fontSize(12)
                        .fontColor('#FFFFFF')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor('#52C41A') // 绿色
                        .borderRadius(4)
                        .margin({ right: 8 })
                    }

                    Text(this.getStateText(task.state))
                      .fontSize(12)
                      .fontColor("#FFFFFF")
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .backgroundColor(this.getStateColor(task.state))
                      .borderRadius(4)
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  // 第二行：患者姓名（如果有）
                  if (task.name) {
                    Row() {
                      Text(`患者：${task.name}`)
                        .fontSize(14)
                        .fontColor('#666666')
                    }
                    .width('100%')
                    .margin({ bottom: 8 })
                  }

                  // 第三行：项目名称
                  Row() {
                    Text(`项目：${task.project_name}`)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  // 任务完成进度
                  Column() {
                    Row() {
                      Text('任务进度')
                        .fontSize(12)
                        .fontColor('#999999')

                      Blank()

                      Row() {
                        Text(`${this.getTableStats(task)} 表格`)
                          .fontSize(11)
                          .fontColor('#999999')
                          .margin({ right: 8 })

                        Text(this.getPercentText(task.percent))
                          .fontSize(12)
                          .fontColor('#333333')
                          .fontWeight(FontWeight.Medium)
                      }
                    }
                    .width('100%')
                    .margin({ bottom: 4 })

                    // 进度条
                    Stack() {
                      Row()
                        .width('100%')
                        .height(6)
                        .backgroundColor('#F0F0F0')
                        .borderRadius(3)

                      Row()
                        .width(`${task.percent}%`)
                        .height(6)
                        .backgroundColor(this.getPercentColor(task.percent))
                        .borderRadius(3)
                    }
                    .width('100%')
                    .alignContent(Alignment.Start)
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  // 创建人和创建时间
                  Row() {
                    Text(`创建人：${task.creator}`)
                      .fontSize(12)
                      .fontColor('#999999')

                    Blank()

                    Text(task.create_time)
                      .fontSize(12)
                      .fontColor('#CCCCCC')
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
                .onClick(() => {
                  this.handleTaskClick(task);
                })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
          .backgroundColor('#F5F5F5')
        }
      }
      .width('100%')
      .height('100%')

      // 同步确认对话框 (代码保持不变)
      if (this.showSyncConfirmDialog) {
        Column() {
          Column() {
            Text('⚠️')
              .fontSize(48)
              .margin({ bottom: 16 })

            Text('检测到本地未上传数据')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 12 })

            Text(`您有 ${this.pendingUploadCount} 份表单数据尚未上传，同步会覆盖这些本地数据。建议先前往【记录】页面上传数据。`)
              .fontSize(14)
              .fontColor('#666666')
              .textAlign(TextAlign.Center)
              .lineHeight(22)
              .margin({ bottom: 24 })

            Row() {
              Button('取消')
                .fontSize(16)
                .fontColor('#333333')
                .backgroundColor('#FFFFFF')
                .border({
                  width: 1,
                  color: '#E5E5E5'
                })
                .width('48%')
                .height(44)
                .borderRadius(8)
                .onClick(() => {
                  this.handleCancelSync();
                })

              Button('仍要同步')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .backgroundColor('#FF6B00')
                .width('48%')
                .height(44)
                .borderRadius(8)
                .onClick(() => {
                  this.handleConfirmSync();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('85%')
          .padding(24)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .shadow({
            radius: 16,
            color: '#00000040',
            offsetX: 0,
            offsetY: 4
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.handleCancelSync();
        })
      }

      // Toast 组件
      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}