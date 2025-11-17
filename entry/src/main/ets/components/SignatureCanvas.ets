/**
 * 签名显示组件 - 用 Canvas 重绘签名
 */

interface DrawPoint {
  x: number;
  y: number;
}

interface DrawPath {
  points: DrawPoint[];
}

interface SignatureData {
  paths: DrawPath[];
  canvasWidth: number;
  canvasHeight: number;
}

@Component
export struct SignatureCanvas {
  @Prop pathsJson: string = '';
  @State displayWidth: number = 300;  // ✅ 设置默认值，避免为 0
  @State displayHeight: number = 120;
  @State isReady: boolean = false;  // ✅ 标记是否已准备好

  private canvasContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private signatureData: SignatureData | null = null;

  aboutToAppear() {
    console.log('========== SignatureCanvas 初始化 ==========');

    if (this.pathsJson) {
      try {
        this.signatureData = JSON.parse(this.pathsJson) as SignatureData;
        console.log('✅ 路径数据解析成功:');
        console.log('  - 路径数量:', this.signatureData.paths.length);
        console.log('  - 原始尺寸:', this.signatureData.canvasWidth, 'x', this.signatureData.canvasHeight);

        // 打印第一条路径的点数
        if (this.signatureData.paths.length > 0) {
          console.log('  - 第一条路径点数:', this.signatureData.paths[0].points.length);
        }
      } catch (e) {
        console.error('❌ 路径数据解析失败:', e);
        console.error('JSON 内容:', this.pathsJson.substring(0, 200));
      }
    } else {
      console.log('⚠️ 没有路径数据');
    }
  }

  /**
   * ✅ 绘制签名
   */
  drawSignature() {
    console.log('========== 开始绘制签名 ==========');
    console.log('Canvas 尺寸:', this.displayWidth, 'x', this.displayHeight);

    if (!this.signatureData || this.signatureData.paths.length === 0) {
      console.log('⚠️ 没有签名数据');
      // 显示提示文字
      this.canvasContext.fillStyle = '#FFFFFF';
      this.canvasContext.fillRect(0, 0, this.displayWidth, this.displayHeight);
      this.canvasContext.fillStyle = '#CCCCCC';
      this.canvasContext.font = '14px sans-serif';
      this.canvasContext.textAlign = 'center';
      this.canvasContext.fillText('无签名数据', this.displayWidth / 2, this.displayHeight / 2);
      return;
    }

    if (this.displayWidth === 0 || this.displayHeight === 0) {
      console.log('⚠️ Canvas 尺寸为 0，跳过绘制');
      return;
    }

    // 填充白色背景
    this.canvasContext.fillStyle = '#FFFFFF';
    this.canvasContext.fillRect(0, 0, this.displayWidth, this.displayHeight);

    // 计算缩放比例（保持纵横比）
    const scaleX = this.displayWidth / this.signatureData.canvasWidth;
    const scaleY = this.displayHeight / this.signatureData.canvasHeight;
    const scale = Math.min(scaleX, scaleY, 1);  // 不放大，只缩小

    // 计算居中偏移
    const offsetX = (this.displayWidth - this.signatureData.canvasWidth * scale) / 2;
    const offsetY = (this.displayHeight - this.signatureData.canvasHeight * scale) / 2;

    console.log('缩放比例:', scale);
    console.log('偏移量:', offsetX, 'x', offsetY);

    // 设置画笔样式
    this.canvasContext.strokeStyle = '#000000';
    this.canvasContext.lineWidth = 4 * scale;
    this.canvasContext.lineCap = 'round';
    this.canvasContext.lineJoin = 'round';

    // 绘制所有路径
    let totalPoints = 0;
    this.signatureData.paths.forEach((path, pathIndex) => {
      if (!path.points || path.points.length === 0) {
        console.log(`路径 ${pathIndex} 为空`);
        return;
      }

      this.canvasContext.beginPath();

      path.points.forEach((point, pointIndex) => {
        const x = point.x * scale + offsetX;
        const y = point.y * scale + offsetY;

        if (pointIndex === 0) {
          this.canvasContext.moveTo(x, y);
        } else {
          this.canvasContext.lineTo(x, y);
        }
      });

      this.canvasContext.stroke();
      totalPoints += path.points.length;
      console.log(`路径 ${pathIndex}: ${path.points.length} 个点`);
    });

    console.log('✅ 签名绘制完成');
    console.log('  - 绘制路径数:', this.signatureData.paths.length);
    console.log('  - 总点数:', totalPoints);
  }

  /**
   * ✅ Canvas 准备完成
   */
  onCanvasReady() {
    console.log('========== Canvas onReady 触发 ==========');
    this.isReady = true;

    // 延迟一下确保尺寸已更新
    setTimeout(() => {
      this.drawSignature();
    }, 100);
  }

  build() {
    Canvas(this.canvasContext)
      .width('100%')
      .height(this.displayHeight)
      .backgroundColor('#FAFAFA')
      .borderRadius(8)
      .border({
        width: 1,
        color: '#E5E5E5'
      })
      .onReady(() => {
        this.onCanvasReady();
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);

        console.log('Canvas 尺寸变化:', newWidth, 'x', newHeight);

        // ✅ 只有尺寸真正变化时才重绘
        if (newWidth !== this.displayWidth || newHeight !== this.displayHeight) {
          this.displayWidth = newWidth;
          this.displayHeight = newHeight;

          // ✅ 如果已经准备好，立即重绘
          if (this.isReady && newWidth > 0 && newHeight > 0) {
            console.log('尺寸变化，重新绘制');
            setTimeout(() => {
              this.drawSignature();
            }, 50);
          }
        }
      })
  }
}