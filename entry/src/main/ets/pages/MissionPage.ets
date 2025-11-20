/**
 * 随访任务详情页 - 支持本地数据 + 知情同意书签署
 *
 * 功能：
 * - 从本地加载最新任务数据（包含 local_records）
 * - 显示本地保存状态：📝 待上传
 * - 已保存的表单可以点击进入编辑
 * - table.state: 0=未填写，1=已填写
 * - 页面显示时自动刷新数据
 * - ✅ 可以填写表单，但必须签署知情同意书后才能上传
 */
import router from '@ohos.router';
import { FollowUpTask, FormTable, FormField } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import storage from '../utils/storage';
import { SignatureCanvas } from '../components/SignatureCanvas';

/**
 * 任务统计信息接口
 */
interface TaskStats {
  total: number;
  completed: number;
  pending: number;
  localSaved: number;  // 本地已保存但未上传的数量
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
    console.log('用户名:', this.currentUsername);

    if (!this.currentTask) {
      this.toastController.show('任务数据错误');
      setTimeout(() => {
        router.back();
      }, 500);
      return;
    }

    // ✅ 从本地加载最新的任务数据
    await this.loadLatestTaskData();

    // 打印任务详情
    this.printTaskDetails();
  }

  /**
   * ✅ 页面显示时刷新数据
   */
  async onPageShow() {
    console.log('========== MissionPage 显示 ==========');

    // 重新加载最新的任务数据
    if (this.currentTask && this.currentUsername) {
      await this.loadLatestTaskData();
      console.log('✅ 页面显示时已刷新数据');
    }
  }

  /**
   * 打印任务详情（调试用）
   */
  printTaskDetails() {
    console.log('知情同意书:', this.hasConsent() ? '已签署' : '未签署');

    if (this.currentTask?.project && this.currentTask.project.tables) {
      console.log('表单数量:', this.currentTask.project.tables.length);

      this.currentTask.project.tables.forEach((table, index) => {
        const hasLocalData = this.hasLocalRecord(table.id);
        const isUploaded = this.isRecordUploaded(table.id);
        console.log(`表单 ${index + 1}: ${table.step_name}`);
        console.log(`  - state: ${table.state} (${table.state === 1 ? '已填写' : '未填写'})`);
        console.log(`  - 本地数据: ${hasLocalData ? '有' : '无'}${hasLocalData && !isUploaded ? ' (待上传)' : ''}`);
        console.log(`  - 字段数: ${table.fields.length}`);
      });
    }
  }

  /**
   * 从本地加载最新的任务数据
   */
  async loadLatestTaskData() {
    try {
      const tasks = await storage.loadFollowUpTasks(this.currentUsername);
      const latestTask = tasks.find(t => t.id === this.currentTask?.id);

      if (latestTask) {
        // 更新当前任务数据（保留本地记录和签名）
        this.currentTask = latestTask;
        console.log('✅ 已加载最新任务数据');
        console.log('  - 本地记录数:', latestTask.local_records?.length || 0);
        console.log('  - 知情同意书:', latestTask.consent_signature ? '已签署' : '未签署');
      }
    } catch (e) {
      console.error('❌ 加载本地任务数据失败:', e);
    }
  }

  /**
   * ✅ 检查是否已签署知情同意书
   */
  hasConsent(): boolean {
    return !!this.currentTask?.consent_signature;
  }

  /**
   * 检查表单是否有本地记录
   */
  hasLocalRecord(tableId: number): boolean {
    if (!this.currentTask?.local_records) {
      return false;
    }
    return this.currentTask.local_records.some(r => r.table_id === tableId);
  }

  /**
   * 检查记录是否已上传
   */
  isRecordUploaded(tableId: number): boolean {
    if (!this.currentTask?.local_records) {
      return false;
    }
    const record = this.currentTask.local_records.find(r => r.table_id === tableId);
    return record?.is_uploaded || false;
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
   */
  getTableStateText(tableId: number, state: number): string {
    const hasLocalData = this.hasLocalRecord(tableId);
    const isUploaded = this.isRecordUploaded(tableId);

    if (hasLocalData && !isUploaded) {
      return '待上传';
    }
    return state === 1 ? '已填写' : '未填写';
  }

  /**
   * 获取表单状态颜色
   */
  getTableStateColor(tableId: number, state: number): string {
    const hasLocalData = this.hasLocalRecord(tableId);
    const isUploaded = this.isRecordUploaded(tableId);

    if (hasLocalData && !isUploaded) {
      return '#1890FF';  // 待上传用蓝色
    }
    return state === 1 ? '#52C41A' : '#FF6B00';
  }

  /**
   * 获取表单状态图标
   */
  getTableStateIcon(tableId: number, state: number): string {
    const hasLocalData = this.hasLocalRecord(tableId);
    const isUploaded = this.isRecordUploaded(tableId);

    if (hasLocalData && !isUploaded) {
      return '📝';  // 待上传显示编辑图标
    }
    return state === 1 ? '✓' : '○';
  }

  /**
   * ✅ 判断表单是否可以填写（修改：不检查知情同意书）
   * - 未填写（state=0）可以填写
   * - 有本地记录但未上传，可以继续编辑
   */
  isTableFillable(table: FormTable): boolean {
    const hasLocalData = this.hasLocalRecord(table.id);
    const isUploaded = this.isRecordUploaded(table.id);

    // 有本地数据但未上传，可以编辑
    if (hasLocalData && !isUploaded) {
      return true;
    }

    // 未填写可以填写
    return table.state === 0;
  }

  /**
   * ✅ 点击知情同意书
   */
  handleConsentClick() {
    if (this.hasConsent()) {
      // 已签署，显示提示（可以扩展为查看大图）
      this.toastController.show('已签署');
      return;
    }

    // 未签署，跳转到签署页面
    console.log('跳转到知情同意书签署页面');

    router.pushUrl({
      url: 'pages/ConsentPage',
      params: {
        task: this.currentTask,
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
   * ✅ 点击表单（修改：允许填写，但提示需要签名才能上传）
   */
  handleFormClick(table: FormTable) {
    const hasLocalData = this.hasLocalRecord(table.id);
    const isUploaded = this.isRecordUploaded(table.id);

    console.log('点击表单:', table.step_name);
    console.log('  state:', table.state);
    console.log('  hasLocalData:', hasLocalData);
    console.log('  isUploaded:', isUploaded);
    console.log('  hasConsent:', this.hasConsent());

    // 已上传的不能再编辑
    if (table.state === 1 && isUploaded) {
      this.toastController.show('该表单已提交，无法修改');
      return;
    }

    // 可以填写或编辑
    if (this.isTableFillable(table)) {
      // ✅ 如果未签署知情同意书，提示但仍然允许填写
      if (!this.hasConsent()) {
        this.toastController.show('提醒：需签署知情同意书后才能上传');
      }

      console.log('跳转到填写页面');

      router.pushUrl({
        url: 'pages/FormPage',
        params: {
          task: this.currentTask,
          table: table,
          token: this.token,
          username: this.currentUsername
        }
      }).then(() => {
        console.log('✅ 跳转成功');
      }).catch((err: Error) => {
        console.error('❌ 跳转失败:', err);
        this.toastController.show('打开失败');
      });
    } else {
      this.toastController.show('该表单已填写');
    }
  }

  /**
   * 获取任务统计信息
   */
  getTaskStats(): TaskStats {
    if (!this.currentTask || !this.currentTask.project || !this.currentTask.project.tables) {
      const emptyStats: TaskStats = { total: 0, completed: 0, pending: 0, localSaved: 0 };
      return emptyStats;
    }

    const tables = this.currentTask.project.tables;
    const total: number = tables.length;
    const completed: number = tables.filter((t: FormTable) => t.state === 1).length;

    // 计算本地已保存但未上传的数量
    let localSaved = 0;
    tables.forEach(table => {
      const hasLocalData = this.hasLocalRecord(table.id);
      const isUploaded = this.isRecordUploaded(table.id);
      if (hasLocalData && !isUploaded) {
        localSaved++;
      }
    });

    const pending: number = total - completed;

    const stats: TaskStats = {
      total: total,
      completed: completed,
      pending: pending,
      localSaved: localSaved
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
    let length: number = table.fields.filter((f: FormField) => f.is_editable === '1').length;
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

                  this.InfoRow('患者姓名', this.currentTask.name)

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

                  // ✅ 显示本地待上传数量
                  if (this.getTaskStats().localSaved > 0) {
                    Divider()
                      .color('#F0F0F0')
                      .margin({ top: 10, bottom: 10 })

                    Row() {
                      Text('待上传')
                        .fontSize(14)
                        .fontColor('#999999')
                        .width(90)

                      Row() {
                        Text(`${this.getTaskStats().localSaved} 份`)
                          .fontSize(14)
                          .fontColor('#1890FF')
                          .fontWeight(FontWeight.Medium)

                        Text('📝')
                          .fontSize(14)
                          .margin({ left: 4 })
                      }
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }
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

              // ✅ 知情同意书卡片
              this.ConsentCard()

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

                    // 显示状态提示
                    if (this.getTaskStats().localSaved > 0) {
                      Text(`${this.getTaskStats().localSaved} 份待上传`)
                        .fontSize(11)
                        .fontColor('#1890FF')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor('#E6F7FF')
                        .borderRadius(12)
                    } else if (this.getTaskStats().pending > 0) {
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
   * ✅ 知情同意书卡片（修改：改为温馨提示样式）
   */
  @Builder
  ConsentCard() {
    Column() {
      // 标题行
      Row() {
        Text('知情同意书')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Blank()

        if (this.hasConsent()) {
          Text('已签署')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#52C41A')
            .borderRadius(12)
        } else {
          Text('待签署')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#FF9800')
            .borderRadius(12)
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 内容区
      if (this.hasConsent()) {
        // ✅ 已签署 - 使用 Canvas 显示签名
        Column() {
          Text('患者签名')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ bottom: 8 })
            .alignSelf(ItemAlign.Start)

          // ✅ 使用 Canvas 组件显示签名
          if (this.currentTask!.consent_signature!.signature_paths) {
            SignatureCanvas({
              pathsJson: this.currentTask!.consent_signature!.signature_paths
            })
          } else {
            // 兜底：显示提示（适用于旧数据）
            Column() {
              Text('⚠️')
                .fontSize(32)
                .margin({ bottom: 4 })

              Text('签名数据不完整')
                .fontSize(12)
                .fontColor('#999999')
            }
            .width('100%')
            .height(120)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#FAFAFA')
            .borderRadius(8)
            .border({
              width: 1,
              color: '#E5E5E5'
            })
          }

          Row() {
            Text(`签署时间：${this.currentTask!.consent_signature!.signature_time}`)
              .fontSize(12)
              .fontColor('#999999')
              .margin({ top: 8 })
          }
          .width('100%')
        }
        .width('100%')
        .onClick(() => {
          this.handleConsentClick();
        })

      } else {
        // ✅ 未签署 - 显示温馨提示
        Column() {
          // 提示图标
          Text('📝')
            .fontSize(40)
            .margin({ bottom: 8 })

          // 主要提示
          Text('温馨提示')
            .fontSize(14)
            .fontColor('#333333')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 6 })

          // 说明文本
          Text('可以先填写随访表单，但需签署知情同意书后才能上传数据')
            .fontSize(12)
            .fontColor('#666666')
            .textAlign(TextAlign.Center)
            .lineHeight(18)
            .margin({ bottom: 14 })
            .width('90%')

          // 签署按钮
          Button('立即签署')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF6B00')
            .height(38)
            .width(110)
            .borderRadius(19)
            .onClick(() => {
              this.handleConsentClick();
            })
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFF9F0')
        .borderRadius(8)
        .border({
          width: 1,
          color: '#FFE7BA',
          style: BorderStyle.Dashed
        })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ top: 16 })
    .shadow({
      radius: 8,
      color: '#00000008',
      offsetX: 0,
      offsetY: 2
    })
  }

  /**
   * 表单卡片组件
   */
  @Builder
  TableCard(table: FormTable, index: number) {
    Row() {
      // 左侧状态指示器
      Column() {
        Text(this.getTableStateIcon(table.id, table.state))
          .fontSize(24)
          .fontColor(this.getTableStateColor(table.id, table.state))
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
            .fontColor(this.isTableFillable(table) ? '#333333' : '#999999')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.getTableStateText(table.id, table.state))
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.getTableStateColor(table.id, table.state))
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
          if (this.hasLocalRecord(table.id) && !this.isRecordUploaded(table.id)) {
            Row() {
              Text('继续编辑')
                .fontSize(12)
                .fontColor('#1890FF')
                .fontWeight(FontWeight.Medium)

              Text('›')
                .fontSize(14)
                .fontColor('#1890FF')
                .margin({ left: 2 })
            }
          } else if (table.state === 1) {
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
    .backgroundColor(this.isTableFillable(table) ? '#FFFFFF' : '#FAFAFA')
    .borderRadius(12)
    .margin({ bottom: index < this.currentTask!.project!.tables.length - 1 ? 10 : 0 })
    .opacity(this.isTableFillable(table) ? 1.0 : 0.75)
    .shadow({
      radius: 6,
      color: this.isTableFillable(table) ? '#00000008' : '#00000003',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.handleFormClick(table);
    })
  }
}