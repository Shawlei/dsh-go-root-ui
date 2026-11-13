# Changelog

## 1.1.4

- 修复 WebUI 状态错位：SukiSU 的原生桥回调是 `(errno, stdout, stderr)`，
  多出的退出码让每行都串了一位（症状：运行身份显示 `1`、SELinux 显示 `17`）
- 桥回调统一归一化，兼容 `(stdout, stderr)` / `(errno, stdout, stderr)` / `(errno, stdout)` / Promise / 对象
- 状态改为按 `key=value` 解析，不再依赖行号
- 「容器客户端」改为检查 rootfs 里的真实路径（此前检查手机侧 `/usr/local/bin`，永远显示未安装）

## 1.1.3

- 修复 token 错位：`customize.sh` 不再预先把 token 烤进 `bin/client.sh`，
  容器客户端一律由 `install-client.sh` 用当时的 token 生成
- 客户端改为运行时读取 `/usr/local/etc/dshgo.token`（rootfs 内、属主为 App、0600），
  换 token 只需重写这个文件，不必重装客户端
- `install-client.sh` 同时写入 token 文件与客户端

## 1.1.2

- 安全修复：`GET /` 不再把 token 注入页面（此前任何能访问回环的 App 都能读到 root 凭证）
- 新增公开端点 `POST /api/resync`：把当前 token 重新写进目标 App 的 rootfs 客户端，
  用于「token 变了但客户端没跟上」的自愈；它只会写进 App 私有目录，别的 App 读不到
- `r` 遇到 401 自动调用 resync 并重试一次
- `rootd.sh` 拒绝以非 root 身份启动（否则读不到 0600 的 token，表现为全部 401）
- `rotate.sh` 同时更新页面里烘入的 token

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
