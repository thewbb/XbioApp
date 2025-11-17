/**
 * 记录列表 Tab
 *
 * 功能：
 * - 显示所有本地保存的表单记录
 * - 筛选：全部/未上传/已上传
 * - 上传未同步的记录
 * - 查看记录详情
 * - 删除记录
 */
import router from '@ohos.router';
import storage, { StorageKeys } from '../utils/storage';
import { FollowUpTask, FormRecord, FormTable } from '../types';
import http from '../utils/http';
import { CustomToast, ToastController } from '../components/CustomToast';
import {SaveSubStepDataParams} from '../types/index';

/**
 * ✅ 上传表单数据到服务器
 */
async function saveSubStepData(params: SaveSubStepDataParams): Promise<boolean> {
  try {
    const request :SaveSubStepDataParams = {
      token: params.token,
      table_name: params.table_name,
      patientNo: params.patientNo,
      multi_line: params.multi_line,
      subStepId: params.subStepId,
      data: params.data
    };

    console.log('📤 上传表单数据:', request);

    let response = await http.post('/mobile/saveSubStepData.json', request);
    console.log('上传响应 code:', response.code);

    if (response.code === 0) {
      console.log('✅ 表单上传成功');
      return true;
    } else {
      console.error('❌ 表单上传失败:', response.message);
      return false;
    }
  } catch (err) {
    const e = err as Error;
    console.error('❌ 表单上传异常:', e.message);
    return false;
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
  @Prop filterType: number = 0;
  @State records: RecordItem[] = [];
  @State currentFilterIndex: number = 0;  // 0=全部，1=未上传，2=已上传
  @State loading: boolean = false;
  @State uploading: boolean = false;
  @State toastController: ToastController = new ToastController();

  // ✅ 删除确认对话框
  @State showDeleteDialog: boolean = false;
  @State recordToDelete: RecordItem | null = null;

  async aboutToAppear() {
    console.log('========== MissionLogTab 加载 ==========');
    await this.loadRecords();
  }

  /**
   * ✅ 加载所有任务的本地记录
   */
  async loadRecords() {
    try {
      this.loading = true;
      console.log('加载本地记录...');

      // 1. 加载所有任务
      let tasksStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.FOLLOW_UP_TASKS
      );

      if (!tasksStr) {
        console.log('本地暂无任务数据');
        this.records = [];
        this.loading = false;
        return;
      }

      if (this.filterType > 0) {
        this.currentFilterIndex = this.filterType;
      }

      const tasks: FollowUpTask[] = JSON.parse(tasksStr);
      console.log('任务数量:', tasks.length);

      // 2. 遍历任务，收集所有本地记录
      const allRecords: RecordItem[] = [];

      for (let task of tasks) {
        if (task.local_records && task.local_records.length > 0) {
          // 为每个记录创建 RecordItem
          task.local_records.forEach(record => {
            allRecords.push({
              task: task,
              record: record,
              taskId: task.id
            });
          });
        }
      }

      // 3. 按填写时间倒序排序（最新的在前面）
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
      case 1:  // 未上传
        return this.records.filter(r => !r.record.is_uploaded);
      case 2:  // 已上传
        return this.records.filter(r => r.record.is_uploaded);
      default:  // 全部
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
   * ✅ 上传单条记录
   */
  async uploadRecord(item: RecordItem): Promise<boolean> {
    try {
      const table = this.getTableInfo(item);
      if (!table) {
        console.error('表单不存在:', item.record.table_id);
        return false;
      }

      console.log('开始上传记录:', table.table_name);

      // 调用接口上传数据
      const params: SaveSubStepDataParams = {
        token: this.currentToken,
        table_name: table.table_name,
        patientNo: item.task.patient_no,
        multi_line: table.multi_line,
        subStepId: item.record.step_id,
        data: JSON.stringify(item.record.data)
      };

      const uploadSuccess = await saveSubStepData(params);

      if (uploadSuccess) {
        // 标记为已上传
        await storage.markRecordAsUploaded(
          this.currentUsername,
          item.taskId,
          item.record.table_id
        );
        console.log('✅ 记录上传成功');
        return true;
      }

      console.error('❌ 记录上传失败');
      return false;
    } catch (err) {
      const e = err as Error;
      console.error('❌ 上传记录异常:', e.message);
      return false;
    }
  }

  /**
   * ✅ 上传所有未同步的记录
   */
  async uploadRecords() {
    const unsyncedRecords = this.records.filter(r => !r.record.is_uploaded);

    if (unsyncedRecords.length === 0) {
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

    try {
      this.uploading = true;
      console.log(`开始上传 ${unsyncedRecords.length} 条记录...`);

      let successCount = 0;
      let failCount = 0;

      for (let item of unsyncedRecords) {
        try {
          const success = await this.uploadRecord(item);

          if (success) {
            successCount++;
            console.log(`✅ 上传成功: ${item.task.patient_no} - ${this.getTableName(item)}`);
          } else {
            failCount++;
          }

        } catch (uploadError) {
          failCount++;
          console.error(`❌ 上传失败:`, uploadError);
        }
      }

      this.uploading = false;

      // 重新加载记录
      await this.loadRecords();

      // 显示结果
      if (failCount === 0) {
        this.toastController.show(`✅ 全部上传成功（${successCount} 条）`);
      } else {
        this.toastController.show(`上传完成：成功 ${successCount} 条，失败 ${failCount} 条`);
      }

    } catch (e) {
      console.error('❌ 上传异常:', e);
      this.toastController.show('上传失败');
      this.uploading = false;
    }
  }

  /**
   * ✅ 点击记录，查看详情
   */
  handleRecordClick(item: RecordItem) {
    console.log('查看记录:', item.task.patient_no, '-', this.getTableName(item));

    // 跳转到记录详情页
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

      // 从存储中删除
      await storage.deleteFormRecord(
        this.currentUsername,
        this.recordToDelete.taskId,
        this.recordToDelete.record.table_id
      );

      this.toastController.show('✅ 删除成功');

      // 重新加载记录
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
                  // 第一行：患者姓名 + 患者编号 + 上传状态
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

                    Text(item.record.is_uploaded ? '✓ 已上传' : '⊙ 未上传')
                      .fontSize(12)
                      .fontColor(item.record.is_uploaded ? '#52C41A' : '#FFFFFF')
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .backgroundColor(item.record.is_uploaded ? '#52C41A20' : '#FF6B0020')
                      .borderRadius(4)
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  // 第二行：项目名称
                  Row() {
                    Text(`项目：${item.task.project_name || '未知项目'}`)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  // 第三行：表单名称
                  Row() {
                    Text(`表单：${this.getTableName(item)}`)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  // 第四行：填写时间
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
                  // ✅ 长按显示删除选项
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

      // ✅ 删除确认对话框
      if (this.showDeleteDialog && this.recordToDelete) {
        Column() {
          Column() {
            // 标题
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 16 })

            // 消息
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

            // 按钮组
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
          // 点击背景关闭
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