
/**
 * 表单填写页面
 *
 * 功能：
 * - 根据字段配置动态渲染表单
 * - 支持多种字段类型：input, inputUnit, date, select, textarea, file 等
 * - 支持栅格布局（col）和换行控制（new_line）
 * - 表单验证和提交
 */
import router from '@ohos.router';
import { FollowUpTask, FormTable, FormField } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import http from '../utils/http';

/**
 * 表单提交数据接口
 */
interface SubmitFormData {
  token: string;
  task_id: number | undefined;
  table_id: number | undefined;
  step_id: number | undefined;
  patient_no: string | undefined;
  data: Record<string, string>;
}

@Entry
@Component
struct FormPage {
  @State currentTask: FollowUpTask | null = null;
  @State currentTable: FormTable | null = null;
  @State token: string = '';
  @State currentUsername: string = '';
  @State formData: Map<string, string> = new Map();
  @State submitting: boolean = false;
  @State toastController: ToastController = new ToastController();

  // 用于日期选择器
  @State showDatePicker: boolean = false;
  @State currentDateField: string = '';

  async aboutToAppear() {
    console.log('========== FormPage 加载 ==========');

    // 获取路由参数
    const params = router.getParams() as Record<string, Object>;

    if (params && params['task']) {
      this.currentTask = params['task'] as FollowUpTask;
    }

    if (params && params['table']) {
      this.currentTable = params['table'] as FormTable;
    }

    if (params && params['token']) {
      this.token = params['token'] as string;
    }

    if (params && params['username']) {
      this.currentUsername = params['username'] as string;
    }

    console.log('任务ID:', this.currentTask?.id);
    console.log('表单:', this.currentTable?.step_name);
    console.log('字段数:', this.currentTable?.fields?.length);

    if (!this.currentTask || !this.currentTable) {
      this.toastController.show('参数错误');
      setTimeout(() => {
        router.back();
      }, 500);
      return;
    }

    // 初始化表单数据（加载已有数据或设置默认值）
    this.initFormData();
  }

  /**
   * 初始化表单数据
   */
  initFormData() {
    if (!this.currentTable || !this.currentTable.fields) {
      return;
    }

    const data = new Map<string, string>();

    this.currentTable.fields.forEach((field: FormField) => {
      // 只初始化可编辑字段
      if (field.is_editable === '1') {
        // 设置默认值
        if (field.default_value && field.default_value !== '' && field.default_value !== 'NOW()') {
          data.set(field.field_name, field.default_value);
        } else {
          data.set(field.field_name, '');
        }
      }
    });

    this.formData = data;
    console.log('表单数据初始化，字段数:', this.formData.size);
  }

  /**
   * 获取字段值
   */
  getFieldValue(fieldName: string): string {
    return this.formData.get(fieldName) || '';
  }

  /**
   * 设置字段值
   */
  setFieldValue(fieldName: string, value: string) {
    this.formData.set(fieldName, value);
    console.log(`字段 ${fieldName} 更新:`, value);
  }

  /**
   * 表单验证
   */
  validateForm(): boolean {
    if (!this.currentTable || !this.currentTable.fields) {
      return false;
    }

    // 检查必填字段
    for (let field of this.currentTable.fields) {
      if (field.is_editable === '1' && field.required === 1) {
        const value = this.getFieldValue(field.field_name);
        if (!value || value.trim() === '') {
          this.toastController.show(`请填写 ${field.annotation}`);
          return false;
        }
      }
    }

    return true;
  }

  /**
   * 提交表单
   */
  async handleSubmit() {
    console.log('准备提交表单...');

    // 验证表单
    if (!this.validateForm()) {
      return;
    }

    try {
      this.submitting = true;

      // 检查网络
      let isOnline = await http.isOnline();
      if (!isOnline) {
        this.toastController.show('网络不可用，请稍后重试');
        this.submitting = false;
        return;
      }

      // 将 Map 转换为普通对象
      const dataObj: Record<string, string> = {};
      this.formData.forEach((value: string, key: string) => {
        dataObj[key] = value;
      });

      // 构造提交数据
      const submitData: SubmitFormData = {
        token: this.token,
        task_id: this.currentTask?.id,
        table_id: this.currentTable?.id,
        step_id: this.currentTable?.step_id,
        patient_no: this.currentTask?.patient_no,
        data: dataObj
      };

      console.log('提交数据:', JSON.stringify(submitData));

      // 调用提交接口
      // TODO: 替换为实际的提交接口
      // let response = await http.post('/mobile/submitForm.json', submitData);

      // 模拟提交
      await new Promise<void>(resolve => setTimeout(resolve, 1000));

      this.submitting = false;
      this.toastController.show('提交成功');

      // 延迟返回
      setTimeout(() => {
        router.back();
      }, 1000);

    } catch (e) {
      console.error('❌ 提交失败:', e);
      this.toastController.show('提交失败');
      this.submitting = false;
    }
  }

  /**
   * 获取可编辑字段列表（按 order_id 排序）
   */
  getEditableFields(): FormField[] {
    if (!this.currentTable || !this.currentTable.fields) {
      return [];
    }

    return this.currentTable.fields
      .filter((f: FormField) => f.is_editable === '1')
      .sort((a: FormField, b: FormField) => {
        const orderA = a.order_id ?? 0;
        const orderB = b.order_id ?? 0;
        return orderA - orderB;
      });
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

          Text(this.currentTable?.step_name || '表单填写')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

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

        // 表单内容区域
        if (!this.currentTable) {
          Column() {
            Text('表单数据错误')
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
              // 表单信息卡片
              Column() {
                Row() {
                  Text('患者编号')
                    .fontSize(14)
                    .fontColor('#999999')

                  Text(this.currentTask?.patient_no || '')
                    .fontSize(14)
                    .fontColor('#333333')
                    .margin({ left: 12 })

                  Blank()

                  Text(this.currentTable.multi_line === 1 ? '📋 多行表单' : '📄 单行表单')
                    .fontSize(12)
                    .fontColor('#666666')
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFF7F0')
              .borderRadius(8)
              .margin({ bottom: 16 })

              // 表单字段
              this.FormFields()
            }
            .width('100%')
            .padding(16)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .scrollBar(BarState.Auto)
        }

        // 底部提交按钮
        Row() {
          Button(this.submitting ? '提交中...' : '提交')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF6B00')
            .width('100%')
            .height(44)
            .borderRadius(8)
            .enabled(!this.submitting)
            .opacity(this.submitting ? 0.6 : 1.0)
            .onClick(() => {
              this.handleSubmit();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .border({
          width: { top: 0.5 },
          color: '#E5E5E5'
        })
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
   * 表单字段渲染
   */
  @Builder
  FormFields() {
    if (this.getEditableFields().length === 0) {
      Column() {
        Text('暂无可填写字段')
          .fontSize(14)
          .fontColor('#999999')
      }
      .width('100%')
      .height(200)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        ForEach(this.getEditableFields(), (field: FormField) => {
          Column() {
            this.FormFieldItem(field)
          }
          .width('100%')
          .margin({ bottom: 16 })
        })
      }
      .width('100%')
    }
  }

  /**
   * 单个表单字段
   */
  @Builder
  FormFieldItem(field: FormField) {
    Column() {
      // 字段标签
      Row() {
        if (field.required === 1) {
          Text('* ')
            .fontSize(14)
            .fontColor('#FF0000')
        }

        Text(field.annotation)
          .fontSize(14)
          .fontColor('#333333')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 根据 show_type 渲染不同类型的输入控件
      if (field.show_type === 'input' || field.show_type === 'decimal') {
        this.InputField(field)
      } else if (field.show_type === 'inputUnit') {
        this.InputUnitField(field)
      } else if (field.show_type === 'date') {
        this.DateField(field)
      } else if (field.show_type === 'select') {
        this.SelectField(field)
      } else if (field.show_type === 'textarea') {
        this.TextAreaField(field)
      } else if (field.show_type === 'file') {
        this.FileField(field)
      } else {
        // 默认使用 input
        this.InputField(field)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 普通输入框
   */
  @Builder
  InputField(field: FormField) {
    TextInput({
      placeholder: field.hint || `请输入${field.annotation}`,
      text: this.getFieldValue(field.field_name)
    })
      .width('100%')
      .height(44)
      .fontSize(14)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({
        width: 1,
        color: '#E5E5E5'
      })
      .onChange((value: string) => {
        this.setFieldValue(field.field_name, value);
      })
  }

  /**
   * 带单位的输入框
   */
  @Builder
  InputUnitField(field: FormField) {
    Row() {
      TextInput({
        placeholder: field.hint || `请输入${field.annotation}`,
        text: this.getFieldValue(field.field_name)
      })
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({
          width: 1,
          color: '#E5E5E5'
        })
        .onChange((value: string) => {
          this.setFieldValue(field.field_name, value);
        })

      if (field.field_desc && field.field_desc !== '') {
        Text(field.field_desc)
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 8 })
      }
    }
    .width('100%')
  }

  /**
   * 日期选择器
   */
  @Builder
  DateField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || '请选择日期')
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('📅')
        .fontSize(16)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({
      width: 1,
      color: '#E5E5E5'
    })
    .onClick(() => {
      // TODO: 打开日期选择器
      this.currentDateField = field.field_name;
      this.toastController.show('日期选择功能开发中');
    })
  }

  /**
   * 下拉选择框
   */
  @Builder
  SelectField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || `请选择${field.annotation}`)
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('▼')
        .fontSize(12)
        .fontColor('#999999')
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({
      width: 1,
      color: '#E5E5E5'
    })
    .onClick(() => {
      // TODO: 打开选择器
      this.toastController.show('下拉选择功能开发中');
    })
  }

  /**
   * 多行文本框
   */
  @Builder
  TextAreaField(field: FormField) {
    TextArea({
      placeholder: field.hint || `请输入${field.annotation}`,
      text: this.getFieldValue(field.field_name)
    })
      .width('100%')
      .height(100)
      .fontSize(14)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({
        width: 1,
        color: '#E5E5E5'
      })
      .onChange((value: string) => {
        this.setFieldValue(field.field_name, value);
      })
  }

  /**
   * 文件上传
   */
  @Builder
  FileField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || '点击选择文件')
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('📎')
        .fontSize(16)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({
      width: 1,
      color: '#E5E5E5'
    })
    .onClick(() => {
      // TODO: 打开文件选择器
      this.toastController.show('文件上传功能开发中');
    })
  }
}
