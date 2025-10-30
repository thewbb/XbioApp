
/**
 * 任务列表 Tab - 正确的进度逻辑
 *
 * percent: 整个任务的完成百分比（如 3 张表完成 2 张 = 67%）
 * task.state: 任务状态（0=待执行，1=进行中，2=已完成）
 * table.state: 表格填写状态（0=未填写，1=已填写）
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { FollowUpTask, TaskListRequest } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';

@Component
export default struct MissionTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @State tasks: FollowUpTask[] = [];
  @State loading: boolean = false;
  @State searchText: string = '';
  @State syncing: boolean = false;
  @State lastSyncTime: string = '';
  @State toastController: ToastController = new ToastController();

  async aboutToAppear() {
    console.log('========== MissionTab 加载 ==========');
    console.log('用户名:', this.currentUsername);
    console.log('Token:', this.currentToken ? '已获取' : '未获取');

    await this.loadTasks();
    await this.loadLastSyncTime();
  }

  /**
   * 从本地加载任务列表
   */
  async loadTasks() {
    try {
      console.log('从本地加载任务列表...');
      this.loading = true;

      let tasksStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.FOLLOW_UP_TASKS
      );

      if (tasksStr) {
        this.tasks = JSON.parse(tasksStr) as FollowUpTask[];
        console.log('✅ 从本地加载任务:', this.tasks.length, '条');

        // 打印任务信息，方便调试
        this.tasks.forEach((task, index) => {
          console.log(`任务 ${index + 1}:`, task.patient_no);
          console.log('  - 任务状态 (state):', task.state);
          console.log('  - 完成进度 (percent):', task.percent);
          if (task.project && task.project.tables) {
            console.log('  - 表格数量:', task.project.tables.length);
            task.project.tables.forEach((table, i) => {
              console.log(`    表格 ${i + 1}: ${table.step_name}, state=${table.state}`);
            });
          }
        });
      } else {
        console.log('本地暂无任务数据');
        this.tasks = [];
      }

      this.loading = false;
    } catch (e) {
      console.error('❌ 加载任务失败:', e);
      this.tasks = [];
      this.loading = false;
    }
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
   * 同步任务
   */
  async syncTasks() {
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

        // 更新状态
        this.tasks = serverTasks;

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
   * 触发同步
   */
  handleSync() {
    if (this.syncing) {
      return;
    }

    console.log('🔄 触发同步...');
    this.syncing = true;
    this.syncTasks();
  }

  /**
   * 获取筛选后的任务列表
   */
  getFilteredTasks(): FollowUpTask[] {
    if (!this.searchText) {
      return this.tasks;
    }

    const keyword = this.searchText.toLowerCase();
    return this.tasks.filter(task =>
    task.patient_no.toLowerCase().includes(keyword) ||
    task.project_name.toLowerCase().includes(keyword) ||
    task.creator.toLowerCase().includes(keyword)
    );
  }

  /**
   * ✅ 获取任务状态文本
   * state: 0=待执行，1=进行中，2=已完成
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
      case 0: return '#FF6B00';  // 橙色：待执行
      case 1: return '#1890FF';  // 蓝色：进行中
      case 2: return '#52C41A';  // 绿色：已完成
      default: return '#999999';
    }
  }

  /**
   * ✅ 格式化百分比显示
   * percent 是整个任务的完成百分比（字符串类型）
   * 例如："0", "33.33", "67", "100"
   */
  getPercentText(percent: string): string {
    const percentNum = Number(percent) || 0;
    return `${Math.round(percentNum)}%`;
  }

  /**
   * ✅ 获取百分比进度条颜色
   * 根据整体完成度显示不同颜色
   */
  getPercentColor(percent: string): string {
    const percentNum = Number(percent) || 0;

    if (percentNum >= 100) {
      return '#52C41A';  // 绿色：已完成 100%
    } else if (percentNum >= 50) {
      return '#1890FF';  // 蓝色：完成 50-99%
    } else if (percentNum > 0) {
      return '#FAAD14';  // 橙色：完成 1-49%
    } else {
      return '#D9D9D9';  // 灰色：未开始 0%
    }
  }

  /**
   * ✅ 获取任务的表格统计信息
   * 返回：已完成数量/总数量
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
        taskId: task.id,
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

            Text(this.searchText ? '没有找到相关任务' : '暂无任务')
              .fontSize(14)
              .fontColor('#999999')

            if (!this.searchText) {
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
                  // 第一行：患者编号 + 任务状态标签
                  Row() {
                    Text(task.patient_no)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#333333')

                    Blank()

                    Text(this.getStateText(task.state))
                      .fontSize(12)
                      .fontColor(this.getStateColor(task.state))
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .backgroundColor(this.getStateColor(task.state) + '20')
                      .borderRadius(4)
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  // 第二行：项目名称
                  Row() {
                    Text(`项目：${task.project_name}`)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  // ✅ 第三行：任务完成进度（整体进度）
                  Column() {
                    Row() {
                      Text('任务进度')
                        .fontSize(12)
                        .fontColor('#999999')

                      Blank()

                      // 显示：已完成表格数/总表格数 + 百分比
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
                      // 背景
                      Row()
                        .width('100%')
                        .height(6)
                        .backgroundColor('#F0F0F0')
                        .borderRadius(3)

                      // 进度（使用 percent 字段）
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

                  // 第四行：创建人
                  Row() {
                    Text(`创建人：${task.creator}`)
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  // 第五行：创建时间
                  Row() {
                    Text(`创建时间：${task.create_time}`)
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

      // Toast 组件
      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}
