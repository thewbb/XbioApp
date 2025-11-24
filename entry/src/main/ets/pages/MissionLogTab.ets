/**
 * 记录列表 Tab - 按任务批量上传（带刷新支持）
 *
 * 功能：
 * - 显示所有本地保存的表单记录
 * - 筛选：全部/未上传/已上传
 * - 按任务批量上传数据（包含签名）
 * - 查看记录详情
 * - 删除记录
 * - ✅ 支持切换 Tab 自动刷新
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import {
  FollowUpTask,
  FormRecord,
  FormTable,
  BatchUploadMissionRequest,
  UploadRecordItem,
  BatchUploadResult,
  UploadTaskResult
} from '../types';
import http from '../utils/http';
import { CustomToast, ToastController } from '../components/CustomToast';

/**
 * ✅ 批量上传任务数据
 */
async function batchUploadMission(request: BatchUploadMissionRequest): Promise<BatchUploadResult> {
  try {
    console.log('📤 批量上传任务数据:', {
      mission_id: request.mission_id,
      patient_no: request.patient_no,
      has_sign: !!request.sign,
      records_count: request.records.length
    });

    let response = await http.post('/mobile/batchUploadMission.json', request);
    console.log('上传响应:', response);

    if (response.code === 0) {
      return {
        success: true,
        message: response.message || '上传成功',
        result: response.dataMap
      };
    } else {
      return {
        success: false,
        message: response.message || '上传失败',
        result: response.dataMap
      };
    }
  } catch (err) {
    const e = err as Error;
    console.error('❌ 批量上传异常:', e.message);
    return {
      success: false,
      message: '上传异常: ' + e.message,
      result: undefined
    };
  }
}

/**
 * ✅ 记录项（包含任务信息）
 */
interface RecordItem {
  task: FollowUpTask;
  record: FormRecord;
  taskId: number;
}

@Component
export default struct MissionLogTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @Link filterType: number;

  // ✅ 新增：监听刷新标志
  @Prop refreshFlag: number = 0;

  // ✅ 用于检测 refreshFlag 变化
  private lastRefreshFlag: number = 0;

  @State records: RecordItem[] = [];
  @State currentFilterIndex: number = 0;
  @State loading: boolean = false;
  @State uploading: boolean = false;
  @State toastController: ToastController = new ToastController();

  // 删除确认对话框
  @State showDeleteDialog: boolean = false;
  @State recordToDelete: RecordItem | null = null;

  // 签名缺失提示对话框
  @State showSignatureMissingDialog: boolean = false;
  @State missingSignatureTasks: FollowUpTask[] = [];

  async aboutToAppear() {
    console.log('========== MissionLogTab 加载 ==========');
    this.lastRefreshFlag = this.refreshFlag;
    await this.loadRecords();
  }

  /**
   * ✅ 监听 refreshFlag 变化
   */
  async aboutToUpdate() {
    if (this.refreshFlag !== this.lastRefreshFlag && this.refreshFlag > 0) {
      console.log('🔄 MissionLogTab 检测到刷新标志变化:', this.lastRefreshFlag, '→', this.refreshFlag);
      this.lastRefreshFlag = this.refreshFlag;
      await this.loadRecords();
    }
  }

  /**
   * ✅ 加载所有任务的本地记录
   */
  async loadRecords() {
    try {
      console.log('🔄 MissionLogTab 开始刷新数据...');
      this.loading = true;

      let tasksStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.FOLLOW_UP_TASKS
      );

      if (!tasksStr) {
        console.log('⚠️ 本地暂无任务数据');
        this.records = [];
        this.loading = false;
        return;
      }

      // ✅ 同步 filterType 到 currentFilterIndex
      if (this.filterType > 0) {
        this.currentFilterIndex = this.filterType;
        console.log('✅ 同步筛选类型:', this.filterType);
      }

      const tasks: FollowUpTask[] = JSON.parse(tasksStr);
      console.log('任务数量:', tasks.length);

      const allRecords: RecordItem[] = [];

      for (let task of tasks) {
        if (task.local_records && task.local_records.length > 0) {
          task.local_records.forEach(record => {
            allRecords.push({
              task: task,
              record: record,
              taskId: task.id
            });
          });
        }
      }

      // 按时间倒序排序
      allRecords.sort((a, b) => {
        const timeA = new Date(a.record.filled_time).getTime();
        const timeB = new Date(b.record.filled_time).getTime();
        return timeB - timeA;
      });

      this.records = allRecords;
      console.log('✅ 加载记录成功:', this.records.length, '条');

      this.loading = false;
    } catch (e) {
      console.error('❌ 加载记录失败:', e);
      this.records = [];
      this.loading = false;
    }
  }

  /**
   * ✅ 获取筛选后的记录
   */
  getFilteredRecords(): RecordItem[] {
    switch (this.currentFilterIndex) {
      case 1:
        return this.records.filter(r => !r.record.is_uploaded);
      case 2:
        return this.records.filter(r => r.record.is_uploaded);
      default:
        return this.records;
    }
  }

  /**
   * ✅ 获取表单信息
   */
  getTableInfo(record: RecordItem): FormTable | undefined {
    if (!record.task.project || !record.task.project.tables) {
      return undefined;
    }

    const tables: FormTable[] = record.task.project.tables;
    for (let i = 0; i < tables.length; i++) {
      if (tables[i].id === record.record.table_id) {
        return tables[i];
      }
    }

    return undefined;
  }

  /**
   * ✅ 获取表单名称
   */
  getTableName(record: RecordItem): string {
    const table = this.getTableInfo(record);
    return table ? table.step_name : '未知表单';
  }

  /**
   * ✅ 检查任务是否有签名
   */
  hasSignature(task: FollowUpTask): boolean {
    if (!task.consent_signature) {
      return false;
    }

    const signature = task.consent_signature;

    if (!signature.signature_image || signature.signature_image.trim().length === 0) {
      return false;
    }

    return true;
  }

  /**
   * ✅ 按任务分组未上传的记录
   */
  groupRecordsByTask(): Map<number, RecordItem[]> {
    const unsyncedRecords = this.records.filter(r => !r.record.is_uploaded);
    const grouped = new Map<number, RecordItem[]>();

    unsyncedRecords.forEach(item => {
      const taskId = item.taskId;
      if (!grouped.has(taskId)) {
        grouped.set(taskId, []);
      }
      grouped.get(taskId)!.push(item);
    });

    return grouped;
  }

  /**
   * ✅ 上传单个任务的所有记录
   */
  async uploadTaskRecords(taskId: number, items: RecordItem[]): Promise<UploadTaskResult> {
    try {
      const task = items[0].task;

      console.log(`\n📤 开始上传任务 [${task.patient_no}] 的 ${items.length} 条记录...`);

      // 构建上传记录列表
      const uploadRecords: UploadRecordItem[] = [];

      for (let item of items) {
        const table = this.getTableInfo(item);
        if (!table) {
          console.error('❌ 表单不存在:', item.record.table_id);
          continue;
        }

        uploadRecords.push({
          table_name: table.table_name,
          table_id: item.record.table_id,
          sub_step_id: item.record.step_id,
          multi_line: table.multi_line === 1 ? "1" : "0",
          data: JSON.stringify(item.record.data)
        });
      }

      if (uploadRecords.length === 0) {
        return { success: false, message: '没有有效的表单数据' };
      }

      // ✅ 提取签名信息
      let signatureImage: string | undefined = undefined;
      let signatureTime: string | undefined = undefined;

      if (task.consent_signature) {
        signatureImage = task.consent_signature.signature_image;
        signatureTime = task.consent_signature.signature_time;
      }

      // ✅ 计算完成度
      const percent = task.percent || '0%';

      // ✅ 确定任务状态
      let state = task.state;
      if (state === 0 && uploadRecords.length > 0) {
        state = 1;  // 设置为进行中
      }

      // 调用批量上传接口
      const request: BatchUploadMissionRequest = {
        token: this.currentToken,
        mission_id: taskId,
        patient_no: task.patient_no,
        sign: signatureImage,
        sign_at: signatureTime,
        percent: percent,
        state: state,
        records: uploadRecords
      };

      console.log('上传请求参数:', {
        mission_id: taskId,
        patient_no: task.patient_no,
        has_sign: !!signatureImage,
        sign_at: signatureTime,
        percent: percent,
        state: state,
        records_count: uploadRecords.length
      });

      const result: BatchUploadResult = await batchUploadMission(request);

      if (result.success) {
        // 标记所有记录为已上传
        for (let item of items) {
          await storage.markRecordAsUploaded(
            this.currentUsername,
            taskId,
            item.record.table_id
          );
        }

        const successCount = result.result?.success_count || uploadRecords.length;
        console.log(`✅ 任务 [${task.patient_no}] 上传成功: ${successCount}/${uploadRecords.length}`);

        return {
          success: true,
          message: `成功 ${successCount}/${uploadRecords.length}`
        };
      } else {
        const failCount = result.result?.fail_count || 0;
        console.error(`❌ 任务 [${task.patient_no}] 上传失败: ${result.message}`);

        return {
          success: false,
          message: result.message + (failCount > 0 ? ` (失败${failCount}条)` : '')
        };
      }

    } catch (err) {
      const e = err as Error;
      console.error('❌ 上传任务记录异常:', e.message);
      return {
        success: false,
        message: '上传异常: ' + e.message
      };
    }
  }

  /**
   * ✅ 上传所有未同步的记录（按任务批量上传）
   */
  async uploadRecords() {
    const groupedRecords = this.groupRecordsByTask();

    if (groupedRecords.size === 0) {
      this.toastController.show('没有需要上传的记录');
      return;
    }

    if (!this.currentToken) {
      this.toastController.show('未获取到 Token，请重新登录');
      return;
    }

    // 检查网络
    let isOnline = await http.isOnline();
    if (!isOnline) {
      this.toastController.show('网络不可用，无法上传');
      return;
    }

    // ✅ 分类：已签名和未签名的任务
    const unsignedTasks: FollowUpTask[] = [];
    const signedEntries: Array<[number, RecordItem[]]> = [];
    const entries = Array.from(groupedRecords.entries());

    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const taskId = entry[0];
      const items = entry[1];
      const task = items[0].task;

      if (!this.hasSignature(task)) {
        unsignedTasks.push(task);
        console.log(`⚠️ 跳过未签名任务: [${task.patient_no}] ${task.name}`);
      } else {
        signedEntries.push([taskId, items]);
      }
    }

    // ✅ 如果全部未签名，直接提示
    if (signedEntries.length === 0) {
      if (unsignedTasks.length > 0) {
        this.missingSignatureTasks = unsignedTasks;
        this.showSignatureMissingDialog = true;
      } else {
        this.toastController.show('没有需要上传的记录');
      }
      return;
    }

    // ✅ 如果有部分未签名，先提示
    if (unsignedTasks.length > 0) {
      console.log(`⚠️ 检测到 ${unsignedTasks.length} 个任务未签署知情同意书，将跳过`);
      this.toastController.show(`检测到 ${unsignedTasks.length} 个未签名任务，将跳过并上传其他任务`);
    }

    // 开始上传已签名的任务
    try {
      this.uploading = true;
      console.log(`\n========== 开始批量上传 ${signedEntries.length} 个已签名任务 ==========`);

      let successTasks = 0;
      let failTasks = 0;
      const failedTaskNames: string[] = [];

      for (let i = 0; i < signedEntries.length; i++) {
        const entry = signedEntries[i];
        const taskId = entry[0];
        const items = entry[1];
        const task = items[0].task;

        const result = await this.uploadTaskRecords(taskId, items);

        if (result.success) {
          successTasks++;
        } else {
          failTasks++;
          failedTaskNames.push(`${task.patient_no}: ${result.message}`);
        }
      }

      this.uploading = false;

      // 重新加载记录
      await this.loadRecords();

      // ✅ 构建结果消息
      let resultMessage = '';

      if (failTasks === 0) {
        resultMessage = `✅ 上传成功 ${successTasks} 个任务`;
      } else {
        resultMessage = `上传完成：成功 ${successTasks}，失败 ${failTasks}`;
        console.error('❌ 失败的任务:', failedTaskNames);
      }

      if (unsignedTasks.length > 0) {
        resultMessage += `\n⚠️ 跳过 ${unsignedTasks.length} 个未签名任务`;
      }

      this.toastController.show(resultMessage);

      // ✅ 如果有未签名任务，延迟显示提示对话框
      if (unsignedTasks.length > 0) {
        setTimeout(() => {
          this.missingSignatureTasks = unsignedTasks;
          this.showSignatureMissingDialog = true;
        }, 2000);
      }

    } catch (e) {
      console.error('❌ 批量上传异常:', e);
      this.toastController.show('上传失败，请重试');
      this.uploading = false;
    }
  }

  /**
   * ✅ 跳转到任务详情页补充签名
   */
  goToSignature() {
    if (!this.missingSignatureTasks || this.missingSignatureTasks.length === 0) {
      return;
    }

    this.showSignatureMissingDialog = false;

    const task = this.missingSignatureTasks[0];

    router.pushUrl({
      url: 'pages/MissionPage',
      params: {
        task: task,
        token: this.currentToken,
        username: this.currentUsername,
        showSignature: true
      }
    }).then(() => {
      console.log('✅ 跳转到签名页');
    }).catch((err: Error) => {
      console.error('❌ 跳转失败:', err);
      this.toastController.show('跳转失败');
    });
  }

  /**
   * ✅ 点击记录，查看详情
   */
  handleRecordClick(item: RecordItem) {
    console.log('查看记录:', item.task.patient_no, '-', this.getTableName(item));

    router.pushUrl({
      url: 'pages/RecordDetailPage',
      params: {
        task: item.task,
        record: item.record,
        tableName: this.getTableName(item),
        username: this.currentUsername
      }
    }).then(() => {
      console.log('✅ 跳转成功');
    }).catch((err: Error) => {
      console.error('❌ 跳转失败:', err);
      this.toastController.show('打开失败');
    });
  }

  /**
   * ✅ 长按记录，显示删除选项
   */
  handleRecordLongPress(item: RecordItem) {
    this.recordToDelete = item;
    this.showDeleteDialog = true;
  }

  /**
   * ✅ 确认删除记录
   */
  async confirmDelete() {
    if (!this.recordToDelete) {
      return;
    }

    try {
      console.log('删除记录:', this.recordToDelete.task.patient_no, '-', this.getTableName(this.recordToDelete));

      await storage.deleteFormRecord(
        this.currentUsername,
        this.recordToDelete.taskId,
        this.recordToDelete.record.table_id
      );

      this.toastController.show('✅ 删除成功');
      await this.loadRecords();

      this.showDeleteDialog = false;
      this.recordToDelete = null;

    } catch (e) {
      console.error('❌ 删除失败:', e);
      this.toastController.show('删除失败');
    }
  }

  /**
   * ✅ 取消删除
   */
  cancelDelete() {
    this.showDeleteDialog = false;
    this.recordToDelete = null;
  }

  build() {
    Stack() {
      Column() {
        // 筛选标签栏
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

          Button('未上传')
            .fontSize(14)
            .height(36)
            .margin({ left: 12 })
            .backgroundColor(this.currentFilterIndex === 1 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.currentFilterIndex === 1 ? '#FFFFFF' : '#666666')
            .borderRadius(8)
            .onClick(() => {
              this.currentFilterIndex = 1;
            })

          Button('已上传')
            .fontSize(14)
            .height(36)
            .margin({ left: 12 })
            .backgroundColor(this.currentFilterIndex === 2 ? '#FF6B00' : '#F5F5F5')
            .fontColor(this.currentFilterIndex === 2 ? '#FFFFFF' : '#666666')
            .borderRadius(8)
            .onClick(() => {
              this.currentFilterIndex = 2;
            })

          Blank()

          // ✅ 添加手动刷新按钮
          Button() {
            Text('🔄')
              .fontSize(16)
          }
          .width(36)
          .height(36)
          .backgroundColor(this.loading ? '#CCCCCC' : '#F7F8FA')
          .borderRadius(8)
          .margin({ right: 8 })
          .enabled(!this.loading)
          .onClick(async () => {
            console.log('手动刷新记录');
            await this.loadRecords();
          })

          Button(this.uploading ? '上传中...' : '上传')
            .fontSize(14)
            .height(36)
            .backgroundColor(this.uploading ? '#CCCCCC' : '#52C41A')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .enabled(!this.uploading)
            .onClick(() => {
              this.uploadRecords();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F5F5F5')

        // 记录列表
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

        } else if (this.getFilteredRecords().length === 0) {
          Column() {
            Text('📝')
              .fontSize(60)
              .margin({ bottom: 12 })

            Text(this.currentFilterIndex === 0 ? '暂无记录' :
              this.currentFilterIndex === 1 ? '暂无未上传记录' : '暂无已上传记录')
              .fontSize(14)
              .fontColor('#999999')

            if (this.currentFilterIndex === 1 && this.records.length > 0) {
              Text('所有记录已上传')
                .fontSize(12)
                .fontColor('#52C41A')
                .margin({ top: 8 })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')

        } else {
          List({ space: 12 }) {
            ForEach(this.getFilteredRecords(), (item: RecordItem) => {
              ListItem() {
                Column() {
                  Row() {
                    Column() {
                      Text(item.task.name || '未知患者')
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#333333')

                      Text(`编号: ${item.task.patient_no}`)
                        .fontSize(12)
                        .fontColor('#999999')
                        .margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)

                    Blank()

                    Row() {
                      if (!this.hasSignature(item.task)) {
                        Text('未签名')
                          .fontSize(11)
                          .fontColor('#FF6B00')
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .backgroundColor('#FF6B0015')
                          .borderRadius(3)
                          .margin({ right: 6 })
                      }

                      Text(item.record.is_uploaded ? '✓ 已上传' : '⊙ 未上传')
                        .fontSize(12)
                        .fontColor(item.record.is_uploaded ? '#52C41A' : '#FF6B00')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor(item.record.is_uploaded ? '#52C41A20' : '#FF6B0020')
                        .borderRadius(4)
                    }
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  Row() {
                    Text(`项目：${item.task.project_name || '未知项目'}`)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  Row() {
                    Text(`表单：${this.getTableName(item)}`)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  Row() {
                    Text(`填写时间：${item.record.filled_time}`)
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
                .onClick(() => {
                  this.handleRecordClick(item);
                })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction(() => {
                      this.handleRecordLongPress(item);
                    })
                )
              }
            }, (item: RecordItem) => `${item.taskId}_${item.record.table_id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
          .backgroundColor('#F5F5F5')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')

      // ✅ 签名缺失提示对话框
      if (this.showSignatureMissingDialog && this.missingSignatureTasks.length > 0) {
        Column() {
          Column() {
            Text('⚠️')
              .fontSize(48)
              .margin({ bottom: 16 })

            Text('需要先签署知情同意书')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 12 })

            if (this.missingSignatureTasks.length === 1) {
              Text(`患者【${this.missingSignatureTasks[0].name || this.missingSignatureTasks[0].patient_no}】的随访任务尚未签署知情同意书。`)
                .fontSize(14)
                .fontColor('#666666')
                .textAlign(TextAlign.Center)
                .lineHeight(22)
                .margin({ bottom: 8 })
            } else {
              Text(`有 ${this.missingSignatureTasks.length} 个随访任务尚未签署知情同意书。`)
                .fontSize(14)
                .fontColor('#666666')
                .textAlign(TextAlign.Center)
                .lineHeight(22)
                .margin({ bottom: 8 })
            }

            Text('请先前往任务详情页完成签名后再上传数据。')
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
                  this.showSignatureMissingDialog = false;
                  this.missingSignatureTasks = [];
                })

              Button('去签名')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .backgroundColor('#FF6B00')
                .width('48%')
                .height(44)
                .borderRadius(8)
                .onClick(() => {
                  this.goToSignature();
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
          this.showSignatureMissingDialog = false;
          this.missingSignatureTasks = [];
        })
      }

      // 删除确认对话框
      if (this.showDeleteDialog && this.recordToDelete) {
        Column() {
          Column() {
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 16 })

            Text(`确定要删除这条记录吗？`)
              .fontSize(14)
              .fontColor('#666666')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8 })

            Text(`患者：${this.recordToDelete.task.name || ''} (${this.recordToDelete.task.patient_no})`)
              .fontSize(12)
              .fontColor('#999999')
              .margin({ bottom: 4 })

            Text(`表单：${this.getTableName(this.recordToDelete)}`)
              .fontSize(12)
              .fontColor('#999999')
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
                  this.cancelDelete();
                })

              Button('删除')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .backgroundColor('#FF4D4F')
                .width('48%')
                .height(44)
                .borderRadius(8)
                .onClick(() => {
                  this.confirmDelete();
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
          this.cancelDelete();
        })
      }

      // Toast 组件
      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}