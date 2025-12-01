import { UserInfo, FollowUpTask } from '../types';
import storage, { StorageKeys } from '../utils/storage';

interface ProjectStat {
  projectId: number;
  projectName: string;
  pending: number;
  inProgress: number;
  pendingUpload: number;
  uploaded: number;
}

@Component
export default struct MainTab {
  @Prop currentUsername: string;
  @Prop currentToken: string;
  @Prop userInfo: UserInfo | null;

  @Link currentTabIndex: number;
  @Link missionFilterType: number;
  @Link logFilterType: number;
  @Link selectedProjectId: number;

  @Prop refreshFlag: number = 0;
  private lastRefreshFlag: number = 0;

  // 基础类型状态变量
  @State statPending: number = 0;
  @State statInProgress: number = 0;
  @State statPendingUpload: number = 0;
  @State statUploaded: number = 0;

  @State projectStats: ProjectStat[] = [];
  @State loading: boolean = false;
  @State currentDate: string = '';

  async aboutToAppear() {
    console.log('========== MainTab 加载 ==========');
    this.updateCurrentDate();
    this.lastRefreshFlag = this.refreshFlag;
    setTimeout(() => {
      this.loadStatistics();
    }, 100);
  }

  async aboutToUpdate() {
    if (this.refreshFlag !== this.lastRefreshFlag && this.refreshFlag > 0) {
      this.lastRefreshFlag = this.refreshFlag;
      await this.loadStatistics();
    }
  }

  updateCurrentDate() {
    const now = new Date();
    const weekDays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    this.currentDate = `${now.getFullYear()}年${String(now.getMonth() + 1).padStart(2, '0')}月${String(now.getDate()).padStart(2, '0')}日 ${weekDays[now.getDay()]}`;
  }

  async loadStatistics() {
    try {
      this.loading = true;
      let tasksStr = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);

      if (!tasksStr || tasksStr === '[]') {
        this.resetStats();
        this.loading = false;
        return;
      }

      let tasks: FollowUpTask[] = [];
      try {
        tasks = JSON.parse(tasksStr);
      } catch (e) {
        this.resetStats();
        this.loading = false;
        return;
      }

      let totalPending = 0;
      let totalInProgress = 0;
      let totalPendingUpload = 0;
      let totalUploaded = 0;

      let projectMap = new Map<number, ProjectStat>();

      for (let task of tasks) {
        let taskState = Number(task.state);
        let projectId = task.project_id || 0;
        let projectName = task.project_name || (projectId === 0 ? '其他项目' : `项目 ${projectId}`);

        if (!projectMap.has(projectId)) {
          projectMap.set(projectId, {
            projectId: projectId,
            projectName: projectName,
            pending: 0,
            inProgress: 0,
            pendingUpload: 0,
            uploaded: 0
          });
        }

        let pStat = projectMap.get(projectId)!;

        // 状态统计
        if (taskState === 0) {
          pStat.pending++;
          totalPending++;
        } else if (taskState === 1) {
          pStat.inProgress++;
          totalInProgress++;
        } else if (taskState === 2) {
          pStat.uploaded++;
          totalUploaded++;
        }

        // 待上传统计
        if (task.local_records && Array.isArray(task.local_records)) {
          const count = task.local_records.filter(r => !r.is_uploaded).length;
          pStat.pendingUpload += count;
          totalPendingUpload += count;
        }
      }

      const finalProjectStats = Array.from(projectMap.values());
      console.log(`📊 统计完成: pending=${totalPending}, inProgress=${totalInProgress}, pendingUpload=${totalPendingUpload}, uploaded=${totalUploaded}`);

      // 更新状态
      this.statPending = totalPending;
      this.statInProgress = totalInProgress;
      this.statPendingUpload = totalPendingUpload;
      this.statUploaded = totalUploaded;
      this.projectStats = finalProjectStats;

    } catch (e) {
      console.error('❌ 加载统计异常:', e);
      this.resetStats();
    } finally {
      this.loading = false;
    }
  }

  resetStats() {
    this.statPending = 0;
    this.statInProgress = 0;
    this.statPendingUpload = 0;
    this.statUploaded = 0;
    this.projectStats = [];
  }

  /**
   * ✅ 辅助方法：直接读取 @State 变量
   */
  getStatCount(type: string): number {
    switch (type) {
      case 'pending': return this.statPending;
      case 'inProgress': return this.statInProgress;
      case 'pendingUpload': return this.statPendingUpload;
      case 'uploaded': return this.statUploaded;
      default: return 0;
    }
  }

  handleStatClick(type: string) {
    switch (type) {
      case 'pending':
        this.selectedProjectId = 0;
        this.missionFilterType = 1;
        setTimeout(() => this.currentTabIndex = 1, 50);
        break;
      case 'inProgress':
        this.selectedProjectId = 0;
        this.missionFilterType = 2;
        setTimeout(() => this.currentTabIndex = 1, 50);
        break;
      case 'pendingUpload':
        this.selectedProjectId = 0;
        this.logFilterType = 1;
        setTimeout(() => this.currentTabIndex = 2, 50);
        break;
      case 'uploaded':
        this.selectedProjectId = 0;
        this.missionFilterType = 3;
        setTimeout(() => this.currentTabIndex = 1, 50);
        break;
    }
  }

  handleViewProject(projectId: number) {
    this.selectedProjectId = projectId;
    this.missionFilterType = 0;
    setTimeout(() => this.currentTabIndex = 1, 50);
  }

  handleStartFollow(projectId: number) {
    this.selectedProjectId = projectId;
    this.missionFilterType = 1;
    setTimeout(() => this.currentTabIndex = 1, 50);
  }

  @Builder
  statCardBuilder(title: string, color: string, type: string) {
    Column() {
      // ✅ 直接调用方法读取 @State，不再通过参数传递数值
      Text(this.getStatCount(type).toString())
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(color)
      Text(title).fontSize(12).fontColor('#666666').margin({ top: 4 })
    }
    .width('22%').padding({ top: 12, bottom: 12 }).backgroundColor('#F9FAFB').borderRadius(8)
    .onClick(() => { this.handleStatClick(type); })
  }

  @Builder
  projectCardBuilder(project: ProjectStat) {
    Column() {
      Row() {
        Text('🏥').fontSize(20).margin({ right: 8 })
        Column() {
          Text(project.projectName).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
          Text(`项目ID: ${project.projectId}`).fontSize(12).fontColor('#999999').margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').margin({ bottom: 12 })

      Divider().color('#EEEEEE').margin({ bottom: 12 })

      Row() {
        this.projectStatItem('待随访', project.pending, '#FF6B00')
        this.projectStatItem('进行中', project.inProgress, '#1890FF')
        this.projectStatItem('待上传', project.pendingUpload, '#FAAD14')
        this.projectStatItem('已完成', project.uploaded, '#52C41A')
      }.width('100%').justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Button('查看详情').fontSize(14).fontColor('#666666').backgroundColor('#F7F8FA')
          .height(36).layoutWeight(1).onClick(() => { this.handleViewProject(project.projectId); })
        Blank().width(12)
        Button('开始随访').fontSize(14).fontColor('#FFFFFF').backgroundColor('#FF6B00')
          .height(36).layoutWeight(1).onClick(() => { this.handleStartFollow(project.projectId); })
      }.width('100%').margin({ top: 12 })
    }
    .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12).margin({ bottom: 12 })
  }

  @Builder
  projectStatItem(label: string, count: number, color: string) {
    Column() {
      Text(label).fontSize(12).fontColor('#666666')
      Text(count.toString()).fontSize(16).fontWeight(FontWeight.Bold).fontColor(color).margin({ top: 4 })
    }.width('23%').alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Column() {
          Row() {
            Text('👋 ').fontSize(24)
            Text(`你好，${this.userInfo?.real_name || this.userInfo?.name || this.currentUsername}`)
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#333333')
          }
          Text(this.currentDate).fontSize(14).fontColor('#999999').margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)

        Button(this.loading ? '...' : '刷新')
          .fontSize(14).width(60).height(32)
          .backgroundColor(this.loading ? '#E5E5E5' : '#FF6B00')
          .fontColor('#FFFFFF').borderRadius(16)
          .enabled(!this.loading)
          .onClick(() => { this.loadStatistics(); })
      }
      .width('100%').padding({ left: 20, right: 20, top: 20, bottom: 10 }).backgroundColor('#FFFFFF')

      Scroll() {
        Column() {
          Column() {
            Text('📊 数据概览').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
              .margin({ bottom: 12 }).alignSelf(ItemAlign.Start)

            // ✅ 这里移除了数字参数
            Row() {
              this.statCardBuilder('待随访', '#FF6B00', 'pending')
              this.statCardBuilder('进行中', '#1890FF', 'inProgress')
              this.statCardBuilder('待上传', '#FAAD14', 'pendingUpload')
              this.statCardBuilder('已完成', '#52C41A', 'uploaded')
            }
            .width('100%').justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12).margin({ top: 12, bottom: 12 })

          if (!this.loading && this.projectStats.length === 0) {
            Column() {
              Text('暂无项目数据').fontSize(14).fontColor('#999999').margin({ top: 20 })
            }.width('100%').alignItems(HorizontalAlign.Center)
          } else {
            Column() {
              Text('📁 项目列表').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
                .margin({ top: 4, bottom: 12 }).alignSelf(ItemAlign.Start)
              ForEach(this.projectStats, (project: ProjectStat) => {
                this.projectCardBuilder(project)
              })
            }
            .width('100%').padding({ left: 4, right: 4 })
          }
          Column().height(20)
        }
        .padding({ left: 12, right: 12 })
      }
      .layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}