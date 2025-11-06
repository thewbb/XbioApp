
/**
 * 记录详情页
 *
 * 功能：
 * - 显示表单填写的详细数据
 * - 只读模式，不可编辑
 * - 显示上传状态
 */
import router from '@ohos.router';
import { FollowUpTask, FormRecord, FormField } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';

@Entry
@Component
struct RecordDetailPage {
  @State currentTask: FollowUpTask | null = null;
  @State currentRecord: FormRecord | null = null;
  @State tableName: string = '';
  @State currentUsername: string = '';
  @State toastController: ToastController = new ToastController();

  async aboutToAppear() {
    console.log('========== RecordDetailPage 加载 ==========');

    // 获取路由参数
    const params = router.getParams() as Record<string, Object>;

    if (params && params['task']) {
      this.currentTask = params['task'] as FollowUpTask;
    }

    if (params && params['record']) {
      this.currentRecord = params['record'] as FormRecord;
    }

    if (params && params['tableName']) {
      this.tableName = params['tableName'] as string;
    }

    if (params && params['username']) {
      this.currentUsername = params['username'] as string;
    }

    console.log('患者编号:', this.currentTask?.patient_no);
    console.log('表单名称:', this.tableName);
    console.log('是否已上传:', this.currentRecord?.is_uploaded);
  }

  /**
   * ✅ 获取表单字段定义
   */
  getTableFields(): FormField[] {
    if (!this.currentTask || !this.currentTask.project || !this.currentTask.project.tables) {
      return [];
    }

    const table = this.currentTask.project.tables.find(t => t.id === this.currentRecord?.table_id);
    return table?.fields || [];
  }

  /**
   * ✅ 获取字段显示名称
   */
  getFieldLabel(fieldName: string): string {
    const field = this.getTableFields().find(f => f.field_name === fieldName);
    return field?.annotation || fieldName;
  }

  /**
   * ✅ 获取字段值
   */
  getFieldValue(fieldName: string): string {
    if (!this.currentRecord || !this.currentRecord.data) {
      return '-';
    }
    return this.currentRecord.data[fieldName] || '-';
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Button('‹ 返回')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor('#333333')
            .onClick(() => {
              try {
                router.back();
              } catch (e) {
                console.error('返回失败:', e);
              }
            })

          Text('记录详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 占位，保持标题居中
          Text('')
            .width(60)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .justifyContent(FlexAlign.SpaceBetween)
        .border({
          width: { bottom: 0.5 },
          color: '#E5E5E5'
        })

        // 内容区域
        if (!this.currentTask || !this.currentRecord) {
          Column() {
            Text('数据错误')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')

        } else {
          Scroll() {
            Column() {
              // ✅ 基本信息卡片
              Column() {
                Row() {
                  Column() {
                    Text('患者编号')
                      .fontSize(12)
                      .fontColor('#999999')
                      .margin({ bottom: 4 })

                    Text(this.currentTask.patient_no)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#333333')
                  }
                  .alignItems(HorizontalAlign.Start)

                  Blank()

                  // 上传状态标签
                  Text(this.currentRecord.is_uploaded ? '✓ 已上传' : '⊙ 未上传')
                    .fontSize(12)
                    .fontColor(this.currentRecord.is_uploaded ? '#52C41A' : '#FF6B00')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(this.currentRecord.is_uploaded ? '#52C41A20' : '#FF6B0020')
                    .borderRadius(4)
                }
                .width('100%')
                .margin({ bottom: 12 })

                Row() {
                  Text(`项目：${this.currentTask.project_name}`)
                    .fontSize(14)
                    .fontColor('#666666')
                }
                .width('100%')
                .margin({ bottom: 8 })

                Row() {
                  Text(`表单：${this.tableName}`)
                    .fontSize(14)
                    .fontColor('#666666')
                }
                .width('100%')
                .margin({ bottom: 8 })

                Row() {
                  Text(`填写时间：${this.currentRecord.filled_time}`)
                    .fontSize(12)
                    .fontColor('#999999')
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFF7F0')
              .borderRadius(8)
              .margin({ bottom: 16 })

              // ✅ 表单数据
              Column() {
                Text('表单数据')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                  .margin({ bottom: 12 })

                // 遍历显示所有字段
                if (this.currentRecord.data) {
                  Column() {
                    ForEach(Object.keys(this.currentRecord.data), (fieldName: string) => {
                      Column() {
                        // 字段标签
                        Row() {
                          Text(this.getFieldLabel(fieldName))
                            .fontSize(14)
                            .fontColor('#666666')
                        }
                        .width('100%')
                        .margin({ bottom: 4 })

                        // 字段值
                        Row() {
                          Text(this.getFieldValue(fieldName))
                            .fontSize(15)
                            .fontColor('#333333')
                            .fontWeight(FontWeight.Medium)
                        }
                        .width('100%')
                        .padding(12)
                        .backgroundColor('#F5F5F5')
                        .borderRadius(6)
                      }
                      .width('100%')
                      .alignItems(HorizontalAlign.Start)
                      .margin({ bottom: 12 })
                    })
                  }
                  .width('100%')
                } else {
                  Text('暂无数据')
                    .fontSize(14)
                    .fontColor('#999999')
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
            }
            .width('100%')
            .padding(16)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')

      // Toast 组件
      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}
