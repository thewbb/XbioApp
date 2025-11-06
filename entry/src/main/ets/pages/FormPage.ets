
/**
 * 表单填写页面
 *
 * 功能：
 * - 根据字段配置动态渲染表单
 * - 支持所有字段类型：
 *   - decimal（数值）
 *   - input（文本框）
 *   - inputUnit（带单位文本框）
 *   - text（大文本框）
 *   - select（下拉框）
 *   - checkbox（多选）
 *   - radio（单选）
 *   - date（日期）
 *   - datetime（日期时间）
 *   - time（时间）
 *   - description（描述）
 *   - line（分割线）
 *   - file（文件）
 *   - image（图像）
 *   - fileOcr（文件需识别）
 *   - imageDesc（描述图像）
 */
import router from '@ohos.router';
import { FollowUpTask, FormTable, FormField, FormRecord } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import http from '../utils/http';
import storage from '../utils/storage';

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
  @State saving: boolean = false;
  @State toastController: ToastController = new ToastController();

  // ✅ 选择器相关
  @State showSelectDialog: boolean = false;
  @State currentSelectField: FormField | null = null;
  @State selectOptions: string[] = [];
  @State selectedIndex: number = -1;

  // ✅ 多选相关
  @State showCheckboxDialog: boolean = false;
  @State currentCheckboxField: FormField | null = null;
  @State checkboxOptions: string[] = [];
  @State checkedItems: boolean[] = [];

  // ✅ 用于延迟返回
  private backTimer: number = -1;

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
      this.scheduleBack(500);
      return;
    }

    // 初始化表单数据
    await this.initFormData();
  }

  aboutToDisappear() {
    if (this.backTimer !== -1) {
      clearTimeout(this.backTimer);
      this.backTimer = -1;
    }
  }

  scheduleBack(delay: number) {
    this.backTimer = setTimeout(() => {
      try {
        router.back();
      } catch (e) {
        console.error('返回失败:', e);
      }
    }, delay);
  }

  /**
   * 初始化表单数据
   */
  async initFormData() {
    if (!this.currentTable || !this.currentTable.fields) {
      return;
    }

    const data = new Map<string, string>();

    // 尝试加载本地保存的数据
    const savedRecord = await storage.getFormRecord(
      this.currentUsername,
      this.currentTask!.id,
      this.currentTable.id
    );

    this.currentTable.fields.forEach((field: FormField) => {
      // 只初始化可编辑字段
      if (field.is_editable === '1') {
        // 优先使用本地保存的值
        if (savedRecord && savedRecord.data[field.field_name]) {
          data.set(field.field_name, savedRecord.data[field.field_name]);
        }
        // 其次使用默认值
        else if (field.default_value && field.default_value !== '' && field.default_value !== 'NOW()') {
          data.set(field.field_name, field.default_value);
        }
        // 如果是日期字段且默认值是 NOW()，设置当前日期
        else if (field.show_type === 'date' && field.default_value === 'NOW()') {
          const today = this.formatDate(new Date());
          data.set(field.field_name, today);
        }
        // 如果是日期时间字段且默认值是 NOW()
        else if (field.show_type === 'datetime' && field.default_value === 'NOW()') {
          const now = this.formatDateTime(new Date());
          data.set(field.field_name, now);
        }
        // 最后设置为空
        else {
          data.set(field.field_name, '');
        }
      }
    });

    this.formData = data;

    if (savedRecord) {
      console.log('✅ 已加载本地保存的数据');
      this.toastController.show('已加载草稿');
    } else {
      console.log('✅ 表单数据初始化，字段数:', this.formData.size);
    }
  }

  getFieldValue(fieldName: string): string {
    return this.formData.get(fieldName) || '';
  }

  setFieldValue(fieldName: string, value: string) {
    this.formData.set(fieldName, value);
    console.log(`字段 ${fieldName} 更新:`, value);
  }

  /**
   * ✅ 格式化日期 (YYYY-MM-DD)
   */
  formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * ✅ 格式化日期时间 (YYYY-MM-DD HH:mm:ss)
   */
  formatDateTime(date: Date): string {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

  /**
   * ✅ 格式化时间 (HH:mm:ss)
   */
  formatTime(date: Date): string {
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }

  /**
   * ✅ 解析日期字符串
   */
  parseDate(dateStr: string): Date {
    if (!dateStr) {
      return new Date();
    }

    const parts = dateStr.split(/[-\/\.\s:]/);
    if (parts.length >= 3) {
      const year = parseInt(parts[0]);
      const month = parseInt(parts[1]) - 1;
      const day = parseInt(parts[2]);
      return new Date(year, month, day);
    }

    return new Date();
  }

  /**
   * ✅ 解析选项列表（从 select_value 中解析，以逗号分隔）
   */
  parseOptions(selectValue: string | undefined): string[] {
    if (!selectValue || selectValue === '') {
      return [];
    }
    return selectValue.split(',').map(v => v.trim()).filter(v => v !== '');
  }

  /**
   * ✅ 打开日期选择器
   */
  openDatePicker(field: FormField) {
    console.log('打开日期选择器:', field.field_name);

    const currentValue = this.getFieldValue(field.field_name);
    const currentDate = currentValue ? this.parseDate(currentValue) : new Date();

    DatePickerDialog.show({
      start: new Date('1900-01-01'),
      end: new Date('2100-12-31'),
      selected: currentDate,
      lunar: false,
      onAccept: (value: DatePickerResult) => {
        const year = value.year ?? new Date().getFullYear();
        const month = value.month ?? new Date().getMonth();
        const day = value.day ?? new Date().getDate();

        const selectedDate = new Date(year, month, day);
        const dateStr = this.formatDate(selectedDate);
        this.setFieldValue(field.field_name, dateStr);

        console.log('日期已更新:', dateStr);
      }
    });
  }

  /**
   * ✅ 打开日期时间选择器
   */
  openDateTimePicker(field: FormField) {
    console.log('打开日期时间选择器:', field.field_name);
    // TODO: HarmonyOS 没有原生的 DateTimePicker，可以分步选择日期和时间
    this.toastController.show('日期时间选择功能开发中');
  }

  /**
   * ✅ 打开时间选择器
   */
  openTimePicker(field: FormField) {
    console.log('打开时间选择器:', field.field_name);

    const currentValue = this.getFieldValue(field.field_name);
    let currentDate = new Date();

    if (currentValue) {
      const parts = currentValue.split(':');
      if (parts.length >= 2) {
        currentDate.setHours(parseInt(parts[0]));
        currentDate.setMinutes(parseInt(parts[1]));
        if (parts.length >= 3) {
          currentDate.setSeconds(parseInt(parts[2]));
        }
      }
    }

    TimePickerDialog.show({
      selected: currentDate,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const hour = value.hour ?? 0;
        const minute = value.minute ?? 0;
        const timeStr = `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}:00`;
        this.setFieldValue(field.field_name, timeStr);
        console.log('时间已更新:', timeStr);
      }
    });
  }

  /**
   * ✅ 打开下拉选择框
   */
  openSelectDialog(field: FormField) {
    console.log('打开下拉选择:', field.field_name);

    this.currentSelectField = field;
    this.selectOptions = this.parseOptions(field.select_value);

    if (this.selectOptions.length === 0) {
      this.toastController.show('暂无选项');
      return;
    }

    // 查找当前选中的索引
    const currentValue = this.getFieldValue(field.field_name);
    this.selectedIndex = this.selectOptions.findIndex(opt => opt === currentValue);

    this.showSelectDialog = true;
  }

  /**
   * ✅ 选择下拉选项
   */
  selectOption(index: number) {
    if (this.currentSelectField && index >= 0 && index < this.selectOptions.length) {
      const value = this.selectOptions[index];
      this.setFieldValue(this.currentSelectField.field_name, value);
      console.log('选择:', value);
    }
    this.showSelectDialog = false;
    this.currentSelectField = null;
  }

  /**
   * ✅ 打开单选框
   */
  openRadioDialog(field: FormField) {
    // 单选和下拉框逻辑相同
    this.openSelectDialog(field);
  }

  /**
   * ✅ 打开多选框
   */
  openCheckboxDialog(field: FormField) {
    console.log('打开多选:', field.field_name);

    this.currentCheckboxField = field;
    this.checkboxOptions = this.parseOptions(field.select_value);

    if (this.checkboxOptions.length === 0) {
      this.toastController.show('暂无选项');
      return;
    }

    // 解析当前选中的值（多个值用逗号分隔）
    const currentValue = this.getFieldValue(field.field_name);
    const selectedValues = currentValue ? currentValue.split(',').map(v => v.trim()) : [];

    // 初始化选中状态
    this.checkedItems = this.checkboxOptions.map(opt => selectedValues.includes(opt));

    this.showCheckboxDialog = true;
  }

  /**
   * ✅ 切换多选项
   */
  toggleCheckbox(index: number) {
    if (index >= 0 && index < this.checkedItems.length) {
      this.checkedItems[index] = !this.checkedItems[index];
    }
  }

  /**
   * ✅ 确认多选
   */
  confirmCheckbox() {
    if (this.currentCheckboxField) {
      // 获取所有选中的值
      const selectedValues = this.checkboxOptions.filter((opt, index) => this.checkedItems[index]);
      const value = selectedValues.join(',');
      this.setFieldValue(this.currentCheckboxField.field_name, value);
      console.log('多选值:', value);
    }
    this.showCheckboxDialog = false;
    this.currentCheckboxField = null;
  }

  /**
   * 表单验证
   */
  validateForm(): boolean {
    if (!this.currentTable || !this.currentTable.fields) {
      return false;
    }

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
   * 保存草稿
   */
  async handleSaveDraft() {
    console.log('保存草稿到本地...');

    try {
      this.saving = true;

      const dataObj: Record<string, string> = {};
      this.formData.forEach((value: string, key: string) => {
        dataObj[key] = value;
      });

      const record: FormRecord = {
        table_id: this.currentTable!.id,
        step_id: this.currentTable!.step_id,
        data: dataObj,
        filled_time: new Date().toLocaleString('zh-CN'),
        is_uploaded: false
      };

      const success = await storage.saveFormRecord(
        this.currentUsername,
        this.currentTask!.id,
        record
      );

      this.saving = false;

      if (success) {
        this.toastController.show('✅ 草稿已保存');
      } else {
        this.toastController.show('❌ 保存失败');
      }

    } catch (e) {
      console.error('❌ 保存草稿失败:', e);
      this.toastController.show('保存失败');
      this.saving = false;
    }
  }

  /**
   * 提交表单
   */
  async handleSubmit() {
    console.log('准备提交表单...');

    if (!this.validateForm()) {
      return;
    }

    try {
      this.submitting = true;

      const dataObj: Record<string, string> = {};
      this.formData.forEach((value: string, key: string) => {
        dataObj[key] = value;
      });

      const record: FormRecord = {
        table_id: this.currentTable!.id,
        step_id: this.currentTable!.step_id,
        data: dataObj,
        filled_time: new Date().toLocaleString('zh-CN'),
        is_uploaded: false
      };

      const saveSuccess = await storage.saveFormRecord(
        this.currentUsername,
        this.currentTask!.id,
        record
      );

      if (!saveSuccess) {
        throw new Error('本地保存失败');
      }

      console.log('✅ 本地保存成功');

      let isOnline = await http.isOnline();

      if (isOnline) {
        try {
          const submitData: SubmitFormData = {
            token: this.token,
            task_id: this.currentTask?.id,
            table_id: this.currentTable?.id,
            step_id: this.currentTable?.step_id,
            patient_no: this.currentTask?.patient_no,
            data: dataObj
          };

          console.log('提交数据:', JSON.stringify(submitData));

          // TODO: 调用实际的提交接口
          await new Promise<void>(resolve => setTimeout(resolve, 1000));

          await storage.markRecordAsUploaded(
            this.currentUsername,
            this.currentTask!.id,
            this.currentTable!.id
          );

          console.log('✅ 上传成功');
          this.toastController.show('✅ 提交成功');

        } catch (uploadError) {
          console.error('❌ 上传失败，但本地已保存:', uploadError);
          this.toastController.show('已保存到本地，稍后可在记录页面上传');
        }
      } else {
        console.log('⚠️ 网络不可用，数据已保存到本地');
        this.toastController.show('已保存到本地，稍后可在记录页面上传');
      }

      this.submitting = false;
      this.scheduleBack(1500);

    } catch (e) {
      console.error('❌ 提交失败:', e);
      this.toastController.show('提交失败');
      this.submitting = false;
    }
  }

  /**
   * 获取可编辑字段列表
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
              try {
                router.back();
              } catch (e) {
                console.error('返回失败:', e);
              }
            })

          Text(this.currentTable?.step_name || '表单填写')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

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

              // 底部留白
              Column()
                .width('100%')
                .height(20)
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .width('100%')
          .backgroundColor('#F5F5F5')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }

        // 底部按钮区域
        Row() {
          Button(this.saving ? '保存中...' : '保存草稿')
            .fontSize(16)
            .fontColor('#FF6B00')
            .backgroundColor('#FFFFFF')
            .border({
              width: 1,
              color: '#FF6B00'
            })
            .width('48%')
            .height(44)
            .borderRadius(8)
            .enabled(!this.saving && !this.submitting)
            .opacity((this.saving || this.submitting) ? 0.6 : 1.0)
            .onClick(() => {
              this.handleSaveDraft();
            })

          Button(this.submitting ? '提交中...' : '提交')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF6B00')
            .width('48%')
            .height(44)
            .borderRadius(8)
            .enabled(!this.submitting && !this.saving)
            .opacity((this.submitting || this.saving) ? 0.6 : 1.0)
            .onClick(() => {
              this.handleSubmit();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .justifyContent(FlexAlign.SpaceBetween)
        .border({
          width: { top: 0.5 },
          color: '#E5E5E5'
        })
      }
      .width('100%')
      .height('100%')

      // ✅ 下拉/单选选择对话框
      if (this.showSelectDialog && this.currentSelectField) {
        Column() {
          Column() {
            Text(this.currentSelectField.annotation)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 16 })

            List({ space: 0 }) {
              ForEach(this.selectOptions, (option: string, index: number) => {
                ListItem() {
                  Row() {
                    Text(option)
                      .fontSize(16)
                      .fontColor('#333333')
                      .layoutWeight(1)

                    if (index === this.selectedIndex) {
                      Text('✓')
                        .fontSize(18)
                        .fontColor('#FF6B00')
                    }
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 16, right: 16 })
                  .backgroundColor(index === this.selectedIndex ? '#FFF7F0' : '#FFFFFF')
                  .onClick(() => {
                    this.selectOption(index);
                  })
                }
              }, (option: string, index: number) => `${this.currentSelectField?.field_name}_${index}`)
            }
            .width('100%')
            .height('60%')
            .divider({
              strokeWidth: 0.5,
              color: '#E5E5E5'
            })

            Button('取消')
              .fontSize(16)
              .fontColor('#666666')
              .backgroundColor('#F5F5F5')
              .width('100%')
              .height(44)
              .margin({ top: 16 })
              .borderRadius(8)
              .onClick(() => {
                this.showSelectDialog = false;
                this.currentSelectField = null;
              })
          }
          .width('85%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showSelectDialog = false;
          this.currentSelectField = null;
        })
      }

      // ✅ 多选对话框
      if (this.showCheckboxDialog && this.currentCheckboxField) {
        Column() {
          Column() {
            Text(this.currentCheckboxField.annotation)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 16 })

            List({ space: 0 }) {
              ForEach(this.checkboxOptions, (option: string, index: number) => {
                ListItem() {
                  Row() {
                    Text(option)
                      .fontSize(16)
                      .fontColor('#333333')
                      .layoutWeight(1)

                    Checkbox()
                      .select(this.checkedItems[index])
                      .selectedColor('#FF6B00')
                      .onChange((value: boolean) => {
                        this.toggleCheckbox(index);
                      })
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 16, right: 16 })
                }
              }, (option: string, index: number) => `${this.currentCheckboxField?.field_name}_${index}`)
            }
            .width('100%')
            .height('60%')
            .divider({
              strokeWidth: 0.5,
              color: '#E5E5E5'
            })

            Row() {
              Button('取消')
                .fontSize(16)
                .fontColor('#666666')
                .backgroundColor('#F5F5F5')
                .width('48%')
                .height(44)
                .borderRadius(8)
                .onClick(() => {
                  this.showCheckboxDialog = false;
                  this.currentCheckboxField = null;
                })

              Button('确定')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .backgroundColor('#FF6B00')
                .width('48%')
                .height(44)
                .borderRadius(8)
                .onClick(() => {
                  this.confirmCheckbox();
                })
            }
            .width('100%')
            .margin({ top: 16 })
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('85%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .justifyContent(FlexAlign.Center)
      }

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
        ForEach(this.getEditableFields(), (field: FormField, index: number) => {
          Column() {
            this.FormFieldItem(field)
          }
          .width('100%')
          .margin({ bottom: 16 })
        }, (field: FormField) => field.field_name)
      }
      .width('100%')
    }
  }

  /**
   * ✅ 单个表单字段（根据 show_type 渲染）
   */
  @Builder
  FormFieldItem(field: FormField) {
    // ✅ 描述类型：只显示文本，不需要输入
    if (field.show_type === 'description') {
      Column() {
        Text(field.annotation)
          .fontSize(14)
          .fontColor('#666666')
          .lineHeight(22)
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F0F9FF')
      .borderRadius(8)
      .alignItems(HorizontalAlign.Start)

    }

    // ✅ 分割线：只显示分割线
    if (field.show_type === 'line') {
      Divider()
        .width('100%')
        .height(1)
        .color('#E5E5E5')
        .margin({ top: 8, bottom: 8 })

    }

    // ✅ 其他可输入字段
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
      if (field.show_type === 'input') {
        this.InputField(field)
      } else if (field.show_type === 'decimal') {
        this.DecimalField(field)
      } else if (field.show_type === 'inputUnit') {
        this.InputUnitField(field)
      } else if (field.show_type === 'text') {
        this.TextAreaField(field)
      } else if (field.show_type === 'date') {
        this.DateField(field)
      } else if (field.show_type === 'datetime') {
        this.DateTimeField(field)
      } else if (field.show_type === 'time') {
        this.TimeField(field)
      } else if (field.show_type === 'select') {
        this.SelectField(field)
      } else if (field.show_type === 'radio') {
        this.RadioField(field)
      } else if (field.show_type === 'checkbox') {
        this.CheckboxField(field)
      } else if (field.show_type === 'file' || field.show_type === 'fileOcr') {
        this.FileField(field)
      } else if (field.show_type === 'image' || field.show_type === 'imageDesc') {
        this.ImageField(field)
      } else {
        // 默认使用文本框
        this.InputField(field)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 普通文本框
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
      .border({ width: 1, color: '#E5E5E5' })
      .onChange((value: string) => {
        this.setFieldValue(field.field_name, value);
      })
  }

  /**
   * ✅ 数值输入框
   */
  @Builder
  DecimalField(field: FormField) {
    TextInput({
      placeholder: field.hint || `请输入${field.annotation}`,
      text: this.getFieldValue(field.field_name)
    })
      .width('100%')
      .height(44)
      .fontSize(14)
      .type(InputType.Number)  // ✅ 数字键盘
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#E5E5E5' })
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
        .border({ width: 1, color: '#E5E5E5' })
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
   * ✅ 大文本框
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
      .border({ width: 1, color: '#E5E5E5' })
      .onChange((value: string) => {
        this.setFieldValue(field.field_name, value);
      })
  }

  /**
   * ✅ 日期选择
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
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.openDatePicker(field);
    })
  }

  /**
   * ✅ 日期时间选择
   */
  @Builder
  DateTimeField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || '请选择日期时间')
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('📅🕒')
        .fontSize(16)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.openDateTimePicker(field);
    })
  }

  /**
   * ✅ 时间选择
   */
  @Builder
  TimeField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || '请选择时间')
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('🕒')
        .fontSize(16)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.openTimePicker(field);
    })
  }

  /**
   * ✅ 下拉选择框
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
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.openSelectDialog(field);
    })
  }

  /**
   * ✅ 单选框
   */
  @Builder
  RadioField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || `请选择${field.annotation}`)
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('◉')
        .fontSize(12)
        .fontColor('#999999')
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.openRadioDialog(field);
    })
  }

  /**
   * ✅ 多选框
   */
  @Builder
  CheckboxField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || `请选择${field.annotation}`)
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text('☑')
        .fontSize(12)
        .fontColor('#999999')
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.openCheckboxDialog(field);
    })
  }

  /**
   * ✅ 文件上传
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
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.toastController.show('文件上传功能开发中');
    })
  }

  /**
   * ✅ 图片上传
   */
  @Builder
  ImageField(field: FormField) {
    Row() {
      Text(this.getFieldValue(field.field_name) || '点击选择图片')
        .fontSize(14)
        .fontColor(this.getFieldValue(field.field_name) ? '#333333' : '#CCCCCC')
        .layoutWeight(1)

      Text('🖼️')
        .fontSize(16)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E5E5E5' })
    .onClick(() => {
      this.toastController.show('图片上传功能开发中');
    })
  }
}
