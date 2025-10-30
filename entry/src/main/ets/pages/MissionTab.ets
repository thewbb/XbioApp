
/**
 * 任务列表 Tab
 */
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { FollowUpTask, TaskListRequest } from '../types';

@Component
export default struct MissionTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @State tasks: FollowUpTask[] = [];
  @State loading: boolean = false;
  @State searchText: string = '';
  @State syncing: boolean = false;
  @State lastSyncTime: string = '';

  async aboutToAppear() {
    console.log('========== MissionTab 加载 ==========');
    console.log('用户名:', this.currentUsername);
    console.log('Token:', this.currentToken ? '已获取' : '未获取');

    await this.loadTasks();
    await this.loadLastSyncTime();
  }

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
      } else {
        console.log('本地暂无任务数据');
      }

      this.loading = false;
    } catch (e) {
      console.error('❌ 加载任务失败:', e);
      this.loading = false;
    }
  }

  async loadLastSyncTime() {
    try {
      let timeStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.LAST_SYNC_TIME
      );

      if (timeStr) {
        const timestamp = Number(timeStr);
        const date = new Date(timestamp);
        this.lastSyncTime = `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`;
      }
    } catch (e) {
      console.error('加载同步时间失败:', e);
    }
  }

  async syncTasks() {
    if (!this.currentToken) {
      promptAction.showToast({
        message: '未获取到 Token，请重新登录',
        duration: 2000
      });
      return;
    }

    try {
      this.syncing = true;
      console.log('========== 开始同步任务 ==========');

      let isOnline = await http.isOnline();
      if (!isOnline) {
        promptAction.showToast({
          message: '网络不可用，无法同步',
          duration: 2000
        });
        this.syncing = false;
        return;
      }

      const request: TaskListRequest = {
        token: this.currentToken
      };

      console.log('发送任务列表请求...');
      let response = await http.post('/mobile/taskList.json', request);
      console.log('任务列表响应:', JSON.stringify(response));

      if (response.code === 0 && response.dataList) {
        this.tasks = response.dataList as FollowUpTask[];

        await storage.setUserData(
          this.currentUsername,
          StorageKeys.FOLLOW_UP_TASKS,
          JSON.stringify(this.tasks)
        );

        const now = Date.now();
        await storage.setUserData(
          this.currentUsername,
          StorageKeys.LAST_SYNC_TIME,
          now.toString()
        );

        await this.loadLastSyncTime();

        promptAction.showToast({
          message: `同步成功，共 ${this.tasks.length} 条任务`,
          duration: 2000
        });

        console.log('✅ 任务同步成功:', this.tasks.length, '条');
      } else {
        promptAction.showToast({
          message: response.message || '同步失败',
          duration: 2000
        });
        console.log('❌ 同步失败:', response.message);
      }

      this.syncing = false;
    } catch (e) {
      console.error('❌ 同步任务异常:', e);
      promptAction.showToast({
        message: '同步失败，请检查网络',
        duration: 2000
      });
      this.syncing = false;
    }
  }

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

  getStateText(state: number): string {
    switch (state) {
      case 0: return '待执行';
      case 1: return '进行中';
      case 2: return '已完成';
      default: return '未知';
    }
  }

  getStateColor(state: number): string {
    switch (state) {
      case 0: return '#FF6B00';
      case 1: return '#1890FF';
      case 2: return '#52C41A';
      default: return '#999999';
    }
  }

  /**
   * ✅ 点击任务，跳转到详情页
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
      console.log('✅ 跳转到任务详情页成功');
    }).catch((err: Error) => {
      console.error('❌ 跳转失败:', err);
      promptAction.showToast({
        message: '打开失败',
        duration: 1500
      });
    });
  }

  build() {
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
            this.syncTasks();
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
                this.syncTasks();
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

                Row() {
                  Text(`项目：${task.project_name}`)
                    .fontSize(14)
                    .fontColor('#666666')
                }
                .width('100%')
                .margin({ bottom: 4 })

                Row() {
                  Text(`创建人：${task.creator}`)
                    .fontSize(12)
                    .fontColor('#999999')

                  Blank()

                  Text(`完成度：${task.percent}`)
                    .fontSize(12)
                    .fontColor('#999999')
                }
                .width('100%')
                .margin({ bottom: 4 })

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
                this.handleTaskClick(task);  // ✅ 跳转到详情页
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
  }
}
