
/**
 * 随访任务详情页
 */
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import storage, { StorageKeys } from '../utils/storage';
import http from '../utils/http';
import { TaskDetailRequest, TaskDetailResponse, FormTable } from '../types';

@Entry
@Component
struct MissionPage {
  @State loading: boolean = true;
  @State taskId: number = 0;
  @State token: string = '';
  @State taskDetail: TaskDetailResponse | null = null;
  @State currentUsername: string = '';

  async aboutToAppear() {
    console.log('========== MissionPage 加载 ==========');

    // 获取路由参数
    const params = router.getParams() as Record<string, Object>;
    if (params && params['taskId']) {
      this.taskId = params['taskId'] as number;
    }
    if (params && params['token']) {
      this.token = params['token'] as string;
    }
    if (params && params['username']) {
      this.currentUsername = params['username'] as string;
    }

    console.log('任务ID:', this.taskId);
    console.log('Token:', this.token ? '已获取' : '未获取');

    if (!this.taskId || !this.token) {
      promptAction.showToast({
        message: '参数错误',
        duration: 2000
      });
      setTimeout(() => {
        router.back();
      }, 500);
      return;
    }

    await this.loadTaskDetail();
  }

  /**
   * 加载任务详情
   */
  async loadTaskDetail() {
    try {
      this.loading = true;
      console.log('开始加载任务详情...');

      // 检查网络
      let isOnline = await http.isOnline();
      if (!isOnline) {
        promptAction.showToast({
          message: '网络不可用',
          duration: 2000
        });
        this.loading = false;
        return;
      }

      // 请求任务详情
      const request: TaskDetailRequest = {
        token: this.token,
        task_id: this.taskId
      };

      let response = await http.post('/mobile/taskDetail.json', request);
      console.log('任务详情响应:', JSON.stringify(response));

      if (response.code === 0 && response.dataMap) {
        this.taskDetail = response.dataMap as TaskDetailResponse;
        console.log('✅ 任务详情加载成功');
        console.log('项目:', this.taskDetail.project_name);
        console.log('患者:', this.taskDetail.patient_no);
        console.log('表单数量:', this.taskDetail.project?.tables.length);
      } else {
        promptAction.showToast({
          message: response.message || '加载失败',
          duration: 2000
        });
      }

      this.loading = false;
    } catch (e) {
      console.error('❌ 加载任务详情异常:', e);
      promptAction.showToast({
        message: '加载失败',
        duration: 2000
      });
      this.loading = false;
    }
  }

  /**
   * 获取状态文本
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
   * 获取状态颜色
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
   * 点击表单，开始填写
   */
  handleFormClick(table: FormTable) {
    console.log('点击表单:', table.step_name);
    promptAction.showToast({
      message: `开始填写：${table.step_name}`,
      duration: 1500
    });

    // TODO: 跳转到表单填写页面
    // router.pushUrl({
    //   url: 'pages/FormPage',
    //   params: {
    //     taskId: this.taskId,
    //     tableId: table.id,
    //     tableName: table.step_name,
    //     token: this.token,
    //     username: this.currentUsername
    //   }
    // });
  }

  build() {
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

      // 内容区域
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

      } else if (this.taskDetail) {
        Scroll() {
          Column() {
            // 基本信息卡片
            Column() {
              Row() {
                Text('基本信息')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')

                Blank()

                Text(this.getStateText(this.taskDetail.state))
                  .fontSize(12)
                  .fontColor(this.getStateColor(this.taskDetail.state))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.getStateColor(this.taskDetail.state) + '20')
                  .borderRadius(4)
              }
              .width('100%')
              .margin({ bottom: 16 })

              // 患者编号
              Row() {
                Text('患者编号')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width(100)

                Text(this.taskDetail.patient_no)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 随访项目
              Row() {
                Text('随访项目')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width(100)

                Text(this.taskDetail.project_name)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 任务发布人
              Row() {
                Text('任务发布人')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width(100)

                Text(this.taskDetail.creator)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 创建时间
              Row() {
                Text('创建时间')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width(100)

                Text(this.taskDetail.create_time)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 完成进度
              Row() {
                Text('完成进度')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width(100)

                Text(this.taskDetail.percent)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ bottom: 12 })

            // 随访表单列表
            if (this.taskDetail.project && this.taskDetail.project.tables.length > 0) {
              Column() {
                Text('随访表单')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                  .width('100%')
                  .margin({ bottom: 12 })

                ForEach(this.taskDetail.project.tables, (table: FormTable, index: number) => {
                  Row() {
                    Column() {
                      Row() {
                        Text(table.step_name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#333333')

                        Blank()

                        Text(`${table.fields.length} 个字段`)
                          .fontSize(12)
                          .fontColor('#999999')
                      }
                      .width('100%')
                      .margin({ bottom: 8 })

                      Row() {
                        Text(table.multi_line === 1 ? '📋 多行表单' : '📄 单行表单')
                          .fontSize(12)
                          .fontColor('#666666')

                        Blank()

                        Text('点击填写 ›')
                          .fontSize(12)
                          .fontColor('#FF6B00')
                      }
                      .width('100%')
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor('#FFFFFF')
                  .borderRadius(8)
                  .margin({ bottom: index < this.taskDetail!.project!.tables.length - 1 ? 12 : 0 })
                  .onClick(() => {
                    this.handleFormClick(table);
                  })
                })
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#F9F9F9')
              .borderRadius(8)
            }
          }
          .width('100%')
          .padding(12)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#F5F5F5')

      } else {
        Column() {
          Text('❌')
            .fontSize(60)
            .margin({ bottom: 12 })

          Text('加载失败')
            .fontSize(14)
            .fontColor('#999999')

          Button('重试')
            .fontSize(14)
            .margin({ top: 20 })
            .backgroundColor('#FF6B00')
            .borderRadius(8)
            .onClick(() => {
              this.loadTaskDetail();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F5F5')
      }
    }
    .width('100%')
    .height('100%')
  }
}
