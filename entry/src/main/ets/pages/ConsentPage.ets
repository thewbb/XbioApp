/**
 * 知情同意书签署页面 - 排版优化版
 */
import router from '@ohos.router';
import { FollowUpTask, ConsentSignature } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import storage, { StorageKeys } from '../utils/storage';
import util from '@ohos.util';

// ... (DrawPoint, DrawPath 接口保持不变，省略以节省空间) ...
interface DrawPoint {
  x: number;
  y: number;
}

interface DrawPath {
  points: DrawPoint[];
}

@Entry
@Component
struct ConsentPage {
  // ... (状态变量保持不变) ...
  @State currentTask: FollowUpTask | null = null;
  @State currentUsername: string = '';
  @State toastController: ToastController = new ToastController();
  @State isSigning: boolean = false;
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private isDrawing: boolean = false;
  @State hasSignature: boolean = false;
  private drawPaths: DrawPath[] = [];
  private currentPath: DrawPath | null = null;
  private uiContext: UIContext | null = null;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  async aboutToAppear() {
    // ... (逻辑保持不变) ...
    const params = router.getParams() as Record<string, Object>;
    this.uiContext = this.getUIContext();
    if (params && params['task']) {
      this.currentTask = params['task'] as FollowUpTask;
    }
    if (params && params['username']) {
      this.currentUsername = params['username'] as string;
    }
  }

  // ... (onCanvasReady, onTouchStart, onTouchMove, onTouchEnd, handleClear, pathsToSvg, handleSave, getCurrentTime 等方法保持不变) ...

  onCanvasReady() {
    this.canvasContext.strokeStyle = '#000000';
    this.canvasContext.lineWidth = 4;
    this.canvasContext.lineCap = 'round';
    this.canvasContext.lineJoin = 'round';
    this.canvasContext.fillStyle = '#FFFFFF';
    this.canvasContext.fillRect(0, 0, 2000, 2000);
  }

  onTouchStart(event: TouchEvent) {
    const touch = event.touches[0];
    this.isDrawing = true;
    this.currentPath = { points: [{ x: touch.x, y: touch.y }] };
    this.canvasContext.beginPath();
    this.canvasContext.moveTo(touch.x, touch.y);
    this.canvasContext.fillStyle = '#000000';
    this.canvasContext.beginPath();
    this.canvasContext.arc(touch.x, touch.y, 2, 0, 2 * Math.PI);
    this.canvasContext.fill();
    this.canvasContext.strokeStyle = '#000000';
    this.canvasContext.lineWidth = 4;
    this.canvasContext.beginPath();
    this.canvasContext.moveTo(touch.x, touch.y);
  }

  onTouchMove(event: TouchEvent) {
    if (!this.isDrawing || !this.currentPath) return;
    const touch = event.touches[0];
    this.currentPath.points.push({ x: touch.x, y: touch.y });
    this.canvasContext.lineTo(touch.x, touch.y);
    this.canvasContext.stroke();
    this.hasSignature = true;
  }

  onTouchEnd() {
    if (this.currentPath && this.currentPath.points.length > 0) {
      this.drawPaths.push(this.currentPath);
      this.currentPath = null;
    }
    this.isDrawing = false;
  }

  handleClear() {
    this.canvasContext.clearRect(0, 0, 2000, 2000);
    this.canvasContext.fillStyle = '#FFFFFF';
    this.canvasContext.fillRect(0, 0, 2000, 2000);
    this.drawPaths = [];
    this.currentPath = null;
    this.hasSignature = false;
    this.toastController.show('已清除');
  }

  pathsToSvg(): string {
    const width = this.canvasWidth || 800;
    const height = this.canvasHeight || 180;
    let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`;
    svg += `<rect width="${width}" height="${height}" fill="white"/>`;
    this.drawPaths.forEach(path => {
      if (path.points.length === 0) return;
      svg += '<path d="M';
      path.points.forEach((point, index) => {
        if (index === 0) svg += `${point.x.toFixed(2)},${point.y.toFixed(2)}`;
        else svg += ` L${point.x.toFixed(2)},${point.y.toFixed(2)}`;
      });
      svg += '" stroke="black" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>';
    });
    svg += '</svg>';
    return svg;
  }

  getCurrentTime(): string {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  }

  async handleSave() {
    // ... (逻辑保持不变，省略以聚焦 UI 修改) ...
    if (!this.hasSignature) { this.toastController.show('请先签名'); return; }
    try {
      this.isSigning = true;
      const svgData = this.pathsToSvg();
      const encodedSvg = encodeURIComponent(svgData);
      const signatureImage = 'data:image/svg+xml;charset=utf-8,' + encodedSvg;

      // 保存逻辑...
      if (this.currentTask) {
        const pathsData = JSON.stringify({ paths: this.drawPaths, canvasWidth: this.canvasWidth, canvasHeight: this.canvasHeight });
        const signature: ConsentSignature = {
          signature_image: signatureImage,
          signature_time: this.getCurrentTime(),
          patient_name: this.currentTask.name,
          patient_no: this.currentTask.patient_no,
          signature_paths: pathsData
        };
        this.currentTask.consent_signature = signature;
        const tasks = await storage.loadFollowUpTasks(this.currentUsername);
        const taskIndex = tasks.findIndex(t => t.id === this.currentTask!.id);
        if (taskIndex !== -1) {
          tasks[taskIndex].consent_signature = signature;
          await storage.saveFollowUpTasks(this.currentUsername, tasks);
        }
        this.toastController.show('签署成功');
        setTimeout(() => { if(this.uiContext) this.uiContext.getRouter().back(); }, 500);
      }
    } catch (e) {
      this.toastController.show('保存失败');
    } finally {
      this.isSigning = false;
    }
  }

  @Builder
  Paragraph(title: string, content: string) {
    Text() {
      Span(title)
        .fontWeight(FontWeight.Bold)
        .fontSize(15)
        .fontColor('#000000')
        .decoration({ type: TextDecorationType.Underline, color: '#000000' }) // 下划线
      Span('：' + content)
        .fontSize(15)
        .fontColor('#333333')
    }
    .width('100%')
    .lineHeight(24) // 增加行高，提升阅读体验
    .margin({ bottom: 12 })
    .textAlign(TextAlign.Start) // 左对齐
  }

  build() {
    Stack() {
      Column() {
        // 1. 顶部导航栏
        Row() {
          Button('取消')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor('#666666')
            .onClick(() => router.back())

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
            .onClick(() => this.handleClear())
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .justifyContent(FlexAlign.SpaceBetween)
        .border({ width: { bottom: 0.5 }, color: '#E5E5E5' })

        // 2. 可滚动内容区域 (核心修改区域)
        Scroll() {
          Column() {
            // 白色卡片容器
            Column() {
              // 2.1 大标题
              Text('本项调查由中国医科大学附属盛京医院开展的“肿瘤患者病因及转归研究”')
                .fontSize(17)
                .fontWeight(FontWeight.Bold) // 粗体
                .fontColor('#000000')
                .textAlign(TextAlign.Center) // 居中
                .lineHeight(26)
                .margin({ bottom: 20 })

              // 2.2 各个段落（使用 Builder 封装的样式）
              this.Paragraph('目的和内容', '本研究旨在了解疾病发病风险及疾病转归因素。研究与疾病发病有关的膳食、环境等风险因素对疾病发病及转归的影响。以指导疾病预防策略的制定。')

              this.Paragraph('可能的风险', '本调查不会产生任何大于常规检查的风险。')

              this.Paragraph('收益和好处', '我们治疗组将根据您所填写的信息对您的治疗方案进行有针对性的研究和调整。')

              this.Paragraph('保密承诺', '我们保证任何情况下不会以任何形式泄露您个人信息和检查结果。')

              this.Paragraph('自愿原则', '本调查是自愿的，您可以拒绝参加或随时退出。')

              // 2.3 最后的声明（加粗，缩进效果）
              Text() {
                Span('      我已与课题组人员进行了详细的沟通， 充分了解了本次调查的目的、内容、可能的风险与收益， ')
                Span('在此自愿参加本调查。')
              }
              .fontSize(15)
              .fontWeight(FontWeight.Bold) // 整体加粗
              .fontColor('#000000')
              .lineHeight(26)
              .margin({ top: 10, bottom: 20 })
            }
            .width('100%')
            .padding(20) // 增加内边距，像A4纸一样
            .backgroundColor('#FFFFFF')
            // 去掉圆角，更像正式文件
            // .borderRadius(12)

            // 2.4 患者简要信息（仅作确认用，放在文件下方）
            Column() {
              Row() {
                Text('签署人：').fontSize(14).fontColor('#666666')
                Text(this.currentTask?.name || '').fontSize(14).fontColor('#333333').fontWeight(FontWeight.Medium)

                Text('    编号：').fontSize(14).fontColor('#666666')
                Text(this.currentTask?.patient_no || '').fontSize(14).fontColor('#333333').fontWeight(FontWeight.Medium)
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)
            }
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 10 })
            .backgroundColor('#FFFFFF')

          }
          .width('100%')
          // 关键：alignItems 默认就是 Center，但 Scroll 内容要撑满，通常 Column 默认是从上到下
          .justifyContent(FlexAlign.Start) // 确保内容靠上对齐
        }
        .layoutWeight(1)
        .backgroundColor('#F5F5F5') // 灰色背景衬托白色纸张
        .align(Alignment.Top) // Scroll 内容顶部对齐
        .edgeEffect(EdgeEffect.Spring)

        // 3. 签名区域 (保持不变)
        Column() {
          Column() {
            Text('请在下方空白处签名')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .margin({ bottom: 8 })
              .alignSelf(ItemAlign.Start)

            Canvas(this.canvasContext)
              .width('100%')
              .height(180)
              .backgroundColor('#FFFFFF')
              .border({ width: 2, color: '#E5E5E5', style: BorderStyle.Dashed })
              .borderRadius(8)
              .onReady(() => this.onCanvasReady())
              .onAreaChange((o, n) => { this.canvasWidth = Number(n.width); this.canvasHeight = Number(n.height); })
              .onTouch((e) => {
                if (e.touches.length > 0) {
                  if (e.type === TouchType.Down) this.onTouchStart(e);
                  else if (e.type === TouchType.Move) this.onTouchMove(e);
                  else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.onTouchEnd();
                }
              })

            Text('请务必由患者本人或其授权代理人签署')
              .fontSize(11)
              .fontColor('#999999')
              .margin({ top: 6 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .border({ width: { top: 0.5 }, color: '#E5E5E5' })

        // 4. 底部按钮
        Row() {
          Button(this.isSigning ? '签署中...' : '确认签署并提交')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor(this.hasSignature && !this.isSigning ? '#000000' : '#CCCCCC') // 改为黑色更严肃，或保持 #FF6B00
            .height(48)
            .width('100%')
            .borderRadius(4) // 按钮方一点，显得正式
            .enabled(this.hasSignature && !this.isSigning)
            .onClick(() => this.handleSave())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')

      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }
}