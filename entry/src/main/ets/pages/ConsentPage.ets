/**
 * 知情同意书签署页面 - 修复触摸冲突
 */
import router from '@ohos.router';
import { FollowUpTask, ConsentSignature } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import storage, { StorageKeys } from '../utils/storage';
import util from '@ohos.util';

// ✅ 绘制点
interface DrawPoint {
  x: number;
  y: number;
}

// ✅ 绘制路径
interface DrawPath {
  points: DrawPoint[];
}

@Entry
@Component
struct ConsentPage {
  @State currentTask: FollowUpTask | null = null;
  @State currentUsername: string = '';
  @State toastController: ToastController = new ToastController();
  @State isSigning: boolean = false;

  // 画布相关
  private canvasContext: CanvasRenderingContext2D | null = null;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private isDrawing: boolean = false;
  @State hasSignature: boolean = false;

  // ✅ 存储绘制路径
  private drawPaths: DrawPath[] = [];
  private currentPath: DrawPath | null = null;

  // ✅ Canvas 尺寸
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  async aboutToAppear() {
    console.log('========== ConsentPage 加载 ==========');

    const params = router.getParams() as Record<string, Object>;

    if (params && params['task']) {
      this.currentTask = params['task'] as FollowUpTask;
    }

    if (params && params['username']) {
      this.currentUsername = params['username'] as string;
    }

    console.log('任务ID:', this.currentTask?.id);
    console.log('患者:', this.currentTask?.name);
  }

  /**
   * ✅ Canvas 准备完成
   */
  onCanvasReady() {
    console.log('========== Canvas 准备完成 ==========');
    if (this.canvasContext) {
      // 设置画笔样式
      this.canvasContext.strokeStyle = '#000000';
      this.canvasContext.lineWidth = 4;
      this.canvasContext.lineCap = 'round';
      this.canvasContext.lineJoin = 'round';

      // 填充白色背景
      this.canvasContext.fillStyle = '#FFFFFF';
      this.canvasContext.fillRect(0, 0, 2000, 2000);

      console.log('Canvas 配置完成');
    }
  }

  /**
   * ✅ 开始绘制
   */
  onTouchStart(event: TouchEvent) {
    if (!this.canvasContext) {
      console.log('⚠️ canvasContext 未初始化');
      return;
    }

    const touch = event.touches[0];
    const x = touch.x;
    const y = touch.y;

    console.log('========== 开始绘制 ==========');
    console.log('起点坐标:', x, y);

    this.isDrawing = true;

    // 创建新路径
    this.currentPath = { points: [{ x, y }] };

    // 开始绘制
    this.canvasContext.beginPath();
    this.canvasContext.moveTo(x, y);

    // 绘制一个小圆点（确保起点可见）
    this.canvasContext.fillStyle = '#000000';
    this.canvasContext.arc(x, y, 2, 0, 2 * Math.PI);
    this.canvasContext.fill();
  }

  /**
   * ✅ 绘制中
   */
  onTouchMove(event: TouchEvent) {
    if (!this.canvasContext || !this.isDrawing || !this.currentPath) {
      return;
    }

    const touch = event.touches[0];
    const x = touch.x;
    const y = touch.y;

    // 记录路径点
    this.currentPath.points.push({ x, y });

    // 绘制线条
    this.canvasContext.lineTo(x, y);
    this.canvasContext.stroke();

    this.hasSignature = true;
  }

  /**
   * ✅ 结束绘制
   */
  onTouchEnd() {
    console.log('========== 结束绘制 ==========');
    if (this.currentPath && this.currentPath.points.length > 0) {
      console.log('路径点数:', this.currentPath.points.length);
      this.drawPaths.push(this.currentPath);
      this.currentPath = null;
    }
    this.isDrawing = false;
    console.log('总路径数:', this.drawPaths.length);
  }

  /**
   * ✅ 清除签名
   */
  handleClear() {
    if (!this.canvasContext) return;

    console.log('清除签名');

    // 清除画布
    this.canvasContext.clearRect(0, 0, 2000, 2000);

    // 重新填充白色背景
    this.canvasContext.fillStyle = '#FFFFFF';
    this.canvasContext.fillRect(0, 0, 2000, 2000);

    // 清除路径数据
    this.drawPaths = [];
    this.currentPath = null;
    this.hasSignature = false;

    this.toastController.show('已清除');
  }

  /**
   * ✅ 将路径转换为 SVG 格式字符串
   */
  pathsToSvg(): string {
    const width = this.canvasWidth || 800;
    const height = this.canvasHeight || 400;

    let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`;
    svg += `<rect width="${width}" height="${height}" fill="white"/>`;

    this.drawPaths.forEach(path => {
      if (path.points.length === 0) return;

      svg += '<path d="M';
      path.points.forEach((point, index) => {
        if (index === 0) {
          svg += `${point.x.toFixed(2)},${point.y.toFixed(2)}`;
        } else {
          svg += ` L${point.x.toFixed(2)},${point.y.toFixed(2)}`;
        }
      });
      svg += '" stroke="black" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>';
    });

    svg += '</svg>';
    return svg;
  }

  /**
   * ✅ 字符串转 Base64（HarmonyOS 方式）
   */
  stringToBase64(str: string): string {
    try {
      const textEncoder = new util.TextEncoder();
      const uint8Array = textEncoder.encodeInto(str);
      const base64Helper = new util.Base64Helper();
      const base64Str = base64Helper.encodeToStringSync(uint8Array);
      return base64Str;
    } catch (e) {
      console.error('Base64 编码失败:', e);
      return '';
    }
  }

  /**
   * ✅ 保存签名
   */
  async handleSave() {
    if (!this.hasSignature) {
      this.toastController.show('请先签名');
      return;
    }

    if (!this.currentTask) {
      this.toastController.show('任务数据错误');
      return;
    }

    if (this.drawPaths.length === 0) {
      this.toastController.show('请先签名');
      return;
    }

    try {
      this.isSigning = true;

      console.log('========== 保存签名 ==========');
      console.log('路径数量:', this.drawPaths.length);

      // 将路径转换为 SVG
      const svgData = this.pathsToSvg();
      console.log('SVG 数据长度:', svgData.length);

      // ✅ 使用 HarmonyOS 的 Base64 编码
      const base64Svg = this.stringToBase64(svgData);
      console.log('Base64 编码长度:', base64Svg.length);

      if (!base64Svg) {
        throw new Error('Base64 编码失败');
      }

      // 创建签名记录
      const signature: ConsentSignature = {
        signature_image: 'data:image/svg+xml;base64,' + base64Svg,
        signature_time: this.getCurrentTime(),
        patient_name: this.currentTask.name,
        patient_no: this.currentTask.patient_no
      };

      console.log('签名数据创建成功');

      // 保存到任务
      this.currentTask.consent_signature = signature;

      // 更新本地存储
      const tasks = await storage.loadFollowUpTasks(this.currentUsername);
      const taskIndex = tasks.findIndex(t => t.id === this.currentTask!.id);

      if (taskIndex !== -1) {
        tasks[taskIndex].consent_signature = signature;
        await storage.saveFollowUpTasks(this.currentUsername, tasks);
        console.log('✅ 签名已保存到本地');
      }

      this.toastController.show('签署成功');

      setTimeout(() => {
        router.back();
      }, 500);

    } catch (e) {
      console.error('❌ 保存签名失败:', e);
      this.toastController.show('保存失败');
    } finally {
      this.isSigning = false;
    }
  }

  /**
   * ✅ 获取当前时间
   */
  getCurrentTime(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hour = String(now.getHours()).padStart(2, '0');
    const minute = String(now.getMinutes()).padStart(2, '0');
    const second = String(now.getSeconds()).padStart(2, '0');

    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Button('取消')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor('#666666')
            .onClick(() => {
              router.back();
            })

          Text('知情同意书签署')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button('清除')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor('#FF6B00')
            .onClick(() => {
              this.handleClear();
            })
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

        // ✅ 可滚动内容区域
        Scroll() {
          Column() {
            // 知情同意书内容
            Column() {
              Text('知情同意书')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .margin({ bottom: 16 })

              Text('尊敬的患者及家属：')
                .fontSize(14)
                .fontColor('#333333')
                .margin({ bottom: 12 })
                .alignSelf(ItemAlign.Start)

              Text('您好！感谢您参与本次随访调查。本次随访旨在了解您的健康状况和生活质量，所收集的信息将严格保密，仅用于医学研究和改善医疗服务。')
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(22)
                .margin({ bottom: 12 })

              Text('随访内容包括：')
                .fontSize(14)
                .fontColor('#333333')
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              Text('1. 基本健康状况评估\n2. 用药情况记录\n3. 生活质量调查\n4. 不良反应监测')
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(24)
                .margin({ bottom: 16 })

              Text('您有权随时退出本次随访，这不会影响您的正常医疗服务。')
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(22)
                .margin({ bottom: 16 })

              Text('如有任何疑问，请联系您的主治医生或随访工作人员。')
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(22)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)

            // 患者信息
            Column() {
              Row() {
                Text('患者姓名：')
                  .fontSize(14)
                  .fontColor('#666666')

                Text(this.currentTask?.name || '')
                  .fontSize(14)
                  .fontColor('#333333')
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Text('患者编号：')
                  .fontSize(14)
                  .fontColor('#666666')

                Text(this.currentTask?.patient_no || '')
                  .fontSize(14)
                  .fontColor('#333333')
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ top: 12, bottom: 12 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12 })
        }
        .layoutWeight(1)
        .backgroundColor('#F5F5F5')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        // ✅ 签名区域（固定在 Scroll 外）
        Column() {
          Column() {
            Text('请在下方签名')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .margin({ bottom: 8 })
              .alignSelf(ItemAlign.Start)

            // Canvas 画布
            Canvas(this.canvasContext)
              .width('100%')
              .height(180)
              .backgroundColor('#FFFFFF')
              .border({
                width: 2,
                color: '#E5E5E5',
                style: BorderStyle.Dashed
              })
              .borderRadius(8)
              .onReady(() => {
                console.log('Canvas onReady 触发');
                this.canvasContext = new CanvasRenderingContext2D(this.settings);
                this.onCanvasReady();
              })
              .onAreaChange((oldValue: Area, newValue: Area) => {
                this.canvasWidth = Number(newValue.width);
                this.canvasHeight = Number(newValue.height);
                console.log('Canvas 尺寸:', this.canvasWidth, 'x', this.canvasHeight);
              })
              .onTouch((event: TouchEvent) => {
                console.log('Touch 事件:', event.type, 'x:', event.touches[0]?.x, 'y:', event.touches[0]?.y);

                if (event.type === TouchType.Down) {
                  this.onTouchStart(event);
                } else if (event.type === TouchType.Move) {
                  this.onTouchMove(event);
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.onTouchEnd();
                }
              })

            Text('请用手指在上方空白区域签名')
              .fontSize(11)
              .fontColor('#999999')
              .margin({ top: 6 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .border({
          width: { top: 0.5 },
          color: '#E5E5E5'
        })

        // 底部按钮
        Row() {
          Button(this.isSigning ? '签署中...' : '确认签署')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor(this.hasSignature && !this.isSigning ? '#FF6B00' : '#CCCCCC')
            .height(48)
            .width('100%')
            .borderRadius(24)
            .enabled(this.hasSignature && !this.isSigning)
            .onClick(() => {
              this.handleSave();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')

      // Toast
      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}