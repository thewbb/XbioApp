/**
 * 主页 Tab - 数据概览和项目列表
 */
import { UserInfo, FollowUpTask } from '../types';
import storage, { StorageKeys } from '../utils/storage';

// 统计数据结构
interface Statistics {
  pending: number;      // 待随访（state=0）
  inProgress: number;   // 进行中（state=1）
  notUploaded: number;  // 未上传（有local_records且未上传）
  uploaded: number;     // 已完成（state=2且全部已上传或无记录）
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

  // ✅ 使用 @Link 接收父组件的状态
  @Link currentTabIndex: number;
  @Link missionFilterType: number;
  @Link logFilterType: number;

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
    await this.loadStatistics();
  }

  /**
   * 更新当前日期
   */
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
   * ✅ 加载统计数据
   */
  async loadStatistics() {
    try {
      this.loading = true;

      // 从本地存储获取任务数据
      let tasksStr = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);

      if (!tasksStr) {
        console.log('⚠️ 暂无任务数据');
        this.loading = false;
        return;
      }

      let tasks = JSON.parse(tasksStr) as FollowUpTask[];
      console.log('📋 任务总数:', tasks.length);

      // 重置统计
      this.totalStats = {
        pending: 0,
        inProgress: 0,
        notUploaded: 0,
        uploaded: 0
      };

      let projectMap = new Map<number, ProjectStat>();

      // 遍历统计
      tasks.forEach((task, index) => {
        // ✅ 确保 state 是数字类型（可能从服务器返回的是字符串）
        let taskState = Number(task.state);

        console.log(`任务 ${index + 1}:`, {
          id: task.id,
          patient_no: task.patient_no,
          state: taskState,
          原始state: task.state,
          state类型: typeof task.state,
          local_records: task.local_records?.length || 0
        });

        // ========== 全局统计 ==========

        // 1. 待随访（state === 0）
        if (taskState === 0) {
          this.totalStats.pending++;
          console.log(`  ✅ 待随访 +1，当前总数: ${this.totalStats.pending}`);
        }

        // 2. 进行中（state === 1）
        else if (taskState === 1) {
          this.totalStats.inProgress++;
          console.log(`  ✅ 进行中 +1，当前总数: ${this.totalStats.inProgress}`);
        }

        // 3. 已完成（state === 2）
        else if (taskState === 2) {
          // 检查是否所有记录都已上传
          const allUploaded = !task.local_records ||
            task.local_records.length === 0 ||
          task.local_records.every(r => r.is_uploaded);

          if (allUploaded) {
            this.totalStats.uploaded++;
            console.log(`  ✅ 已完成 +1，当前总数: ${this.totalStats.uploaded}`);
          }
        }

        // 4. 统计未上传记录（不管任务是什么状态）
        if (task.local_records && task.local_records.length > 0) {
          const notUploadedRecords = task.local_records.filter(r => !r.is_uploaded);
          if (notUploadedRecords.length > 0) {
            this.totalStats.notUploaded += notUploadedRecords.length;
            console.log(`  ✅ 未上传记录 +${notUploadedRecords.length}，当前总数: ${this.totalStats.notUploaded}`);
          }
        }

        // ========== 按项目统计 ==========
        let projectId = task.project_id;
        let projectName = task.project_name || `项目 ${projectId}`;

        if (!projectMap.has(projectId)) {
          projectMap.set(projectId, {
            projectId: projectId,
            projectName: projectName,
            stats: { pending: 0, inProgress: 0, notUploaded: 0, uploaded: 0 }
          });
        }

        let projectStat = projectMap.get(projectId)!;

        // 项目统计（逻辑同全局）
        if (taskState === 0) {
          projectStat.stats.pending++;
        } else if (taskState === 1) {
          projectStat.stats.inProgress++;
        } else if (taskState === 2) {
          const allUploaded = !task.local_records ||
            task.local_records.length === 0 ||
          task.local_records.every(r => r.is_uploaded);

          if (allUploaded) {
            projectStat.stats.uploaded++;
          }
        }

        if (task.local_records && task.local_records.length > 0) {
          const notUploadedRecords = task.local_records.filter(r => !r.is_uploaded);
          projectStat.stats.notUploaded += notUploadedRecords.length;
        }
      });

      // 转换为数组
      this.projectStats = Array.from(projectMap.values());

      console.log('========== 统计结果 ==========');
      console.log('✅ 全局统计:', {
        待随访: this.totalStats.pending,
        进行中: this.totalStats.inProgress,
        未上传: this.totalStats.notUploaded,
        已完成: this.totalStats.uploaded
      });
      console.log('✅ 项目数:', this.projectStats.length);
      this.projectStats.forEach(p => {
        console.log(`  📁 ${p.projectName}:`, {
          待随访: p.stats.pending,
          进行中: p.stats.inProgress,
          未上传: p.stats.notUploaded,
          已完成: p.stats.uploaded
        });
      });
      console.log('================================');

      this.loading = false;

    } catch (e) {
      console.error('❌ 加载统计数据失败:', e);
      console.error('错误详情:', JSON.stringify(e));
      this.loading = false;
    }
  }

  /**
   * ✅ 点击统计卡片 - 直接修改父组件状态
   */
  handleStatClick(type: string) {
    console.log('点击统计卡片:', type);

    switch (type) {
      case 'pending':
        this.missionFilterType = 1;  // ✅ 设置筛选：待执行
        this.currentTabIndex = 1;    // ✅ 切换到任务Tab
        break;
      case 'inProgress':
        this.missionFilterType = 2;  // ✅ 设置筛选：进行中
        this.currentTabIndex = 1;
        break;
      case 'notUploaded':
        this.logFilterType = 1;      // ✅ 设置筛选：未上传
        this.currentTabIndex = 2;    // ✅ 切换到记录Tab
        break;
      case 'uploaded':
        this.logFilterType = 2;      // ✅ 设置筛选：已上传
        this.currentTabIndex = 2;
        break;
    }
  }

  /**
   * ✅ 点击项目"开始随访"按钮
   */
  handleStartFollow(projectId: number) {
    console.log('开始随访，项目ID:', projectId);
    this.missionFilterType = 1;  // 筛选待执行任务
    this.currentTabIndex = 1;    // 切换到任务Tab
  }

  /**
   * ✅ 点击项目"查看详情"按钮
   */
  handleViewProject(projectId: number) {
    console.log('查看项目详情，项目ID:', projectId);
    this.missionFilterType = 0;  // 显示全部任务
    this.currentTabIndex = 1;    // 切换到任务Tab
  }

  build() {
    Column() {
      // 顶部用户信息区
      Row() {
        Column() {
          Row() {
            Text('👋 ')
              .fontSize(24)

            Text(`你好，${this.userInfo?.real_name || this.userInfo?.name || this.currentUsername}`)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
          }

          Text(this.currentDate)
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')

      // 滚动内容区
      Scroll() {
        Column() {
          // 数据概览卡片
          Column() {
            Text('📊 数据概览')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .margin({ bottom: 12 })
              .alignSelf(ItemAlign.Start)

            Row() {
              this.statCardBuilder('待随访', this.totalStats.pending, '#FF6B00', 'pending')
              this.statCardBuilder('进行中', this.totalStats.inProgress, '#1890FF', 'inProgress')
              this.statCardBuilder('未上传', this.totalStats.notUploaded, '#FAAD14', 'notUploaded')
              this.statCardBuilder('已完成', this.totalStats.uploaded, '#52C41A', 'uploaded')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ top: 12, left: 12, right: 12 })

          // 项目列表
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
            .height(200)
            .justifyContent(FlexAlign.Start)

          } else if (this.projectStats.length === 0) {
            Column() {
              Text('📁')
                .fontSize(48)
                .margin({ bottom: 12 })

              Text('暂无项目数据')
                .fontSize(14)
                .fontColor('#999999')
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Start)

          } else {
            Column() {
              Text('📁 项目列表')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333')
                .margin({ top: 16, bottom: 12, left: 12 })
                .alignSelf(ItemAlign.Start)

              ForEach(this.projectStats, (project: ProjectStat) => {
                this.projectCardBuilder(project)
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
          }

          // 底部间距
          Column()
            .height(20)
        }

      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor('#F5F5F5')
  }

  /**
   * ✅ 统计卡片构建器
   */
  @Builder
  statCardBuilder(title: string, count: number, color: string, type: string) {
    Column() {
      Text(count.toString())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)

      Text(title)
        .fontSize(12)
        .fontColor('#666666')
        .margin({ top: 4 })
    }
    .width('22%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor('#F7F8FA')
    .borderRadius(8)
    .onClick(() => {
      this.handleStatClick(type);
    })
  }

  /**
   * ✅ 项目卡片构建器
   */
  @Builder
  projectCardBuilder(project: ProjectStat) {
    Column() {
      // 项目标题
      Row() {
        Text('🏥')
          .fontSize(20)
          .margin({ right: 8 })

        Column() {
          Text(project.projectName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')

          Text(`项目ID: ${project.projectId}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 分隔线
      Divider()
        .color('#EEEEEE')
        .margin({ bottom: 12 })

      // 统计数据
      Row() {
        this.projectStatItem('📌 待随访', project.stats.pending, '#FF6B00')
        this.projectStatItem('⏱️ 进行中', project.stats.inProgress, '#1890FF')
        this.projectStatItem('📤 未上传', project.stats.notUploaded, '#FAAD14')
        this.projectStatItem('✅ 已完成', project.stats.uploaded, '#52C41A')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 操作按钮
      Row() {
        Button('查看详情')
          .fontSize(14)
          .fontColor('#666666')
          .backgroundColor('#F7F8FA')
          .height(36)
          .layoutWeight(1)
          .onClick(() => {
            this.handleViewProject(project.projectId);
          })

        Blank()
          .width(12)

        Button('开始随访')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#FF6B00')
          .height(36)
          .layoutWeight(1)
          .onClick(() => {
            this.handleStartFollow(project.projectId);
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12, left: 12, right: 12 })
  }

  /**
   * ✅ 项目统计项
   */
  @Builder
  projectStatItem(label: string, count: number, color: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor('#666666')

      Text(count.toString())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 4 })
    }
    .width('23%')
  }
}