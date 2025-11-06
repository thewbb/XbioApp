
/**
 * 本地存储工具
 */
import preferences from '@ohos.data.preferences';
import { FollowUpTask, FormRecord } from '../types';

// 存储键常量
export class StorageKeys {
  // 用户相关
  static readonly CURRENT_USER = 'currentUser';           // 当前登录用户
  static readonly LOCAL_USERS = 'localUsers';             // 本地用户列表
  static readonly USER_TOKEN = 'token';                   // 用户令牌
  static readonly USER_INFO = 'userInfo';                 // 用户信息

  // 任务和记录相关
  static readonly FOLLOW_UP_TASKS = 'followUpTasks';      // 随访任务列表
  static readonly FOLLOW_UP_RECORDS = 'followUpRecords';  // 随访记录
  static readonly LAST_SYNC_TIME = 'lastSyncTime';        // 最后同步时间
}

/**
 * 未上传记录项
 */
export interface UnuploadedRecordItem {
  task: FollowUpTask;
  record: FormRecord;
}

/**
 * 数据统计信息
 */
export interface DataStatistics {
  totalTasks: number;
  completedTasks: number;
  unuploadedRecords: number;
  lastSyncTime: string;
}

class Storage {
  private store: preferences.Preferences | null = null;
  private context: Context | null = null;

  async init(): Promise<void> {
    try {
      if (!this.context) {
        this.context = getContext(this) as Context;
      }

      this.store = await preferences.getPreferences(this.context, 'app_storage');
      console.log('存储初始化成功');
    } catch (e) {
      console.error('存储初始化失败:', e);
      throw new Error('存储初始化失败: ' + (e as Error).message);
    }
  }

  async set(key: string, value: string): Promise<void> {
    if (!this.store) {
      await this.init();
    }

    try {
      await this.store!.put(key, value);
      await this.store!.flush();
      console.log(`存储成功: ${key}`);
    } catch (e) {
      console.error(`存储失败: ${key}`, e);
      throw new Error(`存储失败: ${key}, ${(e as Error).message}`);
    }
  }

  async get(key: string): Promise<string> {
    if (!this.store) {
      await this.init();
    }

    try {
      const value = await this.store!.get(key, '');
      return value as string;
    } catch (e) {
      console.error(`读取失败: ${key}`, e);
      return '';
    }
  }

  async remove(key: string): Promise<void> {
    if (!this.store) {
      await this.init();
    }

    try {
      await this.store!.delete(key);
      await this.store!.flush();
      console.log(`删除成功: ${key}`);
    } catch (e) {
      console.error(`删除失败: ${key}`, e);
      throw new Error(`删除失败: ${key}, ${(e as Error).message}`);
    }
  }

  async clear(): Promise<void> {
    if (!this.store) {
      await this.init();
    }

    try {
      await this.store!.clear();
      await this.store!.flush();
      console.log('清空存储成功');
    } catch (e) {
      console.error('清空存储失败:', e);
      throw new Error('清空存储失败: ' + (e as Error).message);
    }
  }

  /**
   * 设置用户专属数据
   * @param username 用户名
   * @param key 存储键
   * @param value 值
   */
  async setUserData(username: string, key: string, value: string): Promise<void> {
    const userKey = `${username}_${key}`;
    await this.set(userKey, value);
  }

  /**
   * 获取用户专属数据
   * @param username 用户名
   * @param key 存储键
   */
  async getUserData(username: string, key: string): Promise<string> {
    const userKey = `${username}_${key}`;
    return await this.get(userKey);
  }

  /**
   * 删除用户专属数据
   * @param username 用户名
   * @param key 存储键
   */
  async removeUserData(username: string, key: string): Promise<void> {
    const userKey = `${username}_${key}`;
    await this.remove(userKey);
  }

  // ============================================
  // 随访任务相关方法
  // ============================================

  /**
   * 保存用户的随访任务列表
   */
  async saveFollowUpTasks(username: string, tasks: FollowUpTask[]): Promise<void> {
    try {
      const data = JSON.stringify(tasks);
      await this.setUserData(username, StorageKeys.FOLLOW_UP_TASKS, data);
      console.log('✅ 随访任务已保存，数量:', tasks.length);
    } catch (e) {
      console.error('❌ 保存随访任务失败:', e);
      throw new Error('保存随访任务失败: ' + (e as Error).message);
    }
  }

  /**
   * 加载用户的随访任务列表
   */
  async loadFollowUpTasks(username: string): Promise<FollowUpTask[]> {
    try {
      const data = await this.getUserData(username, StorageKeys.FOLLOW_UP_TASKS);
      if (data && data !== '') {
        const tasks = JSON.parse(data) as FollowUpTask[];
        console.log('✅ 随访任务加载成功，数量:', tasks.length);
        return tasks;
      }
    } catch (e) {
      console.error('❌ 加载随访任务失败:', e);
    }
    return [];
  }

  /**
   * 保存表单记录到任务
   */
  async saveFormRecord(username: string, taskId: number, record: FormRecord): Promise<boolean> {
    try {
      // 加载所有任务
      const tasks = await this.loadFollowUpTasks(username);
      const task = tasks.find(t => t.id === taskId);

      if (!task) {
        console.error('❌ 任务不存在:', taskId);
        return false;
      }

      // 初始化 local_records
      if (!task.local_records) {
        task.local_records = [];
      }

      // 查找是否已存在相同表单的记录
      const existingIndex = task.local_records.findIndex(
        r => r.table_id === record.table_id
      );

      if (existingIndex >= 0) {
        // 更新已存在的记录
        task.local_records[existingIndex] = record;
        console.log('✅ 更新表单记录:', record.table_id);
      } else {
        // 添加新记录
        task.local_records.push(record);
        console.log('✅ 添加表单记录:', record.table_id);
      }

      // 更新表单状态
      if (task.project && task.project.tables) {
        const table = task.project.tables.find(t => t.id === record.table_id);
        if (table) {
          table.state = 1;  // 标记为已填写
        }
      }

      // 重新计算完成百分比
      this.updateTaskProgress(task);

      // 保存回本地
      await this.saveFollowUpTasks(username, tasks);
      return true;

    } catch (e) {
      console.error('❌ 保存表单记录失败:', e);
      return false;
    }
  }

  /**
   * 获取任务的表单记录
   */
  async getFormRecord(username: string, taskId: number, tableId: number): Promise<FormRecord | null> {
    try {
      const tasks = await this.loadFollowUpTasks(username);
      const task = tasks.find(t => t.id === taskId);

      if (!task || !task.local_records) {
        return null;
      }

      const record = task.local_records.find(r => r.table_id === tableId);
      return record || null;

    } catch (e) {
      console.error('❌ 获取表单记录失败:', e);
      return null;
    }
  }

  /**
   * 获取所有未上传的记录
   */
  async getAllUnuploadedRecords(username: string): Promise<UnuploadedRecordItem[]> {
    const result: UnuploadedRecordItem[] = [];

    try {
      const tasks = await this.loadFollowUpTasks(username);

      tasks.forEach(task => {
        if (task.local_records) {
          task.local_records.forEach(record => {
            if (!record.is_uploaded) {
              // 创建明确类型的对象
              const item: UnuploadedRecordItem = {
                task: task,
                record: record
              };
              result.push(item);
            }
          });
        }
      });

      console.log('✅ 获取未上传记录，数量:', result.length);
    } catch (e) {
      console.error('❌ 获取未上传记录失败:', e);
    }

    return result;
  }

  /**
   * 标记记录为已上传
   */
  async markRecordAsUploaded(username: string, taskId: number, tableId: number): Promise<boolean> {
    try {
      const tasks = await this.loadFollowUpTasks(username);
      const task = tasks.find(t => t.id === taskId);

      if (!task || !task.local_records) {
        return false;
      }

      const record = task.local_records.find(r => r.table_id === tableId);
      if (record) {
        record.is_uploaded = true;
        await this.saveFollowUpTasks(username, tasks);
        console.log('✅ 标记记录为已上传:', tableId);
        return true;
      }

    } catch (e) {
      console.error('❌ 标记记录失败:', e);
    }

    return false;
  }

  /**
   * 删除任务的表单记录
   */
  /**
   * ✅ 删除表单记录
   */
  async deleteFormRecord(username: string, taskId: number, tableId: number): Promise<boolean> {
    try {
      console.log(`删除记录: 用户=${username}, 任务=${taskId}, 表格=${tableId}`);

      // 1. 加载任务列表
      let tasksStr: string = await this.getUserData(username, StorageKeys.FOLLOW_UP_TASKS);
      if (!tasksStr) {
        console.error('任务列表为空');
        return false;
      }

      let tasks: FollowUpTask[] = JSON.parse(tasksStr);

      // 2. 找到对应任务
      const task = tasks.find(t => t.id === taskId);
      if (!task) {
        console.error('任务不存在:', taskId);
        return false;
      }

      // 3. 删除记录
      if (!task.local_records) {
        console.log('任务没有本地记录');
        return false;
      }

      const recordIndex = task.local_records.findIndex(r => r.table_id === tableId);
      if (recordIndex === -1) {
        console.log('记录不存在');
        return false;
      }

      // 移除记录
      task.local_records.splice(recordIndex, 1);

      // 4. 保存任务列表
      await this.setUserData(username, StorageKeys.FOLLOW_UP_TASKS, JSON.stringify(tasks));

      console.log('✅ 删除记录成功');
      return true;

    } catch (e) {
      console.error('❌ 删除记录失败:', e);
      return false;
    }
  }

  /**
   * 合并服务器任务和本地记录
   */
  async mergeTasks(username: string, serverTasks: FollowUpTask[]): Promise<FollowUpTask[]> {
    try {
      const localTasks = await this.loadFollowUpTasks(username);

      // 遍历服务器任务，合并本地记录
      serverTasks.forEach(serverTask => {
        const localTask = localTasks.find(t => t.id === serverTask.id);

        if (localTask && localTask.local_records) {
          // 合并本地记录
          serverTask.local_records = localTask.local_records;

          // 更新表单状态
          if (serverTask.project && serverTask.project.tables) {
            serverTask.project.tables.forEach(table => {
              const hasRecord = localTask.local_records?.some(r => r.table_id === table.id);
              if (hasRecord) {
                table.state = 1;
              }
            });
          }

          // 更新进度
          this.updateTaskProgress(serverTask);
        }
      });

      // 保存合并后的数据
      await this.saveFollowUpTasks(username, serverTasks);
      console.log('✅ 任务数据已合并');

      return serverTasks;

    } catch (e) {
      console.error('❌ 合并任务数据失败:', e);
      return serverTasks;
    }
  }

  /**
   * 更新任务进度
   */
  private updateTaskProgress(task: FollowUpTask): void {
    if (!task.project || !task.project.tables) {
      return;
    }

    const total = task.project.tables.length;
    const completed = task.project.tables.filter(t => t.state === 1).length;
    const percent = total > 0 ? Math.round((completed / total) * 100) : 0;

    task.percent = percent.toString();

    // 更新任务状态
    if (percent === 0) {
      task.state = 0;  // 待执行
    } else if (percent === 100) {
      task.state = 2;  // 已完成
    } else {
      task.state = 1;  // 进行中
    }

    console.log(`✅ 任务进度更新: ${completed}/${total} (${percent}%)`);
  }

  /**
   * 更新最后同步时间
   */
  async updateLastSyncTime(username: string): Promise<void> {
    try {
      const now = new Date().toLocaleString('zh-CN');
      await this.setUserData(username, StorageKeys.LAST_SYNC_TIME, now);
      console.log('✅ 更新同步时间:', now);
    } catch (e) {
      console.error('❌ 更新同步时间失败:', e);
    }
  }

  /**
   * 获取最后同步时间
   */
  async getLastSyncTime(username: string): Promise<string> {
    try {
      return await this.getUserData(username, StorageKeys.LAST_SYNC_TIME);
    } catch (e) {
      console.error('❌ 获取同步时间失败:', e);
      return '';
    }
  }

  /**
   * 清空用户的随访数据
   */
  async clearFollowUpData(username: string): Promise<void> {
    try {
      await this.removeUserData(username, StorageKeys.FOLLOW_UP_TASKS);
      await this.removeUserData(username, StorageKeys.LAST_SYNC_TIME);
      console.log('✅ 用户随访数据已清空');
    } catch (e) {
      console.error('❌ 清空随访数据失败:', e);
    }
  }

  /**
   * 获取用户数据统计
   */
  async getDataStatistics(username: string): Promise<DataStatistics> {
    try {
      const tasks = await this.loadFollowUpTasks(username);
      const unuploadedRecords = await this.getAllUnuploadedRecords(username);
      const lastSyncTime = await this.getLastSyncTime(username);

      const completedTasks = tasks.filter(t => t.state === 2).length;

      const statistics: DataStatistics = {
        totalTasks: tasks.length,
        completedTasks: completedTasks,
        unuploadedRecords: unuploadedRecords.length,
        lastSyncTime: lastSyncTime
      };

      return statistics;

    } catch (e) {
      console.error('❌ 获取数据统计失败:', e);

      const emptyStatistics: DataStatistics = {
        totalTasks: 0,
        completedTasks: 0,
        unuploadedRecords: 0,
        lastSyncTime: ''
      };

      return emptyStatistics;
    }
  }
}

const storage = new Storage();
export default storage;
