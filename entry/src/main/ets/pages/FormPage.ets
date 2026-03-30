/**
 * 表单填写页面
 *
 * 修复：
 * 1. 提交后无法返回上一页的问题
 * 2. 公式计算逻辑（支持选项分值计算 A=3）
 * 3. 使用安全的表达式计算器（不使用 eval/new Function）
 * 4. ✅ 新增：支持 client_visible 字段控制（0=不显示但参与计算和保存）
 * 5. ✅ 新增：select/radio/checkbox 存储 label（如"完全不会"），= 后的数字仅用于公式计算
 */
import router from '@ohos.router';
import { FollowUpTask, FormTable, FormField, FormRecord } from '../types';
import { CustomToast, ToastController } from '../components/CustomToast';
import storage from '../utils/storage';

interface OptionItem {
  label: string;
  value: string;
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

  @State readOnly: boolean = false;

  private backTimer: number = -1;
  private uiContext: UIContext | null = null;

  async aboutToAppear() {
    console.log('========== FormPage 加载 ==========');
    this.uiContext = this.getUIContext();
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

    if (params['readOnly'] !== undefined) {
      this.readOnly = params['readOnly'] as boolean;
    }

    console.log('任务ID:', this.currentTask?.id);
    console.log('表单:', this.currentTable?.step_name);
    console.log('字段数:', this.currentTable?.fields?.length);

    if (!this.currentTask || !this.currentTable) {
      this.toastController.show('参数错误');
      this.scheduleBack(500);
      return;
    }

    await this.initFormData();
  }

  aboutToDisappear() {
    if (this.backTimer !== -1) {
      clearTimeout(this.backTimer);
      this.backTimer = -1;
    }
  }

  /**
   * ✅ 统一返回逻辑
   */
  scheduleBack(delay: number) {
    if (this.backTimer !== -1) {
      clearTimeout(this.backTimer);
    }

    this.backTimer = setTimeout(() => {
      try {
        console.log('🔙 执行返回上一页');
        router.back();
      } catch (e) {
        console.error('返回失败:', e);
      }
    }, delay);
  }

  /**
   * ✅ 初始化表单数据（包括隐藏字段）
   */
  async initFormData() {
    if (!this.currentTable || !this.currentTable.fields) {
      return;
    }

    const data = new Map<string, string>();

    const savedRecord = await storage.getFormRecord(
      this.currentUsername,
      this.currentTask!.id,
      this.currentTable.id
    );

    this.currentTable.fields.forEach((field: FormField) => {
      if (field.is_editable === '1') {
        if (savedRecord && savedRecord.data[field.field_name]) {
          data.set(field.field_name, savedRecord.data[field.field_name]);
        } else if (field.default_value && field.default_value !== '' && field.default_value !== 'NOW()') {
          data.set(field.field_name, field.default_value);
        } else if (field.show_type === 'date' && field.default_value === 'NOW()') {
          const today = this.formatDate(new Date());
          data.set(field.field_name, today);
        } else if (field.show_type === 'datetime' && field.default_value === 'NOW()') {
          const now = this.formatDateTime(new Date());
          data.set(field.field_name, now);
        } else {
          data.set(field.field_name, '');
        }
      }
    });

    this.formData = data;
    this.calculateAllFormulas();

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
    this.calculateAllFormulas();
  }

  /**
   * ✅ 解析选项列表
   * "完全不会=0,≤1周=1" → label="完全不会", value="0"（value 仅用于公式计算）
   * "是,否"             → label="是",     value="是"
   */
  parseOptions(selectValue: string | undefined): OptionItem[] {
    if (!selectValue || selectValue === '') {
      return [];
    }

    const items: OptionItem[] = [];
    const values = selectValue.split(',');

    for (let i = 0; i < values.length; i++) {
      const item = values[i].trim();
      if (item === '') {
        continue;
      }

      if (item.includes('=')) {
        const parts = item.split('=');
        items.push({
          label: parts[0].trim(),  // ✅ 显示文字，也是存储值
          value: parts[1].trim()   // ✅ 仅用于公式计算
        });
      } else {
        items.push({
          label: item,
          value: item
        });
      }
    }

    return items;
  }

  /**
   * ✅ 获取字段的选项列表（供 Builder 使用）
   */
  getFieldOptions(field: FormField): OptionItem[] {
    return this.parseOptions(field.select_value);
  }

  /**
   * ✅ 检查选项是否被选中（多选）
   * 注意：存储和比较都用 label
   */
  isOptionChecked(fieldName: string, optionLabel: string): boolean {
    const currentValue = this.getFieldValue(fieldName);
    if (!currentValue) {
      return false;
    }
    const selectedValues = currentValue.split(',').map(v => v.trim());
    return selectedValues.includes(optionLabel);
  }

  /**
   * ✅ 切换多选选项
   * 注意：存储和比较都用 label
   */
  toggleCheckboxOption(fieldName: string, optionLabel: string) {
    const currentValue = this.getFieldValue(fieldName);
    let selectedValues = currentValue
      ? currentValue.split(',').map(v => v.trim()).filter(v => v !== '')
      : [];

    if (selectedValues.includes(optionLabel)) {
      selectedValues = selectedValues.filter(v => v !== optionLabel);
    } else {
      selectedValues.push(optionLabel);
    }

    this.setFieldValue(fieldName, selectedValues.join(','));
  }

  /**
   * ✅ 计算所有公式字段
   */
  calculateAllFormulas() {
    if (!this.currentTable || !this.currentTable.fields) {
      return;
    }

    const formulaFields = this.currentTable.fields.filter(f =>
    f.formula && f.formula.trim() !== ''
    );

    if (formulaFields.length === 0) {
      return;
    }

    console.log('✅ 开始计算公式字段，共', formulaFields.length, '个');

    formulaFields.forEach(field => {
      try {
        const result = this.calculateFormula(field.formula!);
        const currentValue = this.getFieldValue(field.field_name);
        const newValue = result.toString();

        if (currentValue !== newValue) {
          this.formData.set(field.field_name, newValue);
          console.log(`🧮 公式计算: ${field.field_name} = ${result} (公式: ${field.formula})`);
        }
      } catch (err) {
        const e = err as Error;
        console.error(`计算公式失败: ${field.field_name}`, e.message);
        this.formData.set(field.field_name, '0');
      }
    });
  }

  /**
   * ✅ 公式计算逻辑
   * - 存储的是 label（如"完全不会"）
   * - 公式计算时通过 label 反查 value（如"0"）参与运算
   */
  calculateFormula(formula: string): number {
    let expression = formula;

    if (!this.currentTable || !this.currentTable.fields) {
      return 0;
    }

    this.currentTable.fields.forEach(field => {
      const fieldName = field.field_name;

      const regex = new RegExp(`\\b${fieldName}\\b`, 'g');
      if (!regex.test(expression)) {
        return;
      }

      const rawValue = this.getFieldValue(fieldName);
      let numValue = 0;

      console.log(`  处理字段 ${fieldName}, 原始值: "${rawValue}"`);

      if (!rawValue || rawValue.trim() === '') {
        numValue = 0;
      } else if (!isNaN(Number(rawValue))) {
        // 纯数字直接使用
        numValue = parseFloat(rawValue);
        console.log(`    -> 数值: ${numValue}`);
      } else {
        // 字符串：用 label 反查 value 参与计算
        const options = this.parseOptions(field.select_value);

        // ✅ 优先按 label 匹配（因为存的是 label）
        const matchedByLabel = options.find(opt => opt.label === rawValue);
        if (matchedByLabel && !isNaN(Number(matchedByLabel.value))) {
          numValue = parseFloat(matchedByLabel.value);
          console.log(`    -> 匹配到 label: "${rawValue}", 计算用 value: ${numValue}`);
        } else {
          // 兜底：按 value 匹配
          const matchedByValue = options.find(opt => opt.value === rawValue);
          if (matchedByValue && !isNaN(Number(matchedByValue.value))) {
            numValue = parseFloat(matchedByValue.value);
            console.log(`    -> 匹配到 value: ${numValue}`);
          } else {
            numValue = 0;
            console.log(`    -> 未匹配到有效选项，使用 0`);
          }
        }
      }

      expression = expression.replace(regex, numValue.toString());
    });

    console.log(`  最终表达式: ${expression}`);

    try {
      const result = this.evaluateExpression(expression);
      console.log(`  计算结果: ${result}`);
      return Math.round(result * 100) / 100;
    } catch (err) {
      console.error('  ❌ 计算错误:', err);
      return 0;
    }
  }

  /**
   * ✅ 安全的数学表达式计算器（支持 +、-、*、/、()）
   */
  evaluateExpression(expr: string): number {
    expr = expr.replace(/\s+/g, '');

    const tokens: string[] = [];
    let numBuffer = '';

    for (let i = 0; i < expr.length; i++) {
      const char = expr[i];

      if ((char >= '0' && char <= '9') || char === '.') {
        numBuffer += char;
      } else if (char === '+' || char === '-' || char === '*' || char === '/' || char === '(' || char === ')') {
        if (numBuffer) {
          tokens.push(numBuffer);
          numBuffer = '';
        }
        tokens.push(char);
      } else {
        throw new Error(`非法字符: ${char}`);
      }
    }

    if (numBuffer) {
      tokens.push(numBuffer);
    }

    console.log('  Tokens:', tokens);

    const rpn = this.toRPN(tokens);
    console.log('  RPN:', rpn);

    return this.calculateRPN(rpn);
  }

  /**
   * 中缀表达式转逆波兰表达式（Shunting Yard 算法）
   */
  toRPN(tokens: string[]): string[] {
    const output: string[] = [];
    const operators: string[] = [];

    const precedence: Record<string, number> = {
      '+': 1,
      '-': 1,
      '*': 2,
      '/': 2
    };

    for (let token of tokens) {
      if (!isNaN(Number(token))) {
        output.push(token);
      } else if (token === '(') {
        operators.push(token);
      } else if (token === ')') {
        while (operators.length > 0 && operators[operators.length - 1] !== '(') {
          output.push(operators.pop()!);
        }
        operators.pop();
      } else if (precedence[token] !== undefined) {
        while (
          operators.length > 0 &&
            operators[operators.length - 1] !== '(' &&
            precedence[operators[operators.length - 1]] >= precedence[token]
        ) {
          output.push(operators.pop()!);
        }
        operators.push(token);
      }
    }

    while (operators.length > 0) {
      output.push(operators.pop()!);
    }

    return output;
  }

  /**
   * 计算逆波兰表达式
   */
  calculateRPN(rpn: string[]): number {
    const stack: number[] = [];

    for (let token of rpn) {
      if (!isNaN(Number(token))) {
        stack.push(parseFloat(token));
      } else {
        const b = stack.pop()!;
        const a = stack.pop()!;

        switch (token) {
          case '+':
            stack.push(a + b);
            break;
          case '-':
            stack.push(a - b);
            break;
          case '*':
            stack.push(a * b);
            break;
          case '/':
            if (b === 0) {
              throw new Error('除数不能为 0');
            }
            stack.push(a / b);
            break;
          default:
            throw new Error(`未知运算符: ${token}`);
        }
      }
    }

    if (stack.length !== 1) {
      throw new Error('表达式错误');
    }

    return stack[0];
  }

  formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  formatDateTime(date: Date): string {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

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

  openDateTimePicker(field: FormField) {
    console.log('打开日期时间选择器:', field.field_name);
    this.toastController.show('日期时间选择功能开发中');
  }

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
   * ✅ 验证表单（隐藏字段不参与必填验证）
   */
  validateForm(): boolean {
    if (!this.currentTable || !this.currentTable.fields) {
      return false;
    }

    for (let field of this.currentTable.fields) {
      if (
        field.client_visible !== 0 &&
        this.isFieldVisible(field) &&
          field.is_editable === '1' &&
          field.required === 1
      ) {
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
   * ✅ 判断字段是否应该显示
   * control_by 格式：field1.1,field1.3（.后面是选项序号，从1开始）
   * 比较时用 label（因为存储的是 label）
   */
  isFieldVisible(field: FormField): boolean {
    if (field.client_visible === 0) {
      console.log(`字段 ${field.field_name} 被隐藏 (client_visible=0)`);
      return false;
    }

    if (!field.control_by || field.control_by.trim() === '') {
      return true;
    }

    const controls = field.control_by.split(',').map(v => v.trim());

    for (let i = 0; i < controls.length; i++) {
      const control = controls[i];
      if (control === '') {
        continue;
      }

      const parts = control.split('.');
      if (parts.length !== 2) {
        continue;
      }

      const controlFieldName = parts[0];
      const controlOptionIndex = parseInt(parts[1]);

      const controlFieldValue = this.getFieldValue(controlFieldName);
      if (!controlFieldValue) {
        continue;
      }

      const controlField = this.currentTable?.fields?.find(f => f.field_name === controlFieldName);
      if (!controlField) {
        continue;
      }

      const options = this.parseOptions(controlField.select_value);
      if (controlOptionIndex < 1 || controlOptionIndex > options.length) {
        continue;
      }

      // ✅ 用 label 比较（因为存储的是 label）
      const targetLabel = options[controlOptionIndex - 1].label;

      const selectedLabels = controlFieldValue.split(',').map(v => v.trim());
      if (selectedLabels.includes(targetLabel)) {
        return true;
      }
    }

    return false;
  }

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

    } catch (err) {
      const e = err as Error;
      console.error('❌ 保存草稿失败:', e.message);
      this.toastController.show('保存失败');
      this.saving = false;
    }
  }

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

      console.log('📦 提交的表单数据:', JSON.stringify(dataObj));

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

      this.submitting = false;

      if (saveSuccess) {
        console.log('✅ 本地保存成功');
        this.toastController.show('✅ 保存成功，可在记录页面上传');

        if (this.uiContext) {
          this.uiContext.getRouter().back();
        }
      } else {
        throw new Error('本地保存失败');
      }

    } catch (err) {
      const e = err as Error;
      console.error('❌ 提交失败:', e.message);
      this.toastController.show('提交失败');
      this.submitting = false;
    }
  }

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

          Text('')
            .width(60)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .justifyContent(FlexAlign.SpaceBetween)
        .border({ width: { bottom: 0.5 }, color: '#E5E5E5' })

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
                  Text('患者姓名')
                    .fontSize(14)
                    .fontColor('#999999')

                  Text(this.currentTask?.name || '')
                    .fontSize(14)
                    .fontColor('#333333')
                    .margin({ left: 12, right: 24 })

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
            .border({ width: 1, color: '#FF6B00' })
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
        .border({ width: { top: 0.5 }, color: '#E5E5E5' })
      }
      .width('100%')
      .height('100%')

      CustomToast({ controller: this.toastController })
    }
    .width('100%')
    .height('100%')
  }

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

  @Builder
  FormFieldItem(field: FormField) {
    if (field.client_visible === 0) {
      Column().width(0).height(0)
    } else if (!this.isFieldVisible(field)) {
      Column().width(0).height(0)
    } else if (field.show_type === 'description') {
      Text(field.annotation)
        .fontSize(14)
        .fontColor('#666666')
        .lineHeight(22)
        .width('100%')
    } else if (field.show_type === 'line') {
      Divider()
        .width('100%')
        .height(1)
        .color('#E5E5E5')
        .margin({ top: 8, bottom: 8 })
    } else {
      Column() {
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

          if (field.formula && field.formula.trim() !== '') {
            Text(' 🧮')
              .fontSize(12)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .margin({ bottom: 8 })

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
          this.SelectFieldInline(field)
        } else if (field.show_type === 'radio') {
          this.RadioFieldInline(field)
        } else if (field.show_type === 'checkbox') {
          this.CheckboxFieldInline(field)
        } else if (field.show_type === 'file' || field.show_type === 'fileOcr') {
          this.FileField(field)
        } else if (field.show_type === 'image' || field.show_type === 'imageDesc') {
          this.ImageField(field)
        } else {
          this.InputField(field)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  InputField(field: FormField) {
    if (field.formula && field.formula.trim() !== '') {
      Row() {
        Text(this.getFieldValue(field.field_name) || '0')
          .fontSize(14)
          .fontColor('#333333')
          .layoutWeight(1)

        Text('(自动计算)')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .border({ width: 1, color: '#E5E5E5' })
    } else {
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
  }

  @Builder
  DecimalField(field: FormField) {
    if (field.formula && field.formula.trim() !== '') {
      Row() {
        Text(this.getFieldValue(field.field_name) || '0')
          .fontSize(14)
          .fontColor('#333333')
          .layoutWeight(1)

        Text('(自动计算)')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .border({ width: 1, color: '#E5E5E5' })
    } else {
      TextInput({
        placeholder: field.hint || `请输入${field.annotation}`,
        text: this.getFieldValue(field.field_name)
      })
        .width('100%')
        .height(44)
        .fontSize(14)
        .type(InputType.Number)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#E5E5E5' })
        .onChange((value: string) => {
          this.setFieldValue(field.field_name, value);
        })
    }
  }

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

  @Builder
  SelectFieldInline(field: FormField) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.getFieldOptions(field), (option: OptionItem, index: number) => {
        Row() {
          Row() {
            if (this.getFieldValue(field.field_name) === option.label) {
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor('#FF6B00')
            }
          }
          .width(18)
          .height(18)
          .borderRadius(9)
          .border({
            width: 2,
            color: this.getFieldValue(field.field_name) === option.label ? '#FF6B00' : '#CCCCCC'
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

          Text(option.label)
            .fontSize(14)
            .fontColor(this.getFieldValue(field.field_name) === option.label ? '#FF6B00' : '#333333')
            .fontWeight(this.getFieldValue(field.field_name) === option.label ? FontWeight.Medium : FontWeight.Normal)
            .margin({ left: 8 })
        }
        .height(36)
        .padding({ left: 4, right: 12 })
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          // ✅ 存 label（如"完全不会"），不存 value（如"0"）
          this.setFieldValue(field.field_name, option.label);
          console.log(`[Select] ${field.field_name} = ${option.label}`);
        })
      }, (option: OptionItem, index: number) => `${field.field_name}_select_${index}`)
    }
    .width('100%')
  }

  @Builder
  RadioFieldInline(field: FormField) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.getFieldOptions(field), (option: OptionItem, index: number) => {
        Row() {
          Row() {
            if (this.getFieldValue(field.field_name) === option.label) {
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor('#FF6B00')
            }
          }
          .width(18)
          .height(18)
          .borderRadius(9)
          .border({
            width: 2,
            color: this.getFieldValue(field.field_name) === option.label ? '#FF6B00' : '#CCCCCC'
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

          Text(option.label)
            .fontSize(14)
            .fontColor(this.getFieldValue(field.field_name) === option.label ? '#FF6B00' : '#333333')
            .fontWeight(this.getFieldValue(field.field_name) === option.label ? FontWeight.Medium : FontWeight.Normal)
            .margin({ left: 8 })
        }
        .height(36)
        .padding({ left: 4, right: 12 })
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          // ✅ 存 label
          this.setFieldValue(field.field_name, option.label);
          console.log(`[Radio] ${field.field_name} = ${option.label}`);
        })
      }, (option: OptionItem, index: number) => `${field.field_name}_radio_${index}`)
    }
    .width('100%')
  }

  @Builder
  CheckboxFieldInline(field: FormField) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.getFieldOptions(field), (option: OptionItem, index: number) => {
        Row() {
          Row() {
            if (this.isOptionChecked(field.field_name, option.label)) {
              Text('✓')
                .fontSize(12)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
            }
          }
          .width(18)
          .height(18)
          .borderRadius(4)
          .border({
            width: 2,
            color: this.isOptionChecked(field.field_name, option.label) ? '#FF6B00' : '#CCCCCC'
          })
          .backgroundColor(this.isOptionChecked(field.field_name, option.label) ? '#FF6B00' : Color.Transparent)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

          Text(option.label)
            .fontSize(14)
            .fontColor(this.isOptionChecked(field.field_name, option.label) ? '#FF6B00' : '#333333')
            .fontWeight(this.isOptionChecked(field.field_name, option.label) ? FontWeight.Medium : FontWeight.Normal)
            .margin({ left: 8 })
        }
        .height(36)
        .padding({ left: 4, right: 12 })
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          // ✅ 存 label
          this.toggleCheckboxOption(field.field_name, option.label);
          console.log(`[Checkbox] ${field.field_name} 切换: ${option.label}`);
        })
      }, (option: OptionItem, index: number) => `${field.field_name}_checkbox_${index}`)
    }
    .width('100%')
  }

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

  @Builder
  ImageField(field: FormField) {
    Column() {
      if (field.show_type === 'imageDesc') {
        if (field.local_image_path) {
          Image('file://' + field.local_image_path)
            .width('100%')
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
            .border({ width: 1, color: '#E5E5E5' })
            .onError(() => {
              console.error('图片加载失败:', field.local_image_path);
            })
        } else if (field.default_value) {
          Column() {
            Text('图片加载中...')
              .fontSize(12)
              .fontColor('#999999')
              .padding(20)
          }
          .width('100%')
          .height(150)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .border({ width: 1, color: '#E5E5E5' })
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            Text('暂无图片')
              .fontSize(12)
              .fontColor('#999999')
              .padding(20)
          }
          .width('100%')
          .height(100)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .border({ width: 1, color: '#E5E5E5' })
          .justifyContent(FlexAlign.Center)
        }

        if (field.hint && field.hint.trim() !== '') {
          Text(field.hint)
            .fontSize(12)
            .fontColor('#666666')
            .margin({ top: 8 })
            .width('100%')
        }

      } else if (field.show_type === 'image') {
        if (this.getFieldValue(field.field_name)) {
          Image('file://' + this.getFieldValue(field.field_name))
            .width('100%')
            .height(200)
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
            .border({ width: 1, color: '#E5E5E5' })
            .margin({ bottom: 8 })
        }

        Row() {
          Text(this.getFieldValue(field.field_name) ? '重新选择图片' : '点击选择图片')
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
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}