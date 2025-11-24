/**
 * HTTP 请求工具（支持动态服务器地址）
 */
import http from '@ohos.net.http';
import { ApiResponse } from '../types';
import storage from './storage';

class HttpUtil {
  private token: string = '';
  private baseUrl: string = 'http://127.0.0.1:8080/Xbiosms_war_exploded';  // 默认值

  /**
   * ✅ 初始化 - 加载服务器地址
   */
  async init(): Promise<void> {
    try {
      this.baseUrl = await storage.getServerUrl();
      console.log('✅ HTTP 工具初始化，服务器地址:', this.baseUrl);
    } catch (e) {
      console.error('❌ HTTP 工具初始化失败:', e);
    }
  }

  /**
   * ✅ 设置服务器地址
   */
  async setBaseUrl(url: string): Promise<void> {
    this.baseUrl = url;
    await storage.setServerUrl(url);
    console.log('✅ 服务器地址已更新:', this.baseUrl);
  }

  /**
   * ✅ 获取当前服务器地址
   */
  getBaseUrl(): string {
    return this.baseUrl;
  }

  /**
   * 设置 Token
   */
  setToken(token: string) {
    this.token = token;
  }

  /**
   * GET 请求
   */
  async get(url: string, params?: Record<string, string>): Promise<ApiResponse> {
    let fullUrl = this.baseUrl + url;

    // 拼接参数
    if (params) {
      const query = Object.keys(params)
        .map(key => `${key}=${encodeURIComponent(params[key])}`)
        .join('&');
      fullUrl += '?' + query;
    }

    return this.request(fullUrl, 'GET');
  }

  /**
   * POST 请求
   */
  async post(url: string, data?: Object): Promise<ApiResponse> {
    return this.request(this.baseUrl + url, 'POST', data);
  }

  /**
   * PUT 请求
   */
  async put(url: string, data?: Object): Promise<ApiResponse> {
    return this.request(this.baseUrl + url, 'PUT', data);
  }

  /**
   * DELETE 请求
   */
  async delete(url: string): Promise<ApiResponse> {
    return this.request(this.baseUrl + url, 'DELETE');
  }

  /**
   * 通用请求方法
   */
  private async request(url: string, method: string, data?: Object): Promise<ApiResponse> {
    const httpRequest = http.createHttp();

    try {
      const response = await httpRequest.request(url, {
        method: method as http.RequestMethod,
        header: {
          'Content-Type': 'application/json',
          'token': this.token
        },
        extraData: data ? JSON.stringify(data) : undefined,
        connectTimeout: 60000,
        readTimeout: 60000
      });

      // 解析响应
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as ApiResponse;
        return result;
      } else {
        return {
          code: response.responseCode,
          message: '请求失败',
          error: `HTTP ${response.responseCode}`
        };
      }
    } catch (error) {
      console.error('HTTP请求错误:', error);
      return {
        code: -1,
        message: '网络错误',
        error: error.message || '请求失败'
      };
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 检查网络连接
   */
  async isOnline(): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(this.baseUrl + '/health.json', {
        method: http.RequestMethod.GET,
        connectTimeout: 3000,
        readTimeout: 3000
      });
      httpRequest.destroy();
      return response.responseCode === 200;
    } catch (error) {
      return false;
    }
  }
}

// 导出单例
export default new HttpUtil();