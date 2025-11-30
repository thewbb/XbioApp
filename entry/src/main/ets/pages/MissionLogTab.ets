/**
 * 记录页 (MissionLogTab)
 * 功能：
 * 1. 展示待上传的任务列表（聚合显示）
 * 2. 执行批量上传操作
 * 3. 筛选已上传/未上传
 */
import router from '@ohos.router';
import { FollowUpTask, FormRecord, BatchUploadMissionRequest, UploadRecordItem, BatchUploadMissionResponse } from '../types';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { CustomToast, ToastController } from '../components/CustomToast';

@Component
export default struct MissionLogTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @Link filterType: number; // 0=全部, 1=未上传, 2=已上传
  @Prop refreshFlag: number = 0;

  @State tasks: FollowUpTask[] = [];
  @State loading: boolean = false;
  @State isUploading: boolean = false;
  @State uploadProgress: string = '';
  @State toastController: ToastController = new ToastController();

  // 下拉刷新状态
  @State isRefreshing: boolean = false;

  // 上一次刷新标志
  private lastRefreshFlag: number = 0;

  async aboutToAppear() {
    console.log('========== MissionLogTab 加载 ==========');
    await this.loadData();
    this.lastRefreshFlag = this.refreshFlag;
  }

  /**
   * 监听外部刷新请求
   */
  aboutToUpdate() {
    if (this.refreshFlag !== this.lastRefreshFlag) {
      console.log('🔄 记录页刷新数据');
      this.lastRefreshFlag = this.refreshFlag;
      this.loadData();
    }
  }

  /**
   * 加载本地任务数据
   */
  async loadData() {
    try {
      this.loading = true;
      const tasksStr = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);
      if (tasksStr) {
        this.tasks = JSON.parse(tasksStr) as FollowUpTask[];
      } else {
        this.tasks = [];
      }
      this.loading = false;
    } catch (e) {
      console.error('加载记录失败:', e);
      this.tasks = [];
      this.loading = false;
    }
  }

  /**
   * 下拉刷新
   */
  async handleRefresh() {
    this.isRefreshing = true;
    await this.loadData();
    setTimeout(() => {
      this.isRefreshing = false;
      this.toastController.show('已刷新');
    }, 500);
  }

  /**
   * 核心筛选逻辑
   * @param type 1=未上传(含部分未上传), 2=已上传(全部已上传)
   */
  getFilteredTasks(): FollowUpTask[] {
    if (!this.tasks || this.tasks.length === 0) return [];

    return this.tasks.filter(task => {
      // 必须有本地记录才显示在日志页
      if (!task.local_records || task.local_records.length === 0) {
        return false;
      }

      const hasUnuploaded = task.local_records.some(r => !r.is_uploaded);

      if (this.filterType === 1) {
        // 筛选未上传：只要有一条记录未上传，就算未上传任务
        return hasUnuploaded;
      } else if (this.filterType === 2) {
        // 筛选已上传：所有记录都必须已上传
        return !hasUnuploaded;
      }

      // 全部：只要有记录就显示
      return true;
    });
  }

  /**
   * 检查任务是否可以上传
   * 条件：已签名 + 有未上传的表单数据
   */
  canUpload(task: FollowUpTask): boolean {
    // 1. 必须有未上传的数据
    const hasPendingRecords = task.local_records?.some(r => !r.is_uploaded) || false;
    if (!hasPendingRecords) return false;

    // 2. 必须已签名 (本地有签名数据 或 状态已是进行中/完成)
    // 注意：后端逻辑是上传时带上 sign，所以本地必须有 sign 数据
    const hasSignature = !!task.consent_signature;

    return hasSignature;
  }

  /**
   * 获取未上传的表单数量
   */
  getPendingCount(task: FollowUpTask): number {
    return task.local_records?.filter(r => !r.is_uploaded).length || 0;
  }

  /**
   * 执行批量上传
   */
  async handleUpload(task: FollowUpTask) {
    if (this.isUploading) return;

    // 二次检查
    if (!task.consent_signature) {
      this.toastController.show('请先签署知情同意书');
      return;
    }

    // 获取需要上传的记录
    const pendingRecords = task.local_records?.filter(r => !r.is_uploaded);
    if (!pendingRecords || pendingRecords.length === 0) {
      this.toastController.show('没有需要上传的数据');
      return;
    }

    try {
      this.isUploading = true;
      this.uploadProgress = '准备上传...';
      console.log(`🚀 开始上传任务 [${task.patient_no}]，共 ${pendingRecords.length} 条表单`);

      // 1. 构造请求数据
      const uploadItems: UploadRecordItem[] = [];

      // 遍历待上传记录，找到对应的表单配置
      for (let record of pendingRecords) {
        const table = task.project?.tables?.find(t => t.id === record.table_id);

        // 即使找不到 table 配置（极少情况），只要有数据也尝试上传
        // 注意：data 字段需要是 JSON 字符串格式
        uploadItems.push({
          table_name: table?.table_name || '', // 此时可能为空，依赖后端校验或 table_id
          table_id: record.table_id,
          sub_step_id: record.step_id,
          multi_line: table?.multi_line?.toString() || '0',
          data: JSON.stringify(record.data) // 将 Map/Record 对象转为 JSON 字符串
        });
      }

      // 构造完整请求
      const requestData: BatchUploadMissionRequest = {
        token: this.currentToken,
        mission_id: task.id,
        patient_no: task.patient_no,
        // 只有当知情同意书是在本地新签的（有图片数据），才传 sign
        sign: task.consent_signature.signature_image || undefined,
        records: uploadItems
      };

      this.uploadProgress = '正在上传...';

      // 2. 发送请求
      const response = await http.post('/mobile/batchUploadMission.json', requestData);

      console.log('上传响应:', JSON.stringify(response));

      // 3. 处理响应
      if (response.code === 0) {
        this.uploadProgress = '更新状态...';

        // 标记本地记录为已上传
        const updatedRecords = task.local_records!.map(r => {
          // 如果该记录在本次上传列表中，则标记为已上传
          const isUploaded = pendingRecords.some(pr => pr.table_id === r.table_id);
          if (isUploaded) {
            return {
              table_id: r.table_id,
              step_id: r.step_id,
              data: r.data,
              filled_time: r.filled_time,
              is_uploaded: true
            };
          }
          return r;
        });

        // 更新任务对象
        task.local_records = updatedRecords;

        // 更新任务状态（如果全部传完了）
        const allUploaded = updatedRecords.every(r => r.is_uploaded);
        if (allUploaded && task.state !== 2) {
          // 可选：如果全部上传完毕，可以更新任务状态显示为"已完成"（视业务逻辑而定）
          // task.state = 2;
        }

        // 保存回本地存储
        let allTasks = await storage.loadFollowUpTasks(this.currentUsername);
        const taskIndex = allTasks.findIndex(t => t.id === task.id);
        if (taskIndex !== -1) {
          allTasks[taskIndex] = task;
          await storage.saveFollowUpTasks(this.currentUsername, allTasks);
        }

        // 刷新界面
        this.tasks = [...allTasks]; // 触发UI更新

        this.toastController.show(`✅ 上传成功`);
      } else {
        const errorMsg = response.message || '上传失败';
        console.error('❌ 上传失败:', errorMsg);

        // 如果有具体的失败表单信息，可以展示
        if (response.dataMap && response.dataMap['failed_tables']) {
          const failedArr = response.dataMap['failed_tables'] as string[];
          this.toastController.show(`部分失败: ${failedArr.join(',')}`);
        } else {
          this.toastController.show(errorMsg);
        }
      }

    } catch (e) {
      console.error('❌ 上传异常:', e);
      this.toastController.show('网络异常，上传失败');
    } finally {
      this.isUploading = false;
      this.uploadProgress = '';
    }
  }

  /**
   * 跳转到详情页查看
   */
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

  build() {
    Stack() {
      Column() {
        // 筛选栏
        Row() {
          Button('全部')
            .fontSize(14)
            .height(32)
            .backgroundColor(this.filterType === 0 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.filterType === 0 ? '#FFFFFF' : '#666666')
            .borderRadius(16)
            .onClick(() => this.filterType = 0)

          Button('待上传')
            .fontSize(14)
            .height(32)
            .margin({ left: 12 })
            .backgroundColor(this.filterType === 1 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.filterType === 1 ? '#FFFFFF' : '#666666')
            .borderRadius(16)
            .onClick(() => this.filterType = 1)

          Button('已上传')
            .fontSize(14)
            .height(32)
            .margin({ left: 12 })
            .backgroundColor(this.filterType === 2 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.filterType === 2 ? '#FFFFFF' : '#666666')
            .borderRadius(16)
            .onClick(() => this.filterType = 2)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#FFFFFF')
        .border({ width: { bottom: 0.5 }, color: '#E5E5E5' })

        // 列表区域
        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40)
            Text('加载记录中...').fontSize(14).fontColor('#999999').margin({ top: 10 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
        else if (this.getFilteredTasks().length === 0) {
          Column() {
            Text('📭').fontSize(60).margin({ bottom: 10 })
            Text('暂无相关记录').fontSize(14).fontColor('#999999')
            if (this.filterType === 2) {
              Text('只有上传成功的任务才会显示在这里').fontSize(12).fontColor('#CCCCCC').margin({ top: 5 })
            }
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
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
            .width('100%')
            .layoutWeight(1)
            .padding(16)
            .backgroundColor('#F5F5F5')
          }
          .onRefreshing(() => this.handleRefresh())
        }
      }
      .width('100%')
      .height('100%')

      // 全局 Loading 遮罩 (上传时显示)
      if (this.isUploading) {
        Column() {
          LoadingProgress().width(50).height(50).color(Color.White)
          Text(this.uploadProgress)
            .fontSize(16)
            .fontColor(Color.White)
            .margin({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .zIndex(999)
      }

      CustomToast({ controller: this.toastController })
    }
  }

  /**
   * 单个任务记录卡片
   */
  @Builder
  RecordCard(task: FollowUpTask) {
    Column() {
      // 1. 标题行：患者编号 + 状态标记
      Row() {
        Column() {
          Text(task.patient_no)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')

          Text(`项目：${task.project_name}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 状态徽标
        if (this.getPendingCount(task) > 0) {
          Text('待上传')
            .fontSize(12)
            .fontColor('#FF6B00')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#FFF7E6')
            .borderRadius(4)
            .border({ width: 1, color: '#FFD591' })
        } else {
          Text('已上传')
            .fontSize(12)
            .fontColor('#52C41A')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#F6FFED')
            .borderRadius(4)
            .border({ width: 1, color: '#B7EB8F' })
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      Divider().color('#F0F0F0').margin({ bottom: 12 })

      // 2. 内容详情：表单数量统计 + 签名状态
      Row() {
        // 左侧：统计信息
        Column() {
          Row() {
            Text('表单数据：').fontSize(13).fontColor('#666666')
            Text(`${task.local_records?.length || 0} 份`).fontSize(13).fontColor('#333333')
          }.margin({ bottom: 6 })

          Row() {
            Text('未上传：').fontSize(13).fontColor('#666666')
            Text(`${this.getPendingCount(task)} 份`)
              .fontSize(13)
              .fontColor(this.getPendingCount(task) > 0 ? '#FF6B00' : '#999999')
              .fontWeight(this.getPendingCount(task) > 0 ? FontWeight.Bold : FontWeight.Normal)
          }.margin({ bottom: 6 })

          Row() {
            Text('知情同意书：').fontSize(13).fontColor('#666666')
            if (task.consent_signature) {
              Text('已签署').fontSize(13).fontColor('#52C41A')
            } else {
              Text('未签署').fontSize(13).fontColor('#FF4D4F')
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 右侧：操作按钮
        Column() {
          if (this.getPendingCount(task) > 0) {
            // 待上传状态
            Button('立即上传')
              .fontSize(14)
              .height(32)
              .backgroundColor('#FF6B00')
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .enabled(this.canUpload(task)) // 只有签名后才能点击
              .opacity(this.canUpload(task) ? 1 : 0.5)
              .onClick(() => {
                if (!this.canUpload(task)) {
                  this.toastController.show('请先进入详情页签署知情同意书');
                } else {
                  this.handleUpload(task);
                }
              })
          } else {
            // 已上传状态
            Button('查看详情')
              .fontSize(14)
              .height(32)
              .backgroundColor('#FFFFFF')
              .fontColor('#666666')
              .border({ width: 1, color: '#CCCCCC' })
              .borderRadius(16)
              .onClick(() => this.handleViewDetail(task))
          }
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')

      // 如果未签名，显示提示条
      if (this.getPendingCount(task) > 0 && !task.consent_signature) {
        Row() {
          Text('⚠️ 需签署知情同意书后方可上传').fontSize(12).fontColor('#FF4D4F')
        }
        .width('100%')
        .padding({ top: 8 })
        .onClick(() => this.handleViewDetail(task)) // 点击提示也可以跳转去签名
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 4, color: '#0000000D', offsetY: 2 })
  }
}