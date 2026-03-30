/**
 * 随访任务详情页 - 支持本地数据 + 知情同意书签署
 */
import router from '@ohos.router';
import { FollowUpTask, FormTable, FormField, FormRecord } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import storage, { StorageKeys } from '../utils/storage';
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


    if (!this.currentTask) {
      this.toastController.show('任务数据错误');
      setTimeout(() => {
        router.back();
      }, 500);
      return;
    }

    // ✅ 初始化加载最新数据
    await this.loadLatestTaskData();
  }

  /**
   * ✅ 页面显示时刷新数据
   * 场景：当从 FormPage (填写页) 或 ConsentPage (签名页) 返回此页面时，
   * 需要重新读取 Storage，以更新进度条和状态。
   */
  async onPageShow() {
    if (this.currentTask && this.currentUsername) {
      await this.loadLatestTaskData();
    }
  }

  /**
   * ✅ 统一从 Storage 加载任务数据
   * 确保与 MissionTab 使用完全相同的 Key 和解析逻辑
   */
  async loadLatestTaskData() {
    try {
      // 使用与 MissionTab 相同的读取方式
      const tasksStr: string = await storage.getUserData(this.currentUsername, StorageKeys.FOLLOW_UP_TASKS);

      if (tasksStr) {
        const tasks = JSON.parse(tasksStr) as FollowUpTask[];
        const latestTask = tasks.find(t => t.id === this.currentTask?.id);

        if (latestTask) {
          // 更新当前内存中的任务对象
          this.currentTask = latestTask;
        }
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
    // ✅ 使用 table_id 判断
    return this.currentTask.local_records.some(r => r.table_id === tableId);
  }

  /**
   * 检查记录是否已上传
   */
  isRecordUploaded(tableId: number): boolean {
    if (!this.currentTask?.local_records) {
      return false;
    }
    // ✅ 使用 table_id 判断
    const record = this.currentTask.local_records.find(r => r.table_id === tableId);
    return record?.is_uploaded || false;
  }

  getStateText(state: number): string {
    switch (state) {
      case 0: return '待执行';
      case 1: return '进行中';
      case 2: return '已完成';
      default: return '未知';
    }
  }

  getStateColor(state: number): string {
    switch (state) {
      case 0: return '#FF6B00';
      case 1: return '#1890FF';
      case 2: return '#52C41A';
      default: return '#999999';
    }
  }

  getTableStateText(tableId: number, state: number): string {
    const hasLocalData = this.hasLocalRecord(tableId);
    const isUploaded = this.isRecordUploaded(tableId);

    if (hasLocalData && !isUploaded) {
      return '待上传';
    }
    return state === 1 ? '已填写' : '未填写';
  }

  getTableStateColor(tableId: number, state: number): string {
    const hasLocalData = this.hasLocalRecord(tableId);
    const isUploaded = this.isRecordUploaded(tableId);

    if (hasLocalData && !isUploaded) {
      return '#1890FF';  // 待上传用蓝色
    }
    return state === 1 ? '#52C41A' : '#FF6B00';
  }

  getTableStateIcon(tableId: number, state: number): string {
    const hasLocalData = this.hasLocalRecord(tableId);
    const isUploaded = this.isRecordUploaded(tableId);

    if (hasLocalData && !isUploaded) {
      return '📝';
    }
    return state === 1 ? '✓' : '○';
  }

  // 改为：区分"可编辑"和"可查看"
  isTableEditable(table: FormTable): boolean {
    return !this.isRecordUploaded(table.id);
  }

  isTableViewable(table: FormTable): boolean {
    // 已上传或本地有记录，都可以查看
    return this.hasLocalRecord(table.id) || table.state === 1;
  }

  handleConsentClick() {
    if (this.hasConsent()) {
      this.toastController.show('已签署');
      return;
    }

    router.pushUrl({
      url: 'pages/ConsentPage',
      params: {
        task: this.currentTask,
        username: this.currentUsername
      }
    }).catch((err: Error) => {
      this.toastController.show('打开失败');
    });
  }

  handleFormClick(table: FormTable) {
    const isUploaded = this.isRecordUploaded(table.id);
    const hasLocal = this.hasLocalRecord(table.id);

    // 已上传：允许只读查看
    if (isUploaded) {
      router.pushUrl({
        url: 'pages/FormPage',
        params: {
          task: this.currentTask,
          table: table,
          token: this.token,
          username: this.currentUsername,
          readOnly: true   // ← 传入只读标志
        }
      }).catch((err: Error) => {
        this.toastController.show('打开失败');
      });
      return;
    }

    // 未上传：原有逻辑，允许填写/编辑
    if (!this.hasConsent()) {
      this.toastController.show('提醒：需签署知情同意书后才能上传');
    }
    router.pushUrl({
      url: 'pages/FormPage',
      params: {
        task: this.currentTask,
        table: table,
        token: this.token,
        username: this.currentUsername,
        readOnly: false
      }
    }).catch((err: Error) => {
      this.toastController.show('打开失败');
    });
  }

  getTaskStats(): TaskStats {
    if (!this.currentTask || !this.currentTask.project || !this.currentTask.project.tables) {
      const emptyStats: TaskStats = { total: 0, completed: 0, pending: 0, localSaved: 0 };
      return emptyStats;
    }

    const tables = this.currentTask.project.tables;
    const total: number = tables.length;
    // 为了规避 any 类型检查，使用简单类型断言
    interface TempTable { state?: number }
    const completed: number = tables.filter((t: TempTable) => t.state === 1).length;

    let localSaved = 0;
    tables.forEach(table => {
      const hasLocalData = this.hasLocalRecord(table.id);
      const isUploaded = this.isRecordUploaded(table.id);
      if (hasLocalData && !isUploaded) {
        localSaved++;
      }
    });

    const pending: number = total - completed;

    return {
      total: total,
      completed: completed,
      pending: pending,
      localSaved: localSaved
    };
  }

  getEditableFieldCount(table: FormTable): number {
    if (!table.fields) {
      return 0;
    }
    return table.fields.filter((f: FormField) => f.is_editable === '1').length;
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
              // ✅ 点击返回时，MissionTab 的 onPageShow 会自动触发刷新
              router.back();
            })

          Text('任务详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

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

        if (!this.currentTask) {
          Column() {
            Text('❌').fontSize(60).margin({ bottom: 12 })
            Text('任务数据错误').fontSize(14).fontColor('#999999')
            Button('返回').fontSize(14).margin({ top: 20 }).backgroundColor('#FF6B00').borderRadius(8)
              .onClick(() => { router.back(); })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).backgroundColor('#F5F5F5')

        } else {
          Scroll() {
            Column() {
              // 基本信息卡片
              Column() {
                Row() {
                  Text('基本信息').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#333333')
                  Blank()
                  Text(this.getStateText(this.currentTask.state))
                    .fontSize(11).fontColor('#FFFFFF')
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .backgroundColor(this.getStateColor(this.currentTask.state)).borderRadius(12)
                }.width('100%').margin({ bottom: 16 })

                Column() {
                  this.InfoRow('患者编号', this.currentTask.patient_no)
                  Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })
                  this.InfoRow('患者姓名', this.currentTask.name)
                  Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })
                  this.InfoRow('随访项目', this.currentTask.project_name)
                  Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })
                  this.InfoRow('任务发布人', this.currentTask.creator)
                  Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })
                  this.InfoRow('创建时间', this.currentTask.create_time)
                  Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })

                  Row() {
                    Text('完成进度').fontSize(14).fontColor('#999999').width(90)
                    Row() {
                      Text(`${this.getTaskStats().completed}/${this.getTaskStats().total}`)
                        .fontSize(14).fontColor('#333333').margin({ right: 8 })
                      Text(`${this.currentTask.percent}%`)
                        .fontSize(14).fontColor('#1890FF').fontWeight(FontWeight.Bold)
                    }.layoutWeight(1)
                  }.width('100%').alignItems(VerticalAlign.Center)

                  if (this.getTaskStats().localSaved > 0) {
                    Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })
                    Row() {
                      Text('待上传').fontSize(14).fontColor('#999999').width(90)
                      Row() {
                        Text(`${this.getTaskStats().localSaved} 份`)
                          .fontSize(14).fontColor('#1890FF').fontWeight(FontWeight.Medium)
                        Text('📝').fontSize(14).margin({ left: 4 })
                      }.layoutWeight(1)
                    }.width('100%').alignItems(VerticalAlign.Center)
                  }
                }.width('100%')
              }
              .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12)
              .shadow({ radius: 8, color: '#00000008', offsetX: 0, offsetY: 2 })

              this.ConsentCard()

              if (this.currentTask.project && this.currentTask.project.tables && this.currentTask.project.tables.length > 0) {
                Column() {
                  Row() {
                    Text('随访表单').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#333333')
                    Blank()
                    if (this.getTaskStats().localSaved > 0) {
                      Text(`${this.getTaskStats().localSaved} 份待上传`)
                        .fontSize(11).fontColor('#1890FF').padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor('#E6F7FF').borderRadius(12)
                    } else if (this.getTaskStats().pending > 0) {
                      Text(`还有 ${this.getTaskStats().pending} 张待填写`)
                        .fontSize(11).fontColor('#FF6B00').padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor('#FFF7F0').borderRadius(12)
                    } else {
                      Text('全部已完成')
                        .fontSize(11).fontColor('#52C41A').padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor('#F6FFED').borderRadius(12)
                    }
                  }.width('100%').margin({ bottom: 12 })

                  Column() {
                    ForEach(this.currentTask.project.tables, (table: FormTable, index: number) => {
                      this.TableCard(table, index)
                    })
                  }.width('100%')
                }.width('100%').margin({ top: 16 })
              }
            }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 12 })
          }.width('100%').backgroundColor('#F5F5F5').scrollBar(BarState.Auto)
        }
      }.width('100%').height('100%')

      CustomToast({ controller: this.toastController })
    }.width('100%').height('100%')
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#999999').width(90)
      Text(value).fontSize(14).fontColor('#333333').layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  @Builder
  ConsentCard() {
    Column() {
      Row() {
        Text('知情同意书').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#333333')
        Blank()
        if (this.hasConsent()) {
          Text('已签署').fontSize(11).fontColor('#FFFFFF').padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#52C41A').borderRadius(12)
        } else {
          Text('待签署').fontSize(11).fontColor('#FFFFFF').padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#FF9800').borderRadius(12)
        }
      }.width('100%').margin({ bottom: 12 })

      if (this.hasConsent()) {
        Column() {
          Text('患者签名').fontSize(12).fontColor('#999999').margin({ bottom: 8 }).alignSelf(ItemAlign.Start)
          if (this.currentTask!.consent_signature!.signature_paths) {
            SignatureCanvas({ pathsJson: this.currentTask!.consent_signature!.signature_paths })
          } else {
            Column() {
              Text('⚠️').fontSize(32).margin({ bottom: 4 })
              Text('签名数据不完整').fontSize(12).fontColor('#999999')
            }.width('100%').height(120).justifyContent(FlexAlign.Center).backgroundColor('#FAFAFA').borderRadius(8).border({ width: 1, color: '#E5E5E5' })
          }
          Row() {
            Text(`签署时间：${this.currentTask!.consent_signature!.signature_time}`).fontSize(12).fontColor('#999999').margin({ top: 8 })
          }.width('100%')
        }.width('100%').onClick(() => { this.handleConsentClick(); })
      } else {
        Column() {
          Text('📝').fontSize(40).margin({ bottom: 8 })
          Text('温馨提示').fontSize(14).fontColor('#333333').fontWeight(FontWeight.Medium).margin({ bottom: 6 })
          Text('可以先填写随访表单，但需签署知情同意书后才能上传数据')
            .fontSize(12).fontColor('#666666').textAlign(TextAlign.Center).lineHeight(18).margin({ bottom: 14 }).width('90%')
          Button('立即签署').fontSize(14).fontColor('#FFFFFF').backgroundColor('#FF6B00').height(38).width(110).borderRadius(19)
            .onClick(() => { this.handleConsentClick(); })
        }.width('100%').padding({ top: 16, bottom: 16 }).justifyContent(FlexAlign.Center).backgroundColor('#FFF9F0').borderRadius(8).border({ width: 1, color: '#FFE7BA', style: BorderStyle.Dashed })
      }
    }.width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12).margin({ top: 16 })
    .shadow({ radius: 8, color: '#00000008', offsetX: 0, offsetY: 2 })
  }

  @Builder
  TableCard(table: FormTable, index: number) {
    Row() {
      Column() {
        Text(this.getTableStateIcon(table.id, table.state))
          .fontSize(24).fontColor(this.getTableStateColor(table.id, table.state)).fontWeight(FontWeight.Bold)
      }.width(40).justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          Text(table.step_name).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.isTableEditable(table) ? '#333333' : '#999999')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text(this.getTableStateText(table.id, table.state)).fontSize(11).fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 }).backgroundColor(this.getTableStateColor(table.id, table.state))
            .borderRadius(10).margin({ left: 8 })
        }.width('100%').margin({ bottom: 8 })

        Row() {
          Text(table.multi_line === 1 ? '📋 多行' : '📄 单行').fontSize(12).fontColor('#666666')
          Text('·').fontSize(12).fontColor('#CCCCCC').margin({ left: 8, right: 8 })
          Text(`${this.getEditableFieldCount(table)} 个字段`).fontSize(12).fontColor('#666666')
          Blank()
          if (this.hasLocalRecord(table.id) && !this.isRecordUploaded(table.id)) {
            Row() {
              Text('继续编辑').fontSize(12).fontColor('#1890FF').fontWeight(FontWeight.Medium)
              Text('›').fontSize(14).fontColor('#1890FF').margin({ left: 2 })
            }
            // 改为：
          } else if (this.isRecordUploaded(table.id)) {
            Row() {
              Text('查看').fontSize(12).fontColor('#52C41A').fontWeight(FontWeight.Medium)
              Text('›').fontSize(14).fontColor('#52C41A').margin({ left: 2 })
            }
          } else if (table.state === 1 && !this.hasLocalRecord(table.id)) {
            // 服务器显示已完成但本地无记录（理论上不应出现）
            Text('已完成').fontSize(12).fontColor('#52C41A').fontWeight(FontWeight.Medium)
          } else {
            Row() {
              Text('去填写').fontSize(12).fontColor('#FF6B00').fontWeight(FontWeight.Medium)
              Text('›').fontSize(14).fontColor('#FF6B00').margin({ left: 2 })
            }
          }
        }.width('100%')
      }.layoutWeight(1)
    }
    .width('100%').padding(14).backgroundColor(this.isTableEditable(table) ? '#FFFFFF' : '#FAFAFA').opacity(1.0)
    .borderRadius(12).margin({ bottom: index < this.currentTask!.project!.tables.length - 1 ? 10 : 0 })
    .opacity(this.isTableEditable(table) ? 1.0 : 0.75)
    .shadow({ radius: 6, color: this.isTableEditable(table) ? '#00000008' : '#00000003', offsetX: 0, offsetY: 2 })
    .onClick(() => { this.handleFormClick(table); })
  }
}