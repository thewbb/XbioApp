
/**
 * 随访任务详情页 - 使用 taskList 数据
 *
 * 功能：
 * - 直接从 taskList 获取任务数据，无需请求 taskDetail 接口
 * - table.state: 0=未填写（可填写），1=已填写（不可再填）
 * - 优化布局和配色
 */
import router from '@ohos.router';
import { FollowUpTask, FormTable, FormField } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';

/**
 * 任务统计信息接口
 */
interface TaskStats {
  total: number;
  completed: number;
  pending: number;
}

@Entry
@Component
struct MissionPage {
  @State currentTask: FollowUpTask | null = null;
  @State currentUsername: string = '';
  @State token: string = '';
  @State toastController: ToastController = new ToastController();

  async aboutToAppear() {
    console.log('========== MissionPage 加载 ==========');

    // 获取路由参数
    const params = router.getParams() as Record<string, Object>;

    if (params && params['task']) {
      this.currentTask = params['task'] as FollowUpTask;
    }

    if (params && params['token']) {
      this.token = params['token'] as string;
    }

    if (params && params['username']) {
      this.currentUsername = params['username'] as string;
    }

    console.log('任务ID:', this.currentTask?.id);
    console.log('患者编号:', this.currentTask?.patient_no);
    console.log('Token:', this.token ? '已获取' : '未获取');
    console.log('用户名:', this.currentUsername);

    if (!this.currentTask) {
      this.toastController.show('任务数据错误');
      setTimeout(() => {
        router.back();
      }, 500);
      return;
    }

    // 打印任务详情
    if (this.currentTask.project && this.currentTask.project.tables) {
      console.log('表单数量:', this.currentTask.project.tables.length);

      this.currentTask.project.tables.forEach((table, index) => {
        console.log(`表单 ${index + 1}: ${table.step_name}`);
        console.log(`  - state: ${table.state} (${table.state === 1 ? '已填写' : '未填写'})`);
        console.log(`  - 字段数: ${table.fields.length}`);
      });
    }
  }

  /**
   * 获取任务状态文本
   */
  getStateText(state: number): string {
    switch (state) {
      case 0: return '待执行';
      case 1: return '进行中';
      case 2: return '已完成';
      default: return '未知';
    }
  }

  /**
   * 获取任务状态颜色
   */
  getStateColor(state: number): string {
    switch (state) {
      case 0: return '#FF6B00';
      case 1: return '#1890FF';
      case 2: return '#52C41A';
      default: return '#999999';
    }
  }

  /**
   * 获取表单状态文本
   * table.state: 0=未填写，1=已填写
   */
  getTableStateText(state: number): string {
    return state === 1 ? '已填写' : '未填写';
  }

  /**
   * 获取表单状态颜色
   */
  getTableStateColor(state: number): string {
    return state === 1 ? '#52C41A' : '#FF6B00';
  }

  /**
   * 获取表单状态图标
   */
  getTableStateIcon(state: number): string {
    return state === 1 ? '✓' : '○';
  }

  /**
   * 判断表单是否可以填写
   * state=0 可以填写，state=1 已填写不可再填
   */
  isTableFillable(table: FormTable): boolean {
    return table.state === 0;
  }

  /**
   * 点击表单
   */
  handleFormClick(table: FormTable) {
    console.log('点击表单:', table.step_name, 'state:', table.state);

    // 检查是否已填写
    if (table.state === 1) {
      this.toastController.show('该表单已填写，无需重复填写');
      return;
    }

    // 未填写，跳转到填写页面
    console.log('跳转到填写页面');

    router.pushUrl({
      url: 'pages/FormPage',
      params: {
        task: this.currentTask,     // 传递完整任务对象
        table: table,               // 传递当前表单对象
        token: this.token,
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
   * 获取任务统计信息
   */
  getTaskStats(): TaskStats {
    if (!this.currentTask || !this.currentTask.project || !this.currentTask.project.tables) {
      const emptyStats: TaskStats = { total: 0, completed: 0, pending: 0 };
      return emptyStats;
    }

    const tables = this.currentTask.project.tables;
    const total: number = tables.length;
    const completed: number = tables.filter((t: FormTable) => t.state === 1).length;
    const pending: number = total - completed;

    const stats: TaskStats = {
      total: total,
      completed: completed,
      pending: pending
    };

    return stats;
  }

  /**
   * 获取可编辑字段数量
   */
  getEditableFieldCount(table: FormTable): number {
    if (!table.fields) {
      return 0;
    }
    let length:number = table.fields.filter((f: FormField) => f.is_editable === '1').length;
    return length;
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
              router.back();
            })

          Text('任务详情')
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
        if (!this.currentTask) {
          Column() {
            Text('❌')
              .fontSize(60)
              .margin({ bottom: 12 })

            Text('任务数据错误')
              .fontSize(14)
              .fontColor('#999999')

            Button('返回')
              .fontSize(14)
              .margin({ top: 20 })
              .backgroundColor('#FF6B00')
              .borderRadius(8)
              .onClick(() => {
                router.back();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')

        } else {
          Scroll() {
            Column() {
              // 基本信息卡片
              Column() {
                // 标题行
                Row() {
                  Text('基本信息')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')

                  Blank()

                  Text(this.getStateText(this.currentTask.state))
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .backgroundColor(this.getStateColor(this.currentTask.state))
                    .borderRadius(12)
                }
                .width('100%')
                .margin({ bottom: 16 })

                // 信息列表
                Column() {
                  // 患者编号
                  this.InfoRow('患者编号', this.currentTask.patient_no)

                  Divider()
                    .color('#F0F0F0')
                    .margin({ top: 10, bottom: 10 })

                  // 随访项目
                  this.InfoRow('随访项目', this.currentTask.project_name)

                  Divider()
                    .color('#F0F0F0')
                    .margin({ top: 10, bottom: 10 })

                  // 任务发布人
                  this.InfoRow('任务发布人', this.currentTask.creator)

                  Divider()
                    .color('#F0F0F0')
                    .margin({ top: 10, bottom: 10 })

                  // 创建时间
                  this.InfoRow('创建时间', this.currentTask.create_time)

                  Divider()
                    .color('#F0F0F0')
                    .margin({ top: 10, bottom: 10 })

                  // 完成进度
                  Row() {
                    Text('完成进度')
                      .fontSize(14)
                      .fontColor('#999999')
                      .width(90)

                    Row() {
                      Text(`${this.getTaskStats().completed}/${this.getTaskStats().total}`)
                        .fontSize(14)
                        .fontColor('#333333')
                        .margin({ right: 8 })

                      Text(`${this.currentTask.percent}%`)
                        .fontSize(14)
                        .fontColor('#1890FF')
                        .fontWeight(FontWeight.Bold)
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .shadow({
                radius: 8,
                color: '#00000008',
                offsetX: 0,
                offsetY: 2
              })

              // 随访表单列表
              if (this.currentTask.project && this.currentTask.project.tables &&
                this.currentTask.project.tables.length > 0) {
                Column() {
                  // 标题行
                  Row() {
                    Text('随访表单')
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#333333')

                    Blank()

                    // 显示待填写数量
                    if (this.getTaskStats().pending > 0) {
                      Text(`还有 ${this.getTaskStats().pending} 张待填写`)
                        .fontSize(11)
                        .fontColor('#FF6B00')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor('#FFF7F0')
                        .borderRadius(12)
                    } else {
                      Text('全部已完成')
                        .fontSize(11)
                        .fontColor('#52C41A')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor('#F6FFED')
                        .borderRadius(12)
                    }
                  }
                  .width('100%')
                  .margin({ bottom: 12 })

                  // 表单列表
                  Column() {
                    ForEach(this.currentTask.project.tables, (table: FormTable, index: number) => {
                      this.TableCard(table, index)
                    })
                  }
                  .width('100%')
                }
                .width('100%')
                .margin({ top: 16 })
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })
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

  /**
   * 信息行组件
   */
  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#999999')
        .width(90)

      Text(value)
        .fontSize(14)
        .fontColor('#333333')
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 表单卡片组件
   */
  @Builder
  TableCard(table: FormTable, index: number) {
    Row() {
      // 左侧状态指示器
      Column() {
        Text(this.getTableStateIcon(table.state))
          .fontSize(24)
          .fontColor(this.getTableStateColor(table.state))
          .fontWeight(FontWeight.Bold)
      }
      .width(40)
      .justifyContent(FlexAlign.Center)

      // 右侧内容
      Column() {
        // 表单名称 + 状态
        Row() {
          Text(table.step_name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(table.state === 1 ? '#999999' : '#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.getTableStateText(table.state))
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.getTableStateColor(table.state))
            .borderRadius(10)
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ bottom: 8 })

        // 表单信息
        Row() {
          Text(table.multi_line === 1 ? '📋 多行' : '📄 单行')
            .fontSize(12)
            .fontColor('#666666')

          Text('·')
            .fontSize(12)
            .fontColor('#CCCCCC')
            .margin({ left: 8, right: 8 })

          Text(`${this.getEditableFieldCount(table)} 个字段`)
            .fontSize(12)
            .fontColor('#666666')

          Blank()

          // 操作提示
          if (table.state === 1) {
            Text('已完成')
              .fontSize(12)
              .fontColor('#52C41A')
              .fontWeight(FontWeight.Medium)
          } else {
            Row() {
              Text('去填写')
                .fontSize(12)
                .fontColor('#FF6B00')
                .fontWeight(FontWeight.Medium)

              Text('›')
                .fontSize(14)
                .fontColor('#FF6B00')
                .margin({ left: 2 })
            }
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(table.state === 1 ? '#FAFAFA' : '#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: index < this.currentTask!.project!.tables.length - 1 ? 10 : 0 })
    .opacity(table.state === 1 ? 0.75 : 1.0)
    .shadow({
      radius: 6,
      color: table.state === 1 ? '#00000003' : '#00000008',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.handleFormClick(table);
    })
  }
}
