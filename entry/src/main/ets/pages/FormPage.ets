/**
 * 表单填写页面
 *
 * 修复：
 * 1. 提交后无法返回上一页的问题
 * 2. 公式计算逻辑（支持选项分值计算 A=3）
 * 3. 使用安全的表达式计算器（不使用 eval/new Function）
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
   * 支持 "A=3,B=4" 或 "是,否" 格式
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
          label: parts[0].trim(),
          value: parts[1].trim()
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
   */
  isOptionChecked(fieldName: string, optionValue: string): boolean {
    const currentValue = this.getFieldValue(fieldName);
    if (!currentValue) {
      return false;
    }
    const selectedValues = currentValue.split(',').map(v => v.trim());
    return selectedValues.includes(optionValue);
  }

  /**
   * ✅ 切换多选选项
   */
  toggleCheckboxOption(fieldName: string, optionValue: string) {
    const currentValue = this.getFieldValue(fieldName);
    let selectedValues = currentValue ? currentValue.split(',').map(v => v.trim()).filter(v => v !== '') : [];

    if (selectedValues.includes(optionValue)) {
      // 移除
      selectedValues = selectedValues.filter(v => v !== optionValue);
    } else {
      // 添加
      selectedValues.push(optionValue);
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

        // 只有值变化时才更新，避免无限循环
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
   * ✅ 核心修复：公式计算逻辑（使用手写解析器）
   *
   * 规则：
   * 1. 公式格式：field1 * 0.5 + field2
   * 2. 如果 field 的 select_value = "A=3,B=4"，当前选择了 A，则取值 3
   * 3. 如果 field 的值是纯数字，直接计算
   * 4. 如果 field 的值是字符串（非数字），尝试匹配选项的 value，否则视为 0
   */
  calculateFormula(formula: string): number {
    let expression = formula;

    if (!this.currentTable || !this.currentTable.fields) {
      return 0;
    }

    // 遍历所有字段，替换公式中的变量名为数值
    this.currentTable.fields.forEach(field => {
      const fieldName = field.field_name;

      // 使用正则确保全字匹配（避免 field1 匹配到 field11）
      const regex = new RegExp(`\\b${fieldName}\\b`, 'g');
      if (!regex.test(expression)) {
        return; // 公式中不包含该字段
      }

      const rawValue = this.getFieldValue(fieldName);
      let numValue = 0;

      console.log(`  处理字段 ${fieldName}, 原始值: "${rawValue}"`);

      // 1. 如果字段值为空
      if (!rawValue || rawValue.trim() === '') {
        numValue = 0;
      }
      // 2. 如果字段值是纯数字（包括小数）
      else if (!isNaN(Number(rawValue))) {
        numValue = parseFloat(rawValue);
        console.log(`    -> 数值: ${numValue}`);
      }
      // 3. 如果字段值不是数字（可能是选项的 label 或 value）
      else {
        // 尝试从选项定义中找对应的数值
        const options = this.parseOptions(field.select_value);

        // 先检查是否是某个选项的 value（直接匹配）
        const matchedOption = options.find(opt => opt.value === rawValue);
        if (matchedOption) {
          // 如果 value 本身是数字，则使用
          if (!isNaN(Number(matchedOption.value))) {
            numValue = parseFloat(matchedOption.value);
            console.log(`    -> 匹配到选项 value: ${numValue}`);
          } else {
            numValue = 0;
            console.log(`    -> 选项 value 不是数字，使用 0`);
          }
        }
        // 再检查是否是某个选项的 label
        else {
          const matchedByLabel = options.find(opt => opt.label === rawValue);
          if (matchedByLabel && !isNaN(Number(matchedByLabel.value))) {
            numValue = parseFloat(matchedByLabel.value);
            console.log(`    -> 匹配到选项 label: ${rawValue}, value: ${numValue}`);
          } else {
            numValue = 0;
            console.log(`    -> 未匹配到有效选项，使用 0`);
          }
        }
      }

      // 替换公式中的字段名为数值
      expression = expression.replace(regex, numValue.toString());
    });

    console.log(`  最终表达式: ${expression}`);

    try {
      // ✅ 使用安全的表达式计算器
      const result = this.evaluateExpression(expression);
      console.log(`  计算结果: ${result}`);

      // 保留两位小数
      return Math.round(result * 100) / 100;
    } catch (err) {
      console.error('  ❌ 计算错误:', err);
      return 0;
    }
  }

  /**
   * ✅ 安全的数学表达式计算器（支持 +、-、*、/、()）
   * 使用逆波兰表达式（RPN）算法
   */
  evaluateExpression(expr: string): number {
    // 去除空格
    expr = expr.replace(/\s+/g, '');

    // 词法分析：将表达式拆分为 token
    const tokens: string[] = [];
    let numBuffer = '';

    for (let i = 0; i < expr.length; i++) {
      const char = expr[i];

      if (char >= '0' && char <= '9' || char === '.') {
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

    // 转换为逆波兰表达式（后缀表达式）
    const rpn = this.toRPN(tokens);
    console.log('  RPN:', rpn);

    // 计算逆波兰表达式
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
        // 数字直接输出
        output.push(token);
      } else if (token === '(') {
        operators.push(token);
      } else if (token === ')') {
        // 弹出直到遇到左括号
        while (operators.length > 0 && operators[operators.length - 1] !== '(') {
          output.push(operators.pop()!);
        }
        operators.pop(); // 弹出 '('
      } else if (precedence[token] !== undefined) {
        // 运算符
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

    // 弹出剩余的运算符
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

  validateForm(): boolean {
    if (!this.currentTable || !this.currentTable.fields) {
      return false;
    }

    for (let field of this.currentTable.fields) {
      // ✅ 只验证可见且可编辑的必填字段
      if (this.isFieldVisible(field) && field.is_editable === '1' && field.required === 1) {
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
   * ✅ 判断字段是否应该显示（根据 control_by 控制）
   */
  isFieldVisible(field: FormField): boolean {
    // 如果没有 control_by，直接显示
    if (!field.control_by || field.control_by.trim() === '') {
      return true;
    }

    // 解析 control_by，格式：field1.1,field1.3
    const controls = field.control_by.split(',').map(v => v.trim());

    for (let i = 0; i < controls.length; i++) {
      const control = controls[i];
      if (control === '') {
        continue;
      }

      // 分割字段名和选项索引，如 "field1.1" -> ["field1", "1"]
      const parts = control.split('.');
      if (parts.length !== 2) {
        continue;
      }

      const controlFieldName = parts[0];
      const controlOptionIndex = parseInt(parts[1]);

      // 获取控制字段的当前值
      const controlFieldValue = this.getFieldValue(controlFieldName);
      if (!controlFieldValue) {
        continue;
      }

      // 获取控制字段的选项列表
      const controlField = this.currentTable?.fields?.find(f => f.field_name === controlFieldName);
      if (!controlField) {
        continue;
      }

      const options = this.parseOptions(controlField.select_value);
      if (controlOptionIndex < 1 || controlOptionIndex > options.length) {
        continue;
      }

      // 检查当前值是否匹配指定的选项（索引从 1 开始）
      const targetOption = options[controlOptionIndex - 1];

      // 支持多选（逗号分隔）
      const selectedValues = controlFieldValue.split(',').map(v => v.trim());
      if (selectedValues.includes(targetOption.value)) {
        return true;
      }
    }

    // 如果没有任何控制条件满足，则不显示
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

      const record: FormRecord = {
        table_id: this.currentTable!.id,
        step_id: this.currentTable!.step_id,
        data: dataObj,
        filled_time: new Date().toLocaleString('zh-CN'),
        is_uploaded: false  // 标记为未上传
      };

      // 只保存到本地
      const saveSuccess = await storage.saveFormRecord(
        this.currentUsername,
        this.currentTask!.id,
        record
      );

      this.submitting = false;

      if (saveSuccess) {
        console.log('✅ 本地保存成功');
        this.toastController.show('✅ 保存成功，可在记录页面上传');

        // ✅ 修复：确保返回上一页
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

      // Toast 组件
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
    if (!this.isFieldVisible(field)) {
      // 不显示该字段
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

          if (field.formula && field.formula.trim() !== '') {
            Text(' 🧮')
              .fontSize(12)
              .margin({ left: 4 })
          }
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
          Radio({ value: option.value, group: field.field_name })
            .checked(this.getFieldValue(field.field_name) === option.value)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.setFieldValue(field.field_name, option.value);
              }
            })

          Text(option.label)
            .fontSize(14)
            .fontColor('#333333')
            .margin({ left: 8 })
            .onClick(() => {
              this.setFieldValue(field.field_name, option.value);
            })
        }
        .height(36)
        .padding({ left: 4, right: 12 })
        .margin({ right: 8, bottom: 8 })
      }, (option: OptionItem, index: number) => `${field.field_name}_radio_${index}`)
    }
    .width('100%')
  }

  @Builder
  RadioFieldInline(field: FormField) {
    this.SelectFieldInline(field);
  }

  @Builder
  CheckboxFieldInline(field: FormField) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.getFieldOptions(field), (option: OptionItem, index: number) => {
        Row() {
          Checkbox()
            .select(this.isOptionChecked(field.field_name, option.value))
            .selectedColor('#FF6B00')
            .onChange((isChecked: boolean) => {
              this.toggleCheckboxOption(field.field_name, option.value);
            })

          Text(option.label)
            .fontSize(14)
            .fontColor('#333333')
            .margin({ left: 8 })
            .onClick(() => {
              this.toggleCheckboxOption(field.field_name, option.value);
            })
        }
        .height(36)
        .padding({ left: 4, right: 12 })
        .margin({ right: 8, bottom: 8 })
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