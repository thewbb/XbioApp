/**
 * HTTP 请求工具（支持动态服务器地址）
 */
import http from '@ohos.net.http';
import { ApiResponse } from '../types';
import storage from './storage';
import fileIo from '@ohos.file.fs';

class HttpUtil {
  private token: string = '';
  private baseUrl: string = 'http://172.30.249.228:8080';  // 默认值

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
console.log(url + ":" + JSON.stringify(data))
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

  // ============================================
  // ✅ 新增：图片下载相关方法
  // ============================================

  /**
   * 从 URL 提取文件名
   */
  private getFilenameFromUrl(url: string): string {
    // 移除查询参数
    const urlWithoutParams = url.split('?')[0];
    // 获取最后一段
    const parts = urlWithoutParams.split('/');
    let filename = parts[parts.length - 1];

    // 如果没有扩展名，默认 .jpg
    if (!filename.includes('.')) {
      filename += '.jpg';
    }

    return filename || `image_${Date.now()}.jpg`;
  }

  /**
   * 下载单张图片
   * @param imageUrl 图片 URL（可能是相对路径）
   * @param saveDir 保存目录（绝对路径）
   * @returns 本地文件路径，失败返回 null
   */
  async downloadImage(imageUrl: string, saveDir: string): Promise<string | null> {
    try {
      // 构建完整 URL
      let fullUrl = imageUrl;
      if (!imageUrl.startsWith('http')) {
        fullUrl = this.baseUrl + imageUrl;
      }

      console.log(`📥 开始下载图片: ${fullUrl}`);

      // 创建 HTTP 请求
      const httpRequest = http.createHttp();

      const response = await httpRequest.request(fullUrl, {
        method: http.RequestMethod.GET,
        header: {
          'token': this.token
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 30000
      });

      httpRequest.destroy();

      // 检查响应
      if (response.responseCode !== 200) {
        console.error(`❌ 下载失败，状态码: ${response.responseCode}`);
        return null;
      }

      // 确保目录存在
      try {
        if (!fileIo.accessSync(saveDir)) {
          fileIo.mkdirSync(saveDir);
          console.log(`✅ 创建目录: ${saveDir}`);
        }
      } catch (e) {
        fileIo.mkdirSync(saveDir);
        console.log(`✅ 创建目录: ${saveDir}`);
      }

      // 生成本地文件路径
      const filename = this.getFilenameFromUrl(imageUrl);
      const localPath = `${saveDir}/${filename}`;

      // 保存文件
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

  /**
   * 批量下载图片
   * @param imageUrls 图片 URL 数组
   * @param saveDir 保存目录
   * @returns Map<原始URL, 本地路径>
   */
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

// 导出单例
export default new HttpUtil();