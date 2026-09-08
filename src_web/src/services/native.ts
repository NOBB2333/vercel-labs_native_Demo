/** 模板后端命令返回的健康状态。 */
export interface BackendHealth {
  status: "ok";
  app: string;
  version: string;
  requestCount: number;
}

/** Native SDK 注入到 WebView 的最小 Bridge 接口。 */
export interface NativeBridge {
  invoke<T>(command: string, payload?: unknown): Promise<T>;
}

declare global {
  interface Window {
    zero?: NativeBridge;
  }
}

/** 判断当前页面是否由原生壳承载。 */
export function hasNativeBridge(): boolean {
  return typeof window.zero?.invoke === "function";
}

/** 通过类型化的前端/原生边界请求进程健康状态。 */
export async function getBackendHealth(): Promise<BackendHealth> {
  if (!window.zero) throw new Error("Native bridge is not available");
  return window.zero.invoke<BackendHealth>("app.health");
}
