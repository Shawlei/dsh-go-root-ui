# Changelog

## 1.1.1

- 启用 GitHub Actions：推 `v*` tag 自动打包并发布 Release
- 移除 `docs/release-workflow.yml` 重复文件

## 1.1.0

- 重构为通用实现：自动发现 proot rootfs 与 App uid，不再写死包名/uid
- 守护启动时自动安装容器客户端，无需手动点
- 前端拆分为 `index.html` / `app.js` / `style.css`，双通道（原生桥 / HTTP）自动切换
- 管理器未注入 JS 桥时，页面自动探测并跳转到守护页面，不再显示「通道未通」而无解释
- 新增 `/api/rfix`：把 root 写出的文件属主交还 App，客户端不再硬编码路径
- token 轮换后自动同步容器客户端
- HTTP 响应补上 CORS / 缓存控制 / 请求体上限（64 KB）/ 415 与 405 处理
- 日志超过 64 KB 自动截断保留 300 行
- 新增 `build.sh`、GitHub Actions 发布流程、文档

## 1.0.0

- 首个可用版本：root 守护 + WebUI 控制台 + `r` / `rfix` 客户端
