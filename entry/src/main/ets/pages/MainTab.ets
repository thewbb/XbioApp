import { UserInfo, FollowUpTask } from '../types';
import storage, { StorageKeys } from '../utils/storage';

// 统计数据结构
interface Statistics {
  pending: number;      // 待随访 (state=0)
  inProgress: number;   // 进行中 (state=1)
  notUploaded: number;  // 未上传 (local_records 中 is_uploaded=false 的数量)
  uploaded: number;     // 已完成 (state=2 且所有记录均已上传)
}

// 项目统计
interface ProjectStat {
  projectId: number;
  projectName: string;
  stats: Statistics;
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

  @State totalStats: Statistics = {
    pending: 0,
    inProgress: 0,
    notUploaded: 0,
    uploaded: 0
  };

  @State projectStats: ProjectStat[] = [];
  @State loading: boolean = true;
  @State currentDate: string = '';

  async aboutToAppear() {
    console.log('========== MainTab 加载 ==========');
    this.updateCurrentDate();
    this.lastRefreshFlag = this.refreshFlag;
    await this.loadStatistics();
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
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const weekDay = weekDays[now.getDay()];
    this.currentDate = `${year}年${month}月${day}日 ${weekDay}`;
  }

  /**
   * ✅ 核心修复：先计算项目统计，再汇总出全局统计，确保数据绝对一致
   */
  async loadStatistics() {
    try {
      this.loading = true;
      this.updateCurrentDate();

      // 1. 加载任务
      let tasksStr = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);

      if (!tasksStr) {
        this.totalStats = { pending: 0, inProgress: 0, notUploaded: 0, uploaded: 0 };
        this.projectStats = [];
        this.loading = false;
        return;
      }

      let tasks = JSON.parse(tasksStr) as FollowUpTask[];

      // 2. 临时 Map 用于按项目归类
      let projectMap = new Map<number, ProjectStat>();

      // 3. 遍历任务，计算每个项目的统计
      for (let task of tasks) {
        let taskState = Number(task.state);
        let projectId = task.project_id || 0; // 没有ID的归为0
        let projectName = task.project_name || (projectId === 0 ? '其他项目' : `项目 ${projectId}`);

        if (!projectMap.has(projectId)) {
          projectMap.set(projectId, {
            projectId: projectId,
            projectName: projectName,
            stats: { pending: 0, inProgress: 0, notUploaded: 0, uploaded: 0 }
          });
        }

        let projectStat = projectMap.get(projectId)!;

        // 计算该任务下未上传的表单数
        let pendingUploadCount = 0;
        if (task.local_records && task.local_records.length > 0) {
          pendingUploadCount = task.local_records.filter(r => !r.is_uploaded).length;
        }

        // 累加到项目统计中
        projectStat.stats.notUploaded += pendingUploadCount;

        // 累加任务状态
        if (taskState === 0) {
          projectStat.stats.pending++;
        } else if (taskState === 1) {
          projectStat.stats.inProgress++;
        } else if (taskState === 2) {
          projectStat.stats.uploaded++;
        }
      }

      // 4. 转换为数组
      const finalProjectStats = Array.from(projectMap.values());

      // 5. ✅ 重点：基于计算好的项目列表，汇总出全局统计
      // 这样可以保证“数据概览”绝对等于“项目列表”的总和
      let finalTotalStats: Statistics = {
        pending: 0,
        inProgress: 0,
        notUploaded: 0,
        uploaded: 0
      };

      for (let proj of finalProjectStats) {
        finalTotalStats.pending += proj.stats.pending;
        finalTotalStats.inProgress += proj.stats.inProgress;
        finalTotalStats.notUploaded += proj.stats.notUploaded;
        finalTotalStats.uploaded += proj.stats.uploaded;
      }

      console.log('📊 项目统计:', JSON.stringify(finalProjectStats));
      console.log('📊 全局汇总:', JSON.stringify(finalTotalStats));

      // 6. 更新 UI 状态 (使用新对象赋值确保触发刷新)
      this.projectStats = finalProjectStats;
      this.totalStats = {
        pending: finalTotalStats.pending,
        inProgress: finalTotalStats.inProgress,
        notUploaded: finalTotalStats.notUploaded,
        uploaded: finalTotalStats.uploaded
      };

      this.loading = false;

    } catch (e) {
      console.error('❌ 加载统计失败:', e);
      this.loading = false;
    }
  }

  // ... 下面的点击处理逻辑保持不变 ...

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
      case 'notUploaded':
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

  handleStartFollow(projectId: number) {
    this.selectedProjectId = projectId;
    this.missionFilterType = 1;
    setTimeout(() => this.currentTabIndex = 1, 50);
  }

  handleViewProject(projectId: number) {
    this.selectedProjectId = projectId;
    this.missionFilterType = 0;
    setTimeout(() => this.currentTabIndex = 1, 50);
  }

  // ... build 方法保持不变 ...

  build() {
    Column() {
      // 顶部用户信息区
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
          .onClick(async () => { await this.loadStatistics(); })
      }
      .width('100%').padding({ left: 20, right: 20, top: 20, bottom: 10 }).backgroundColor('#FFFFFF')

      Scroll() {
        Column() {
          // 数据概览
          Column() {
            Text('📊 数据概览').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
              .margin({ bottom: 12 }).alignSelf(ItemAlign.Start)
            Row() {
              this.statCardBuilder('待随访', this.totalStats.pending, '#FF6B00', 'pending')
              this.statCardBuilder('进行中', this.totalStats.inProgress, '#1890FF', 'inProgress')
              this.statCardBuilder('未上传', this.totalStats.notUploaded, '#FAAD14', 'notUploaded')
              this.statCardBuilder('已完成', this.totalStats.uploaded, '#52C41A', 'uploaded')
            }
            .width('100%').justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12).margin({ top: 12, bottom: 12 })

          // 项目列表
          if (this.loading && this.projectStats.length === 0) {
            // Loading...
          } else if (this.projectStats.length === 0) {
            // Empty...
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

  @Builder
  statCardBuilder(title: string, count: number, color: string, type: string) {
    Column() {
      Text(count.toString()).fontSize(24).fontWeight(FontWeight.Bold).fontColor(color)
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
        this.projectStatItem('待随访', project.stats.pending, '#FF6B00')
        this.projectStatItem('进行中', project.stats.inProgress, '#1890FF')
        this.projectStatItem('未上传', project.stats.notUploaded, '#FAAD14')
        this.projectStatItem('已完成', project.stats.uploaded, '#52C41A')
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
}