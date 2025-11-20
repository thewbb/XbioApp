
/**
 * 类型定义
 */

// ========== 基础类型 ==========

// API 响应基础结构
export interface ApiResponse {
  code: number;
  message?: string;
  error?: string;
  dataMap?: object;
  dataList?: object[];
}

// 用户信息
export interface UserInfo {
  id: number;
  username: string;
  name?: string;
  phone?: string;
  email?: string;
  avatar?: string;
  role?: string;
  organId?: string;
  organName?: string;
  real_name?: string;  // ✅ 新增：真实姓名
  mobile?: string;     // ✅ 新增：手机号
  utime?: string;      // ✅ 新增：更新时间
}

// 登录请求
export interface LoginRequest {
  username: string;
  password: string;
}

// 登录响应
export interface LoginResponse {
  token: string;
  userInfo: UserInfo;
}

// ✅ 新增：Token 验证请求
export interface TokenVerifyRequest {
  token: string;
}

// ✅ 新增：Token 验证响应
export interface TokenVerifyResponse {
  id: number;
  username: string;
  real_name: string;
  mobile: string;
  utime: string;
}

// 本地用户数据（单个用户）
export interface LocalUser {
  username: string;
  passwordMd5: string;
  userInfo: UserInfo;
  token: string;
  lastLoginTime: number;
  keepLogin: boolean;
}

// 本地用户数据存储（所有用户）- 使用类代替索引签名
export class LocalUsers {
  private users: Map<string, LocalUser> = new Map();

  set(username: string, user: LocalUser): void {
    this.users.set(username, user);
  }

  get(username: string): LocalUser | undefined {
    return this.users.get(username);
  }

  delete(username: string): void {
    this.users.delete(username);
  }

  has(username: string): boolean {
    return this.users.has(username);
  }

  getUsernames(): string[] {
    return Array.from(this.users.keys());
  }

  getAllUsers(): LocalUser[] {
    return Array.from(this.users.values());
  }

  toJSON(): string {
    const usersArray: LocalUser[] = Array.from(this.users.values());
    return JSON.stringify(usersArray);
  }

  static fromJSON(json: string): LocalUsers {
    const localUsers = new LocalUsers();
    if (json) {
      try {
        const usersArray: Array<Object> = JSON.parse(json);
        for (let i = 0; i < usersArray.length; i++) {
          const userObj: Object = usersArray[i];
          const user: LocalUser = userObj as LocalUser;
          if (user && user.username) {
            localUsers.set(user.username, user);
          }
        }
      } catch (e) {
        console.error('解析 LocalUsers 失败:', e);
      }
    }
    return localUsers;
  }

  clear(): void {
    this.users.clear();
  }

  size(): number {
    return this.users.size;
  }
}

// 当前登录用户
export interface CurrentUser {
  username: string;
  keepLogin: boolean;
  lastLoginTime: number;
}

// ========== 任务相关类型 ==========

// 表单字段
export interface FormField {
  id: number;
  table_name_id: number;
  field_name: string;
  field_type: string;
  annotation: string;
  annotation_en?: string;
  show_type: string;  // input, radio, checkbox, select, date, textarea, inputUnit
  field_desc?: string;  // 单位或说明
  select_value?: string;  // 选项值，逗号分隔
  default_value?: string;
  required: number;  // 0=非必填，1=必填
  control_by?: string;  // 控制显示的字段，如 "ss12.1" 表示当 ss12 选择第1个选项时显示
  is_controlled: number;  // 0=不受控，1=受控
  order_id?: number;
  col?: number;  // 占用列数
  new_line: number;  // 0=不换行，1=换行
  hold_space: number;  // 0=不占位，1=占位
  hint?: string;
  regular?: string;  // 正则表达式
  formula?: string;  // 计算公式
  is_editable: string;  // "0"=不可编辑，"1"=可编辑
  is_list: string;  // "0"=不在列表显示，"1"=在列表显示
}

// 表单信息（包含字段）
export interface FormTable {
  id: number;
  project_id: number;
  step_id: number;
  step_name: string;
  table_name: string;
  user_id: number;
  create_time: string;
  state:number;
  multi_line: number;  // 0=单行，1=多行
  fields: FormField[];
}

// 项目信息
export interface Project {
  id: number;
  project_name: string;
  user_id: number;
  organId: string;
  group_name?: string;
  ocr_flag: string;  // "0"=关闭，"1"=开启
  create_time: string;
  tables: FormTable[];
}

export interface FormRecord {
  table_id: number;           // 表单ID
  step_id: number;            // 步骤ID
  data: Record<string, string>;  // 表单数据
  filled_time: string;        // 填写时间
  is_uploaded: boolean;       // 是否已上传
}

// 随访任务
export interface FollowUpTask {
  id: number;
  project_id: number;
  project_name: string;
  patient_no: string;
  from_user_id: number;
  to_user_id: number;
  name:string;
  creator: string;
  create_time: string;
  state: number;  // 0=待执行，1=进行中，2=已完成
  percent: string;
  sf_table_ids: string;
  comment?: string;
  project?: Project;

  local_records?: FormRecord[];  // 本地保存的表单数据
  consent_signature?: ConsentSignature;
}

// 任务列表请求
export interface TaskListRequest {
  token: string;
}

// ✅ 新增：任务详情请求
export interface TaskDetailRequest {
  token: string;
  task_id: number;
}

// ✅ 新增：任务详情响应
export interface TaskDetailResponse {
  id: number;
  project_id: number;
  project_name: string;
  patient_no: string;
  from_user_id: number;
  to_user_id: number;
  creator: string;
  create_time: string;
  state: number;
  percent: string;
  sf_table_ids: string;
  comment?: string;
  project: Project;
}

// ========== 随访记录相关类型 ==========

// 随访记录
export interface FollowUpRecord {
  id?: number;
  taskId: number;
  patientNo: string;
  projectName: string;
  formData: Record<string, Object>;
  createTime: number;
  updateTime: number;
  synced: boolean;
  syncTime?: number;
}

export interface SaveSubStepDataParams {
  token: string;
  table_name: string;
  patientNo: string;
  multi_line: number;
  subStepId: number;
  data: string;  // JSON 字符串
}

export interface ConsentSignature {
  signature_image: string;      // 签名图片 Base64
  signature_time: string;        // 签名时间
  patient_name: string;          // 患者姓名
  patient_no: string;            // 患者编号
  signature_paths?: string;      // ✅ 新增：签名路径数据
}

