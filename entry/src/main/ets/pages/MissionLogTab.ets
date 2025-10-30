
/**
 * 记录列表 Tab
 */
import promptAction from '@ohos.promptAction';
import storage, { StorageKeys } from '../utils/storage';
import { FollowUpRecord, LocalRecords } from '../types';

@Component
export default struct MissionLogTab {
  @Prop currentUsername: string = '';
  @Prop currentToken: string = '';
  @State records: FollowUpRecord[] = [];
  @State currentFilterIndex: number = 0;  // 0=全部，1=未同步，2=已同步
  @State loading: boolean = false;

  async aboutToAppear() {
    console.log('========== MissionLogTab 加载 ==========');
    await this.loadRecords();
  }

  /**
   * 加载记录列表
   */
  async loadRecords() {
    try {
      this.loading = true;
      console.log('加载随访记录...');

      let recordsStr: string = await storage.getUserData(
        this.currentUsername,
        StorageKeys.FOLLOW_UP_RECORDS
      );

      if (recordsStr) {
        let localRecords = LocalRecords.fromJSON(recordsStr);
        this.records = localRecords.getAll();
        console.log('✅ 加载记录成功:', this.records.length, '条');
      } else {
        console.log('本地暂无记录');
      }

      this.loading = false;
    } catch (e) {
      console.error('❌ 加载记录失败:', e);
      this.loading = false;
    }
  }

  /**
   * 获取筛选后的记录
   */
  getFilteredRecords(): FollowUpRecord[] {
    switch (this.currentFilterIndex) {
      case 1:  // 未同步
        return this.records.filter(r => !r.synced);
      case 2:  // 已同步
        return this.records.filter(r => r.synced);
      default:  // 全部
        return this.records;
    }
  }

  /**
   * ✅ 格式化时间（在外部方法中计算）
   */
  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }

  /**
   * 上传记录
   */
  async uploadRecords() {
    const unsyncedRecords = this.records.filter(r => !r.synced);

    if (unsyncedRecords.length === 0) {
      promptAction.showToast({
        message: '没有需要上传的记录',
        duration: 1500
      });
      return;
    }

    promptAction.showToast({
      message: `准备上传 ${unsyncedRecords.length} 条记录（功能开发中）`,
      duration: 2000
    });

    // TODO: 实现上传逻辑
  }

  /**
   * 点击记录
   */
  handleRecordClick(record: FollowUpRecord) {
    console.log('点击记录:', record.patientNo);
    promptAction.showToast({
      message: `查看记录：${record.patientNo}`,
      duration: 1500
    });
    // TODO: 跳转到记录详情页
  }

  build() {
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

        Button('未同步')
          .fontSize(14)
          .height(36)
          .margin({ left: 12 })
          .backgroundColor(this.currentFilterIndex === 1 ? '#FF6B00' : '#F5F5F5')
          .fontColor(this.currentFilterIndex === 1 ? '#FFFFFF' : '#666666')
          .borderRadius(8)
          .onClick(() => {
            this.currentFilterIndex = 1;
          })

        Button('已同步')
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

        Button('上传')
          .fontSize(14)
          .height(36)
          .backgroundColor('#52C41A')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.uploadRecords();
          })
      }
      .width('100%')
      .padding(12)

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

          Text('暂无记录')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F5F5')

      } else {
        List({ space: 12 }) {
          ForEach(this.getFilteredRecords(), (record: FollowUpRecord) => {
            ListItem() {
              Column() {
                // 第一行：患者编号 + 同步状态
                Row() {
                  Text(record.patientNo)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')

                  Blank()

                  Text(record.synced ? '已同步' : '未同步')
                    .fontSize(12)
                    .fontColor(record.synced ? '#52C41A' : '#FF6B00')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(record.synced ? '#52C41A20' : '#FF6B0020')
                    .borderRadius(4)
                }
                .width('100%')
                .margin({ bottom: 8 })

                // 第二行：项目名称
                Row() {
                  Text(`项目：${record.projectName}`)
                    .fontSize(14)
                    .fontColor('#666666')
                }
                .width('100%')
                .margin({ bottom: 4 })

                // 第三行：创建时间（✅ 使用方法调用）
                Row() {
                  Text(`创建时间：${this.formatTime(record.createTime)}`)
                    .fontSize(12)
                    .fontColor('#999999')
                }
                .width('100%')
                .margin({ bottom: 4 })

                // 第四行：同步时间（如果已同步）
                if (record.synced && record.syncTime) {
                  Row() {
                    Text(`同步时间：${this.formatTime(record.syncTime)}`)
                      .fontSize(12)
                      .fontColor('#CCCCCC')
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.handleRecordClick(record);
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
    .backgroundColor('#F5F5F5')
  }
}
