/**
 * 记录页 (MissionLogTab) - 修复签名同步问题 & 优化显示逻辑 & 添加长按删除功能
 */
import router from '@ohos.router';
import { FollowUpTask, FormRecord, BatchUploadMissionRequest, UploadRecordItem } from '../types';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { CustomToast, ToastController } from '../components/CustomToast';

// 临时接口，用于类型检查 table 结构
interface TempTable { id: number; }

@Component
export default struct MissionLogTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @Link filterType: number; // 0=全部, 1=未上传, 2=已上传

  // 监听来自父组件的刷新信号
  @Prop @Watch('onRefreshFlagChange') refreshFlag: number = 0;

  @State tasks: FollowUpTask[] = [];
  @State loading: boolean = false;
  @State isUploading: boolean = false;
  @State uploadProgress: string = '';
  @State toastController: ToastController = new ToastController();
  @State isRefreshing: boolean = false;

  // ✅ 新增：删除确认对话框相关状态
  @State showDeleteDialog: boolean = false;
  @State taskToDelete: FollowUpTask | null = null;

  async aboutToAppear() {
    await this.loadData();
  }

  onRefreshFlagChange() {
    this.loadData();
  }

  async loadData() {
    try {
      const tasksStr = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);
      console.log(JSON.stringify(tasksStr));
      if (tasksStr) {
        const loadedTasks = JSON.parse(tasksStr) as FollowUpTask[];
        this.tasks = [...loadedTasks];
      } else {
        this.tasks = [];
      }
    } catch (e) {
      this.tasks = [];
    }
  }

  async handleRefresh() {
    this.isRefreshing = true;
    await this.loadData();
    setTimeout(() => {
      this.isRefreshing = false;
      this.toastController.show('已刷新');
    }, 500);
  }

  /**
   * 核心筛选与排序逻辑
   * 规则：
   * 1. 只有"本地有记录"的任务才会显示
   * 2. 排序：未上传的排在最前面，已上传的排在后面
   */
  getFilteredTasks(): FollowUpTask[] {
    if (!this.tasks || this.tasks.length === 0) return [];

    // 1. 先筛选
    let filtered = this.tasks.filter(task => {
      // 必须有本地表单记录
      if (!task.local_records || task.local_records.length === 0) {
        return false;
      }

      const hasUnuploaded = task.local_records.some(r => !r.is_uploaded);

      if (this.filterType === 1) { // 仅显示待上传
        return hasUnuploaded;
      } else if (this.filterType === 2) { // 仅显示已上传
        return !hasUnuploaded;
      }
      return true; // 全部显示
    });

    // 2. 后排序
    // sort 返回负数表示 a 排在 b 前面
    filtered.sort((a, b) => {
      const aPending = this.getPendingCount(a) > 0; // a 是否待上传
      const bPending = this.getPendingCount(b) > 0; // b 是否待上传

      if (aPending && !bPending) {
        return -1; // a 待上传，b 已上传 -> a 排前
      }
      if (!aPending && bPending) {
        return 1; // a 已上传，b 待上传 -> b 排前
      }

      // 如果状态相同（都是待上传，或都是已上传），则按任务创建时间倒序排列（最新的在上面）
      // 假设有 create_time 字段，是字符串比较
      if (a.create_time && b.create_time) {
        return b.create_time.localeCompare(a.create_time);
      }

      return 0;
    });

    return filtered;
  }

  hasConsent(task: FollowUpTask): boolean {
    return !!task.consent_signature;
  }

  getPendingCount(task: FollowUpTask): number {
    return task.local_records?.filter(r => !r.is_uploaded).length || 0;
  }

  /**
   * ✅ 新增：获取未完成的表单数量
   * 逻辑：项目总表单数 - 本地已填写的表单数(去重后)
   */
  getUnfinishedCount(task: FollowUpTask): number {
    if (!task.project || !task.project.tables) return 0;

    const totalTables = task.project.tables.length;

    // 计算本地已填写的唯一 table_id 数量
    const filledTableIds = new Set<number>();
    if (task.local_records) {
      task.local_records.forEach((r: FormRecord) => {
        filledTableIds.add(r.table_id);
      });
    }

    const filledCount = filledTableIds.size;

    // 剩余未填写的数量 (不小于0)
    return Math.max(0, totalTables - filledCount);
  }

  /**
   * ✅ 修改：检查任务是否可以上传
   * 条件：已签名 + 有未上传数据 + 所有表单都填完了(未完成数==0)
   */
  canUpload(task: FollowUpTask): boolean {
    const hasPendingRecords = this.getPendingCount(task) > 0;
    const signed = this.hasConsent(task);
    const allFinished = this.getUnfinishedCount(task) === 0;

    return hasPendingRecords && signed && allFinished;
  }

  async handleUpload(task: FollowUpTask) {
    if (this.isUploading) return;

    // 1. 检查是否全部填完
    if (this.getUnfinishedCount(task) > 0) {
      this.toastController.show(`还有 ${this.getUnfinishedCount(task)} 份表单未填写，请先完成`);
      return;
    }

    // 2. 检查签名
    if (!this.hasConsent(task)) {
      this.toastController.show('请先进入详情页签署知情同意书');
      return;
    }

    const pendingRecords = task.local_records?.filter(r => !r.is_uploaded);
    if (!pendingRecords || pendingRecords.length === 0) {
      this.toastController.show('没有需要上传的数据');
      return;
    }

    try {
      this.isUploading = true;
      this.uploadProgress = '正在上传...';

      const uploadItems: UploadRecordItem[] = [];
      for (let record of pendingRecords) {
        const table = task.project?.tables?.find(t => t.id === record.table_id);
        uploadItems.push({
          table_name: table?.table_name || '',
          table_id: record.table_id,
          sub_step_id: record.step_id,
          multi_line: table?.multi_line?.toString() || '0',
          data: JSON.stringify(record.data)
        });
      }

      const requestData: BatchUploadMissionRequest = {
        token: this.currentToken,
        mission_id: task.id,
        patient_no: task.patient_no,
        sign: task.consent_signature?.signature_image || undefined,
        sign_at: task.consent_signature ? task.consent_signature.signature_time : '',
        records: uploadItems
      };

      const response = await http.post('/mobile/batchUploadMission.json', requestData);

      if (response.code === 0) {
        this.uploadProgress = '保存状态...';

        const updatedRecords = task.local_records!.map((r: FormRecord) => {
          const isUploaded = pendingRecords.some(pr => pr.table_id === r.table_id);
          if (isUploaded) {
            return {
              table_id: r.table_id,
              step_id: r.step_id,
              data: r.data,
              filled_time: r.filled_time,
              is_uploaded: true
            } as FormRecord;
          }
          return r;
        });
        task.local_records = updatedRecords;

        let allTasks = await storage.loadFollowUpTasks(this.currentUsername);
        const taskIndex = allTasks.findIndex(t => t.id === task.id);
        if (taskIndex !== -1) {
          allTasks[taskIndex] = task;
          await storage.saveFollowUpTasks(this.currentUsername, allTasks);
        }

        this.tasks = [...allTasks];
        this.toastController.show(`✅ 上传成功`);
      } else {
        this.toastController.show(response.message || '上传失败');
      }

    } catch (e) {
      this.toastController.show('网络异常，上传失败');
    } finally {
      this.isUploading = false;
    }
  }

  handleViewDetail(task: FollowUpTask) {
    router.pushUrl({
      url: 'pages/MissionPage',
      params: {
        task: task,
        token: this.currentToken,
        username: this.currentUsername
      }
    });
  }

  /**
   * ✅ 新增：长按触发删除确认
   */
  handleLongPress(task: FollowUpTask) {
    this.taskToDelete = task;
    this.showDeleteDialog = true;
  }

  /**
   * ✅ 新增：确认删除任务的所有本地记录
   */
  async confirmDelete() {
    if (!this.taskToDelete) {
      return;
    }

    try {
      const task = this.taskToDelete;

      // 检查是否有未上传的数据
      const hasUnuploaded = this.getPendingCount(task) > 0;

      console.log(`删除任务记录: ID=${task.id}, 患者=${task.patient_no || task.name}`);

      // 1. 加载所有任务
      let allTasks = await storage.loadFollowUpTasks(this.currentUsername);

      // 2. 找到对应任务
      const taskIndex = allTasks.findIndex(t => t.id === task.id);
      if (taskIndex === -1) {
        this.toastController.show('任务不存在');
        this.showDeleteDialog = false;
        this.taskToDelete = null;
        return;
      }

      // 3. 清空该任务的本地记录和签名
      allTasks[taskIndex].local_records = [];
      allTasks[taskIndex].consent_signature = undefined;

      // 4. 重置表单状态
      if (allTasks[taskIndex].project && allTasks[taskIndex].project!.tables) {
        allTasks[taskIndex].project!.tables.forEach(table => {
          table.state = 0;  // 重置为未填写
        });
      }

      // 5. 重置任务进度
      allTasks[taskIndex].percent = '0';
      allTasks[taskIndex].state = 0;

      // 6. 保存到本地
      await storage.saveFollowUpTasks(this.currentUsername, allTasks);

      // 7. 刷新列表
      this.tasks = [...allTasks];

      // 8. 显示提示
      if (hasUnuploaded) {
        this.toastController.show('✅ 已删除（包含未上传数据）');
      } else {
        this.toastController.show('✅ 已删除');
      }

      console.log('✅ 删除成功');

    } catch (e) {
      console.error('❌ 删除失败:', e);
      this.toastController.show('删除失败');
    } finally {
      this.showDeleteDialog = false;
      this.taskToDelete = null;
    }
  }

  /**
   * ✅ 新增：取消删除
   */
  cancelDelete() {
    this.showDeleteDialog = false;
    this.taskToDelete = null;
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Button('全部').fontSize(13).height(28)
            .backgroundColor(this.filterType === 0 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.filterType === 0 ? '#FFFFFF' : '#666666')
            .onClick(() => this.filterType = 0)

          Button('待上传').fontSize(13).height(28).margin({ left: 12 })
            .backgroundColor(this.filterType === 1 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.filterType === 1 ? '#FFFFFF' : '#666666')
            .onClick(() => this.filterType = 1)

          Button('已上传').fontSize(13).height(28).margin({ left: 12 })
            .backgroundColor(this.filterType === 2 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.filterType === 2 ? '#FFFFFF' : '#666666')
            .onClick(() => this.filterType = 2)
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#FFFFFF').border({ width: { bottom: 0.5 }, color: '#E5E5E5' })

        if (this.loading && this.tasks.length === 0) {
          Column() {
            LoadingProgress().width(40).height(40)
            Text('加载中...').fontSize(14).fontColor('#999999').margin({ top: 10 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
        else if (this.getFilteredTasks().length === 0) {
          Column() {
            Text('📭').fontSize(48).margin({ bottom: 10 })
            Text('暂无记录').fontSize(14).fontColor('#999999')
            Text('填写并保存表单后会显示在这里').fontSize(12).fontColor('#CCCCCC').margin({ top: 5 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
        else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ space: 12 }) {
              ForEach(this.getFilteredTasks(), (task: FollowUpTask) => {
                ListItem() {
                  this.RecordCard(task)
                }
              })
            }
            .width('100%').layoutWeight(1).padding(16).backgroundColor('#F5F5F5')
          }
          .onRefreshing(() => this.handleRefresh())
        }
      }
      .width('100%').height('100%')

      // ✅ 上传进度蒙层
      if (this.isUploading) {
        Column() {
          LoadingProgress().width(50).height(50).color(Color.White)
          Text(this.uploadProgress).fontSize(16).fontColor(Color.White).margin({ top: 16 })
        }.width('100%').height('100%')
        .backgroundColor('#80000000').justifyContent(FlexAlign.Center).zIndex(999)
      }

      // ✅ 删除确认对话框
      if (this.showDeleteDialog) {
        Column() {
          Column() {
            // 标题
            Text('确认删除？').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
              .margin({ bottom: 16 })

            // 内容
            Column() {
              if (this.taskToDelete) {
                Text(`患者：${this.taskToDelete.name || this.taskToDelete.patient_no || '未知'}`)
                  .fontSize(14).fontColor('#666666').margin({ bottom: 8 })
                Text(`项目：${this.taskToDelete.project_name || '未知项目'}`)
                  .fontSize(14).fontColor('#666666').margin({ bottom: 8 })

                Divider().color('#F0F0F0').margin({ top: 8, bottom: 8 })

                // 警告提示
                Row() {
                  Text('⚠️').fontSize(16).margin({ right: 6 })
                  Column() {
                    Text('将删除该任务的所有本地记录：')
                      .fontSize(13).fontColor('#FF4D4F').margin({ bottom: 4 })
                    Text(`• 表单数据（${this.taskToDelete.local_records?.length || 0} 份）`)
                      .fontSize(12).fontColor('#999999').margin({ bottom: 2 })
                    if (this.hasConsent(this.taskToDelete)) {
                      Text('• 知情同意书签名')
                        .fontSize(12).fontColor('#999999').margin({ bottom: 2 })
                    }
                    if (this.getPendingCount(this.taskToDelete) > 0) {
                      Text(`• 未上传数据（${this.getPendingCount(this.taskToDelete)} 份）`)
                        .fontSize(12).fontColor('#FF4D4F').fontWeight(FontWeight.Medium)
                    }
                  }.alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#FFF7F0')
                .borderRadius(8)
                .alignItems(VerticalAlign.Top)
              }
            }
            .width('100%')
            .margin({ bottom: 20 })

            // 按钮
            Row() {
              Button('取消')
                .fontSize(15)
                .height(44)
                .layoutWeight(1)
                .backgroundColor('#F5F5F5')
                .fontColor('#666666')
                .borderRadius(8)
                .onClick(() => this.cancelDelete())

              Button('确认删除')
                .fontSize(15)
                .height(44)
                .layoutWeight(1)
                .backgroundColor('#FF4D4F')
                .fontColor('#FFFFFF')
                .borderRadius(8)
                .margin({ left: 12 })
                .onClick(() => this.confirmDelete())
            }
            .width('100%')
          }
          .width('85%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .shadow({ radius: 20, color: '#00000030', offsetY: 4 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .zIndex(1000)
      }

      CustomToast({ controller: this.toastController })
    }
  }

  @Builder
  RecordCard(task: FollowUpTask) {
    Column() {
      // 1. 头部
      Row() {
        Column() {
          Text(task.patient_no + "("+task.name+")" || '未知编号')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(task.patient_no ? '#333333' : '#999999')
          Text(`项目：${task.project_name || '未知项目'}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
        }.alignItems(HorizontalAlign.Start)

        Blank()

        if (this.getPendingCount(task) > 0) {
          Text('待上传').fontSize(11).fontColor('#FF6B00')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#FFF7E6').borderRadius(4)
        } else {
          Text('已上传').fontSize(11).fontColor('#52C41A')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#F6FFED').borderRadius(4)
        }
      }.width('100%').margin({ bottom: 12 })

      Divider().color('#F0F0F0').margin({ bottom: 12 })

      // 2. 详情统计
      Row() {
        Column() {
          // ✅ 修改点：显示待完成表单数量
          Row() {
            Text('待填表单：').fontSize(13).fontColor('#666666')
            if (this.getUnfinishedCount(task) > 0) {
              Text(`${this.getUnfinishedCount(task)} 份`).fontSize(13).fontColor('#FF4D4F').fontWeight(FontWeight.Bold)
            } else {
              Text('已完成').fontSize(13).fontColor('#52C41A')
            }
          }.margin({ bottom: 6 })

          Row() {
            Text('知情同意书：').fontSize(13).fontColor('#666666')
            if (this.hasConsent(task)) {
              Text('已签署').fontSize(13).fontColor('#52C41A')
            } else {
              Text('未签署').fontSize(13).fontColor('#FF4D4F')
            }
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

        // 3. 操作按钮区域
        Column() {
          if (this.getPendingCount(task) > 0) {
            // 待上传状态
            Button('上传数据')
              .fontSize(13)
              .height(30)
              .backgroundColor(this.canUpload(task) ? '#FF6B00' : '#CCCCCC')
              .fontColor('#FFFFFF')
              .borderRadius(15)
              .onClick(() => {
                if (this.getUnfinishedCount(task) > 0) {
                  this.toastController.show(`还有 ${this.getUnfinishedCount(task)} 份表单未填写`);
                } else if (!this.hasConsent(task)) {
                  this.toastController.show('请先点击下方提示签署同意书');
                } else {
                  this.handleUpload(task);
                }
              })
          } else {
            // 已上传状态
            Button('查看详情')
              .fontSize(13)
              .height(30)
              .backgroundColor('#FFFFFF')
              .fontColor('#666666')
              .border({ width: 1, color: '#E5E5E5' })
              .borderRadius(15)
              .onClick(() => this.handleViewDetail(task))
          }
        }
      }.width('100%')

      // 4. 底部提示条 (红字提示)
      Column() {
        // 提示1：未填完表单
        if (this.getUnfinishedCount(task) > 0) {
          Row() {
            Text(`⚠️ 需填写剩余 ${this.getUnfinishedCount(task)} 份表单方可上传，点击填写 ›`).fontSize(12).fontColor('#FF4D4F')
          }
          .width('100%').padding({ top: 8 }).justifyContent(FlexAlign.Start)
          .onClick(() => this.handleViewDetail(task))
        }
        // 提示2：未签名 (如果表单填完了但没签名)
        else if (this.getPendingCount(task) > 0 && !this.hasConsent(task)) {
          Row() {
            Text('⚠️ 待签署知情同意书，点击前往签署 ›').fontSize(12).fontColor('#FF4D4F')
          }
          .width('100%').padding({ top: 8 }).justifyContent(FlexAlign.Start)
          .onClick(() => this.handleViewDetail(task))
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .margin({ bottom: 0 })
    .shadow({ radius: 4, color: '#00000005', offsetY: 1 })
    // ✅ 添加长按手势
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.handleLongPress(task);
        })
    )
  }
}