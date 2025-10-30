
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

  /**
   * 设置用户
   */
  set(username: string, user: LocalUser): void {
    this.users.set(username, user);
  }

  /**
   * 获取用户
   */
  get(username: string): LocalUser | undefined {
    return this.users.get(username);
  }

  /**
   * 删除用户
   */
  delete(username: string): void {
    this.users.delete(username);
  }

  /**
   * 是否存在用户
   */
  has(username: string): boolean {
    return this.users.has(username);
  }

  /**
   * 获取所有用户名
   */
  getUsernames(): string[] {
    return Array.from(this.users.keys());
  }

  /**
   * 获取所有用户
   */
  getAllUsers(): LocalUser[] {
    return Array.from(this.users.values());
  }

  /**
   * 转换为 JSON 字符串
   */
  toJSON(): string {
    // 将 Map 转换为数组格式
    const usersArray: LocalUser[] = Array.from(this.users.values());
    return JSON.stringify(usersArray);
  }

  /**
   * 从 JSON 字符串解析
   */
  static fromJSON(json: string): LocalUsers {
    const localUsers = new LocalUsers();
    if (json) {
      try {
        // 解析为数组
        const usersArray: Array<Object> = JSON.parse(json);

        // 遍历数组，添加到 Map
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

  /**
   * 清空所有用户
   */
  clear(): void {
    this.users.clear();
  }

  /**
   * 获取用户数量
   */
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

// 表单信息
export interface FormTable {
  id: number;
  project_id: number;
  step_id: number;
  step_name: string;
  table_name: string;
  user_id: number;
  create_time: string;
  multi_line: number;  // 0=单行，1=多行
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

// 随访任务
export interface FollowUpTask {
  id: number;
  project_id: number;
  project_name: string;
  patient_no: string;  // 患者编号
  from_user_id: number;
  to_user_id: number;
  creator: string;  // 创建人
  create_time: string;
  state: number;  // 0=待执行，1=进行中，2=已完成
  percent: string;  // 完成百分比，如 "0%"
  sf_table_ids: string;  // 随访表单ID，逗号分隔
  comment?: string;
  project?: Project;
}

// 任务列表请求
export interface TaskListRequest {
  token: string;
}

// 任务列表响应（直接使用 ApiResponse，dataList 就是任务数组）

// ========== 随访记录相关类型 ==========

// 随访记录
export interface FollowUpRecord {
  id?: number;  // 本地ID
  taskId: number;  // 任务ID
  patientNo: string;  // 患者编号
  projectName: string;  // 项目名称
  formData: Record<string, Object>;  // 表单数据
  createTime: number;  // 创建时间戳
  updateTime: number;  // 更新时间戳
  synced: boolean;  // 是否已同步
  syncTime?: number;  // 同步时间戳
}

// 本地记录存储
export class LocalRecords {
  private records: Map<number, FollowUpRecord> = new Map();

  /**
   * 添加记录
   */
  add(record: FollowUpRecord): void {
    const id = record.id || Date.now();
    record.id = id;
    this.records.set(id, record);
  }

  /**
   * 更新记录
   */
  update(id: number, record: FollowUpRecord): void {
    this.records.set(id, record);
  }

  /**
   * 删除记录
   */
  remove(id: number): void {
    this.records.delete(id);
  }

  /**
   * 获取记录
   */
  get(id: number): FollowUpRecord | undefined {
    return this.records.get(id);
  }

  /**
   * 获取所有记录
   */
  getAll(): FollowUpRecord[] {
    return Array.from(this.records.values());
  }

  /**
   * 获取未同步的记录
   */
  getUnsynced(): FollowUpRecord[] {
    return this.getAll().filter(r => !r.synced);
  }

  /**
   * 获取已同步的记录
   */
  getSynced(): FollowUpRecord[] {
    return this.getAll().filter(r => r.synced);
  }

  /**
   * 转换为 JSON 字符串
   */
  toJSON(): string {
    const recordsArray: FollowUpRecord[] = Array.from(this.records.values());
    return JSON.stringify(recordsArray);
  }

  /**
   * 从 JSON 字符串解析
   */
  static fromJSON(json: string): LocalRecords {
    const localRecords = new LocalRecords();
    if (json) {
      try {
        const recordsArray: Array<Object> = JSON.parse(json);

        for (let i = 0; i < recordsArray.length; i++) {
          const recordObj: Object = recordsArray[i];
          const record: FollowUpRecord = recordObj as FollowUpRecord;

          if (record && record.id) {
            localRecords.records.set(record.id, record);
          }
        }
      } catch (e) {
        console.error('解析 LocalRecords 失败:', e);
      }
    }
    return localRecords;
  }

  /**
   * 清空所有记录
   */
  clear(): void {
    this.records.clear();
  }

  /**
   * 获取记录数量
   */
  size(): number {
    return this.records.size;
  }
}
