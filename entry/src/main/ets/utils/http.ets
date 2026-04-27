/**
 * HTTP 请求工具（支持动态服务器地址）
 */
import http from '@ohos.net.http';
import { ApiResponse } from '../types';
import storage from './storage';
import fileIo from '@ohos.file.fs';
import util from '@ohos.util';

class HttpUtil {
  private token: string = '';
  private baseUrl: string = 'http://172.30.249.228:8080';  // 默认值
  private initialized: boolean = false;
  private initPromise: Promise<void>;

  constructor() {
    // 单例创建时自动开始初始化，外部无需调用 init()
    this.initPromise = this._init();
  }

  private async _init(): Promise<void> {
    try {
      this.baseUrl = await storage.getServerUrl();
      this.initialized = true;
      console.log('✅ HTTP 工具初始化，服务器地址:', this.baseUrl);
    } catch (e) {
      this.initialized = true; // 失败也标记完成，使用默认值
      console.error('❌ HTTP 工具初始化失败，使用默认地址:', e);
    }
  }

  /**
   * 确保初始化完成（内部使用）
   */
  private async ensureInit(): Promise<void> {
    if (!this.initialized) {
      await this.initPromise;
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
    await this.ensureInit();
    let fullUrl = this.baseUrl + url;

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
    await this.ensureInit();
    return this.request(this.baseUrl + url, 'POST', data);
  }

  /**
   * PUT 请求
   */
  async put(url: string, data?: Object): Promise<ApiResponse> {
    await this.ensureInit();
    return this.request(this.baseUrl + url, 'PUT', data);
  }

  /**
   * DELETE 请求
   */
  async delete(url: string): Promise<ApiResponse> {
    await this.ensureInit();
    return this.request(this.baseUrl + url, 'DELETE');
  }

  /**
   * 通用请求方法
   */
  private async request(url: string, method: string, data?: Object): Promise<ApiResponse> {
    const httpRequest = http.createHttp();
    console.log(url + ':' + JSON.stringify(data));

    try {
      const response = await httpRequest.request(url, {
        method: method as http.RequestMethod,
        header: {
          'Content-Type': 'application/json',
          'token': this.token
        },
        extraData: data ? JSON.stringify(data) : undefined,
        expectDataType: http.HttpDataType.STRING,  // ← 明确要 string
        connectTimeout: 60000,
        readTimeout: 60000,
        maxLimit: 100 * 1024 * 1024
      });

      if (response.responseCode === 200) {
        let resultStr: string;

        // 防御：result 可能是 ArrayBuffer
        if (response.result instanceof ArrayBuffer) {
          const decoder = new util.TextDecoder('utf-8');
          resultStr = decoder.decodeWithStream(new Uint8Array(response.result as ArrayBuffer));
        } else {
          resultStr = response.result as string;
        }

        try {
          const result = JSON.parse(resultStr) as ApiResponse;
          return result;
        } catch (parseError) {
          console.error('JSON解析失败:', parseError, '原始内容:', resultStr.substring(0, 200));
          return {
            code: -2,
            message: 'JSON解析失败',
            error: String(parseError)
          };
        }
      } else {
        return {
          code: response.responseCode,
          message: '请求失败',
          error: `HTTP ${response.responseCode}`
        };
      }
    } catch (error) {
      // 打印完整错误，方便排查
      console.error('HTTP请求错误:', JSON.stringify(error), 'url:', url);
      return {
        code: -1,
        message: '网络错误',
        error: error.message || JSON.stringify(error) || '请求失败'
      };
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 检查网络连接
   */
  async isOnline(): Promise<boolean> {
    await this.ensureInit();
    try {
      const httpRequest = http.createHttp();
      let url = this.baseUrl + 'mobile/health.json';
      const response = await httpRequest.request(url, {
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

  // ============================================
  // 图片下载相关方法
  // ============================================

  private getFilenameFromUrl(url: string): string {
    const urlWithoutParams = url.split('?')[0];
    const parts = urlWithoutParams.split('/');
    let filename = parts[parts.length - 1];
    if (!filename.includes('.')) {
      filename += '.jpg';
    }
    return filename || `image_${Date.now()}.jpg`;
  }

  async downloadImage(imageUrl: string, saveDir: string): Promise<string | null> {
    await this.ensureInit();
    try {
      let fullUrl = imageUrl;
      if (!imageUrl.startsWith('http')) {
        fullUrl = this.baseUrl + imageUrl;
      }

      console.log(`📥 开始下载图片: ${fullUrl}`);

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(fullUrl, {
        method: http.RequestMethod.GET,
        header: { 'token': this.token },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      httpRequest.destroy();

      if (response.responseCode !== 200) {
        console.error(`❌ 下载失败，状态码: ${response.responseCode}`);
        return null;
      }

      try {
        if (!fileIo.accessSync(saveDir)) {
          fileIo.mkdirSync(saveDir);
        }
      } catch (e) {
        fileIo.mkdirSync(saveDir);
      }

      const filename = this.getFilenameFromUrl(imageUrl);
      const localPath = `${saveDir}/${filename}`;

      const file = fileIo.openSync(
        localPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      fileIo.writeSync(file.fd, response.result as ArrayBuffer);
      fileIo.closeSync(file);

      console.log(`✅ 图片已保存: ${localPath}`);
      return localPath;
    } catch (e) {
      console.error(`❌ 下载图片失败 (${imageUrl}):`, e);
      return null;
    }
  }

  async downloadImages(imageUrls: string[], saveDir: string): Promise<Map<string, string>> {
    const resultMap = new Map<string, string>();
    console.log(`📥 开始批量下载 ${imageUrls.length} 张图片`);

    for (let i = 0; i < imageUrls.length; i++) {
      const url = imageUrls[i];
      console.log(`📥 [${i + 1}/${imageUrls.length}] 下载: ${url}`);
      const localPath = await this.downloadImage(url, saveDir);
      if (localPath) {
        resultMap.set(url, localPath);
      }
    }

    console.log(`✅ 批量下载完成: ${resultMap.size}/${imageUrls.length} 成功`);
    return resultMap;
  }
}

// 导出单例（构造时自动开始初始化）
export default new HttpUtil();