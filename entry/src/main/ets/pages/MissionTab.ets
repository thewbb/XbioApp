/**
 * MissionTab.ets
 * 任务列表 Tab - 自动刷新 + 增量同步
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { FollowUpTask, TaskListRequest, FormRecord } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';

// ... (接口定义保持不变)
interface ProjectOption { id: number; name: string; }
interface TempTable { state?: number; }

@Component
export default struct MissionTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @Link filterType: number;
  @Link selectedProjectId: number;

  // ✅ 关键修改点 1: 监听 refreshFlag 的变化
  // 当 Index.ets 的 refreshFlag 增加时，这里会自动触发 onRefreshFlagChange 方法
  @Prop @Watch('onRefreshFlagChange') refreshFlag: number = 0;

  @State tasks: FollowUpTask[] = [];
  @State loading: boolean = false;
  @State searchText: string = '';
  @State syncing: boolean = false;
  @State lastSyncTime: string = '';
  @State toastController: ToastController = new ToastController();
  @State currentFilterIndex: number = 0;
  @State projectList: ProjectOption[] = [];
  @State showSyncConfirmDialog: boolean = false;
  @State pendingUploadCount: number = 0;

  async aboutToAppear() {
    await this.loadTasks();
    await this.loadLastSyncTime();
    if (this.filterType > 0) {
      this.currentFilterIndex = this.filterType;
    }
  }

  /**
   * ✅ 关键修改点 2: 响应刷新信号
   * 当父组件 (Index.ets) 的 refreshFlag 改变时，这个方法会被自动调用
   */
  onRefreshFlagChange() {
    console.log('MissionTab: 收到刷新信号，正在重新加载本地数据...');
    // 只有当用户名存在时才加载，避免初始化时的无效调用
    if (this.currentUsername) {
      this.loadTasks();
      this.loadLastSyncTime(); // 顺便更新一下时间显示
    }
  }

  /**
   * 加载任务数据
   * ✅ 这里的逻辑不需要变，但要确保它是从 storage 读取的
   */
  async loadTasks() {
    try {
      let tasksStr: string = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);
      if (tasksStr) {
        let loadedTasks = JSON.parse(tasksStr) as FollowUpTask[];

        // 强制刷新数组引用，确保 UI 更新
        this.tasks = [...loadedTasks];
        this.extractProjects();
      } else {
        this.tasks = [];
        this.projectList = [{ id: 0, name: '全部项目' }];
      }
    } catch (e) {
      console.error('MissionTab: 加载失败', e);
      this.tasks = [];
    }
  }

  extractProjects() {
    const projectMap = new Map<number, string>();
    this.tasks.forEach(task => {
      if (!projectMap.has(task.project_id)) {
        projectMap.set(task.project_id, task.project_name);
      }
    });
    this.projectList = [{ id: 0, name: '全部项目' }];
    projectMap.forEach((name, id) => {
      this.projectList.push({ id, name });
    });
  }

  async loadLastSyncTime() {
    try {
      let timeStr: string = await storage.getUserData(this.currentUsername, StorageKeys.LAST_SYNC_TIME);
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
      this.lastSyncTime = '';
    }
  }

  async syncTasks() {
    if (!this.currentToken) {
      this.toastController.show('未获取到 Token，请重新登录');
      return;
    }

    if (this.syncing) return;
    this.syncing = true;

    try {
      let isOnline = await http.isOnline();
      if (!isOnline) {
        this.toastController.show('网络不可用，无法同步');
        this.syncing = false;
        return;
      }

      const request: TaskListRequest = { token: this.currentToken };
      let response = await http.post('/mobile/taskList.json', request);

      if (response.code === 0) {
        const serverTasks: FollowUpTask[] = response.dataList ? (response.dataList as FollowUpTask[]) : [];

        let currentLocalTasks = [...this.tasks];
        let addedCount = 0;

        serverTasks.forEach(serverTask => {
          const exists = currentLocalTasks.some(local => local.id === serverTask.id);
          if (!exists) {
            currentLocalTasks.push(serverTask);
            addedCount++;
          }
        });

        this.tasks = currentLocalTasks;
        this.extractProjects();

        await storage.setUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS, JSON.stringify(this.tasks));

        const now = Date.now();
        await storage.setUserData(this.currentUsername, StorageKeys.LAST_SYNC_TIME, now.toString());
        await this.loadLastSyncTime();

        if (addedCount > 0) {
          this.toastController.show(`同步成功，新增 ${addedCount} 条任务`);
        } else {
          this.toastController.show('同步成功，暂无新任务');
        }

      } else {
        this.toastController.show(response.message || '同步失败');
      }
    } catch (e) {
      this.toastController.show('同步失败，请检查网络');
    } finally {
      this.syncing = false;
    }
  }

  handleSync() {
    this.syncTasks();
  }

  isTaskUploaded(task: FollowUpTask): boolean {
    if (task.state !== 2) return false;
    if (!task.local_records || task.local_records.length === 0) return true;
    return task.local_records.every(r => r.is_uploaded);
  }

  getFilteredTasks(): FollowUpTask[] {
    let filteredTasks = this.tasks;
    if (this.selectedProjectId !== 0) {
      filteredTasks = filteredTasks.filter(task => task.project_id === this.selectedProjectId);
    }
    if (this.currentFilterIndex === 1) {
      filteredTasks = filteredTasks.filter(task => task.state === 0);
    } else if (this.currentFilterIndex === 2) {
      filteredTasks = filteredTasks.filter(task => task.state === 1);
    } else if (this.currentFilterIndex === 3) {
      filteredTasks = filteredTasks.filter(task => task.state === 2);
    } else if (this.currentFilterIndex === 4) {
      filteredTasks = filteredTasks.filter(task => this.isTaskUploaded(task));
    }
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

  getPercentText(percent: string): string {
    const percentNum = Number(percent) || 0;
    return `${Math.round(percentNum)}%`;
  }

  getPercentColor(percent: string): string {
    const percentNum = Number(percent) || 0;
    if (percentNum >= 100) return '#52C41A';
    if (percentNum >= 50) return '#1890FF';
    if (percentNum > 0) return '#FAAD14';
    return '#D9D9D9';
  }

  getTableStats(task: FollowUpTask): string {
    if (!task || !task.project || !task.project.tables) {
      return '0/0';
    }
    const tables = task.project.tables;
    const totalCount = tables.length;
    let completedCount = 0;

    if (task.local_records && task.local_records.length > 0) {
      const filledTableIds = new Set<number>();
      task.local_records.forEach((r: FormRecord) => {
        if (r.table_id) {
          filledTableIds.add(r.table_id);
        }
      });
      completedCount = filledTableIds.size;
    } else {
      completedCount = tables.filter((table: TempTable) => {
        return table.state === 1;
      }).length;
    }
    return `${Math.min(completedCount, totalCount)}/${totalCount}`;
  }

  handleTaskClick(task: FollowUpTask) {
    router.pushUrl({
      url: 'pages/MissionPage',
      params: { task: task, token: this.currentToken, username: this.currentUsername }
    }).catch((err: Error) => {
      this.toastController.show('打开失败');
    });
  }

  getSelectedProjectName(): string {
    if (this.selectedProjectId === 0) return '全部项目';
    const project = this.projectList.find(p => p.id === this.selectedProjectId);
    return project ? project.name : `项目 ${this.selectedProjectId}`;
  }

  @Builder
  ProjectSelector() {
    Column() {
      if (this.selectedProjectId !== 0) {
        Row() {
          Text('🏥 ').fontSize(14)
          Text(`当前项目：${this.getSelectedProjectName()}`)
            .fontSize(13).fontColor('#FF6B00').fontWeight(FontWeight.Medium).layoutWeight(1)
          Button('清除筛选')
            .fontSize(12).height(28).padding({ left: 12, right: 12 })
            .backgroundColor('#F5F5F5').fontColor('#666666').borderRadius(4)
            .onClick(() => { this.selectedProjectId = 0; })
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#FFF7E6').borderRadius(8).margin({ left: 12, right: 12, bottom: 8 })
      }
      Text('项目筛选').fontSize(13).fontColor('#999999').margin({ bottom: 8, left: 12 }).alignSelf(ItemAlign.Start)
      Scroll() {
        Row() {
          ForEach(this.projectList, (project: ProjectOption) => {
            Button(project.name)
              .fontSize(13).height(32).padding({ left: 16, right: 16 })
              .backgroundColor(this.selectedProjectId === project.id ? '#FF6B00' : '#FFFFFF')
              .fontColor(this.selectedProjectId === project.id ? '#FFFFFF' : '#666666')
              .borderRadius(16)
              .border({ width: 1, color: this.selectedProjectId === project.id ? '#FF6B00' : '#E5E5E5' })
              .margin({ right: 8 })
              .onClick(() => { this.selectedProjectId = project.id; })
          })
        }.padding({ left: 12 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }.width('100%').padding({ bottom: 8 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  FilterButton(label: string, index: number) {
    Button(label)
      .fontSize(14).height(36).margin({ left: index === 0 ? 0 : 12 })
      .backgroundColor(this.currentFilterIndex === index ? '#FF6B00' : '#F5F5F5')
      .fontColor(this.currentFilterIndex === index ? '#FFFFFF' : '#666666')
      .borderRadius(8)
      .onClick(() => { this.currentFilterIndex = index; })
  }

  build() {
    Stack() {
      Column() {
        // 顶部搜索和同步按钮
        Row() {
          TextInput({ placeholder: '搜索患者编号或项目名称', text: this.searchText })
            .layoutWeight(1).height(40).fontSize(14).backgroundColor('#FFFFFF').borderRadius(8)
            .onChange((value: string) => { this.searchText = value; })
          Button(this.syncing ? '同步中...' : '同步')
            .fontSize(14).height(40).margin({ left: 12 }).enabled(!this.syncing)
            .backgroundColor(this.syncing ? '#CCCCCC' : '#FF6B00').borderRadius(8)
            .onClick(() => { this.handleSync(); })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12, top: 40 })
        .backgroundColor('#F5F5F5')

        this.ProjectSelector()

        Scroll() {
          Row() {
            this.FilterButton('全部', 0)
            this.FilterButton('待执行', 1)
            this.FilterButton('进行中', 2)
            this.FilterButton('已完成', 3)
            this.FilterButton('已上传', 4)
          }.padding({ left: 12, right: 12, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .backgroundColor('#F5F5F5')

        if (this.lastSyncTime) {
          Row() {
            Text(`最后同步：${this.lastSyncTime}`).fontSize(12).fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 8 })
        }

        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40)
            Text('加载中...').fontSize(14).fontColor('#999999').margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')
        } else if (this.getFilteredTasks().length === 0) {
          // 空状态
          Column() {
            Text('📋').fontSize(60).margin({ bottom: 12 })
            Text('没有符合条件的任务').fontSize(14).fontColor('#999999')
            if (this.currentFilterIndex === 4) {
              Text('任务完成后并成功上传数据才会显示在这里').fontSize(12).fontColor('#CCCCCC').margin({ top: 8 })
            }
            if (!this.searchText && this.selectedProjectId === 0 && this.currentFilterIndex === 0) {
              Button('点击同步任务')
                .fontSize(14)
                .margin({ top: 20 })
                .backgroundColor('#FF6B00')
                .borderRadius(8)
                .onClick(() => { this.handleSync(); })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')
        } else {
          // ✅ 列表区域：下拉刷新 + 正确高度
          Refresh({ refreshing: $$this.syncing }) {
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

                      if (task.consent_signature) {
                        Text('已签署')
                          .fontSize(12)
                          .fontColor('#FFFFFF')
                          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                          .backgroundColor('#52C41A')
                          .borderRadius(4)
                          .margin({ right: 8 })
                      }

                      if (this.isTaskUploaded(task)) {
                        Text('已上传')
                          .fontSize(12)
                          .fontColor('#FFFFFF')
                          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                          .backgroundColor('#1890FF')
                          .borderRadius(4)
                          .margin({ right: 8 })
                      }

                      Text(this.getStateText(task.state))
                        .fontSize(12)
                        .fontColor('#FFFFFF')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor(this.getStateColor(task.state))
                        .borderRadius(4)
                    }
                    .width('100%')
                    .margin({ bottom: 8 })

                    if (task.name) {
                      Row() {
                        Text(`患者：${task.name}`).fontSize(14).fontColor('#666666')
                      }
                      .width('100%')
                      .margin({ bottom: 8 })
                    }

                    Row() {
                      Text(`项目：${task.project_name}`).fontSize(14).fontColor('#666666')
                    }
                    .width('100%')
                    .margin({ bottom: 8 })

                    Column() {
                      Row() {
                        Text('任务进度').fontSize(12).fontColor('#999999')
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

                    Row() {
                      Text(`创建人：${task.creator}`).fontSize(12).fontColor('#999999')
                      Blank()
                      Text(task.create_time).fontSize(12).fontColor('#CCCCCC')
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor('#FFFFFF')
                  .borderRadius(8)
                  .onClick(() => { this.handleTaskClick(task); })
                }
              })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 0, bottom: 12 })
            .backgroundColor('#F5F5F5')
          }
          .layoutWeight(1) // 让整个可滚动区域占满剩余高度
          .onRefreshing(() => {
            this.loadTasks();
            setTimeout(() => { this.syncing = false; }, 500);
          })
        }
      }
      .width('100%')
      // 内层 Column 不再写 height('100%')，避免和 Tabs 高度冲突

      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}