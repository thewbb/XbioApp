
/**
 * 本地存储工具
 */
import preferences from '@ohos.data.preferences';

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
      // ✅ 修复：转换为 Error 对象
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
      // ✅ 修复：转换为 Error 对象
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
      // ✅ 不抛出异常，返回空字符串
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
      // ✅ 修复：转换为 Error 对象
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
      // ✅ 修复：转换为 Error 对象
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
}

const storage = new Storage();
export default storage;
