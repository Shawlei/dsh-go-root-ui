# dsh-go Root UI

> 给 proot 运行环境递 root 的 KernelSU / SukiSU / Magisk 模块，自带 WebUI 控制台。

![version](https://img.shields.io/badge/version-1.1.0-blue.svg)
[![stars](https://img.shields.io/github/stars/Shawlei/dsh-go-root-ui?style=flat)](https://github.com/Shawlei/dsh-go-root-ui/stargazers)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/Android-KernelSU%20%7C%20SukiSU%20%7C%20Magisk-3ddc84.svg)](#兼容性)

手机上跑 proot 类 Linux 环境（dsh-go、Termux proot-distro 等）时，容器里的 `uid=0` 是 proot 的
`-0` 参数伪造出来的，真实的 root 能力它拿不到。本模块在**手机侧**开一个只监听回环地址的 root
守护，把执行结果递进容器，并提供模块自带的 WebUI 用来操作。

```
容器 (uid 10306)  ──HTTP/token──▶  127.0.0.1:7000 (root, u:r:ksu:s0)  ──▶  真正执行
        ▲                                                                     │
        └────────────────────  stdout / stderr  ──────────────────────────────┘
```

## 特性

- **一行命令拿 root**：装好后容器里直接 `r id` → `uid=0(root)`
- **模块自带 WebUI**：管理器里点开就能执行命令、看状态、查日志、换 token
- **零配置**：自动发现 proot 的 rootfs 目录与 App uid，不写死包名
- **开机自启**：`service.sh` 拉起守护，断网/关屏都不影响
- **失败可自愈**：管理器没注入 JS 桥时，页面自动跳到守护自己的 HTTP 页面
- **小体积、纯 shell**：守护用 toybox `nc -L` + 手写 HTTP/1.1，没有额外二进制、没有 Node/Python 依赖
- **能修属主**：`rfix` 一条命令把 root 写出来的文件交还给 App，避免引擎读不了自己的文件

## 为什么容器里不能直接用 su

KernelSU / SukiSU 的 `su` 不是磁盘上的文件，而是内核在 `execve` 上的钩子：

```
stat /system/bin/su   →  size=5326360  mode=755
dd   /system/bin/su   →  0 bytes copied      ← 一个字节都读不出来
/system/bin/su -c id  →  uid=0                ← execve 时才被拦截
```

而 proot 必须先 `open()` 读到 ELF 才决定怎么 `exec`，第一步就是 `ENOENT`，钩子根本没机会触发。
所以 `su` 永远进不了容器，只能让外面的进程执行。详见 [docs/why-proot-cannot-su.md](docs/why-proot-cannot-su.md)。

## 安装

1. 管理器（KernelSU / SukiSU / Magisk）里刷入 `dshgo_rootui-<version>.zip`
2. 重启手机（或手动跑一次 `su -c 'sh /data/adb/modules/dshgo_rootui/bin/rootd.sh'`）
3. 管理器 → 模块 → **dsh-go Root UI** → **WebUI**

装好之后容器里会自动出现：

```bash
r id              # uid=0(root) gid=0(root) context=u:r:ksu:s0
```

> 如果 WebUI 显示「通道未通」，说明管理器没注入 `ksu` 桥且守护没起来。
> 页面会给出一键入口；实在不行重启一次手机。

## 用法

### WebUI

| 区域 | 作用 |
|---|---|
| 状态 | 运行身份、设备、SELinux 域、容器客户端是否安装 |
| 命令 | 输入框 + 常用命令胶囊，`Ctrl/⌘ + Enter` 执行，输出可复制 |
| 更新客户端 | 重新把 `r` / `rfix` 写进 rootfs（换 token 后必须点） |
| 日志 | 守护最近 80 行 |
| 换 token | 重置 token 并自动同步容器客户端 |

### 容器里

```bash
r id                          # 单条命令
r ls /data/adb/modules
r - <<'X'                      # 多行脚本
getprop ro.product.model
ls /data/adb/modules/*/module.prop
X
rfix /root/.dsh               # 把 root 写的文件属主交还 App
```

**路径注意**：`r` 里的路径是**手机侧**路径（`/data/adb`、`/sdcard`、`/system`），
不是容器路径。容器 `/` 对应手机侧 `<app>/files/runtime/rootfs`，要让 root 写进容器可见的位置，
就写到这个前缀下，再 `rfix`。

## HTTP API

守护默认 `127.0.0.1:7000`（可用 `DSHGO_PORT` 改），除 `/api/ping` 外都需要 token。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/ping` | 存活探测，返回 `pong` |
| GET | `/api/status` | `key=value` 多行：uid / model / android / context / rootfs / client / port |
| GET | `/api/log?lines=80` | 守护日志尾部（上限 500 行） |
| POST | `/api/exec` | 请求体即命令，返回 stdout+stderr，退出码在 `X-Exit-Code` |
| POST | `/api/rfix` | 请求体是容器内路径（空格分隔），交还属主 |
| POST | `/api/resync` | **无需 token**，把当前 token 重新写进目标 App 的 rootfs 客户端（自愈用） |

```bash
TOK=$(cat /data/adb/dshgo_rootui/token)
curl -s "http://127.0.0.1:7000/api/status?token=$TOK"
curl -s -X POST --data-binary 'id' "http://127.0.0.1:7000/api/exec?token=$TOK"
```

## 安全模型

- 守护只 bind `127.0.0.1`，不接受外部连接。
- token 32 位十六进制，存于 `/data/adb/dshgo_rootui/token`（`0600 root`），普通 App 读不到。
- WebUI 页面由管理器从 `/data/adb/modules/...` 加载，同样仅 root 可读。
- 守护**不会**把 token 暴露在页面上：`GET /` 只返回静态 HTML，读 token 需要文件权限或已认证请求。
- **能读到 token 的进程等价于 root**：手机上任何能读该文件或能访问回环 + 拿到 token 的东西都能执行命令。
  不要装来路不明的 App，不要把 token 贴到聊天/截图里。
- 通过 `r` 写的文件属主是 `0:0`；写进 `/root`、rootfs 的 `0600` 文件会让 App 之后读不了，记得 `rfix`。

## 兼容性

| 环境 | 状态 |
|---|---|
| SukiSU Ultra（KernelSU 分支） | 已实测（Android 17 / arm64） |
| KernelSU / KernelSU Next | 理论兼容（同一套模块与 WebUI 规范） |
| Magisk | 模块可装；Magisk 管理器没有 WebUI，页面需用浏览器打开 `http://127.0.0.1:7000/` |
| APatch | 同 Magisk |

WebUI 里依次探测 `ksu` / `$ksu` / `kernelsu` / `$kernelsu` / `ksuAPI` 五种桥名，
都找不到时回退到 HTTP。不同实现的原生桥回调签名不一样，前端已统一归一化：

| 签名 | 来源 |
|---|---|
| `(stdout, stderr)` | KernelSU 官方 npm 包 |
| `(errno, stdout, stderr)` | SukiSU 实测 |
| `(errno, stdout)` | 部分分支 |

返回 Promise 或直接返回对象也能识别。

## 目录结构

```
module.prop                      模块信息
customize.sh                     安装期：落盘 / 生成 token / 注入 / 权限
post-fs-data.sh                  开机早期：确保 token 存在
service.sh                       开机后：拉起守护
uninstall.sh                     卸载：停守护、清数据
bin/common.sh                    路径发现、token、日志（被其他脚本引用）
bin/rootd.sh                     启动 127.0.0.1 守护 + 自装客户端
bin/handler.sh                   每连接一个实例的 HTTP/1.1 实现
bin/install-client.sh            把 r / rfix 写进 rootfs
bin/rotate.sh                    换 token 并同步客户端
bin/client.sh                    容器里的 r 客户端
bin/client-rfix.sh               容器里的 rfix 客户端
webroot/index.html               页面骨架
webroot/app.js                   前端逻辑（双通道）
webroot/style.css                样式
META-INF/…/update-binary         安装器（Magisk/KSU 通用）
build.sh                         打包：./build.sh → dist/<id>-<ver>.zip
```

## 开发

```bash
./build.sh                    # 打包到 dist/
```

发布流程：

```bash
./build.sh                       # 本地打包
git tag v1.1.0 && git push origin v1.1.0
```

推 `v*` tag 后，GitHub Actions 会自动 `./build.sh` 打包并把 zip 挂到 Release 上；
也可以在 Actions 页手动 Run workflow，只产出 artifact。

## English

A KernelSU/SukiSU/Magisk module that gives **proot-based Linux environments** (dsh-go, etc.)
access to real root, plus a module WebUI.

The container's `uid=0` is proot's fake root; KernelSU's `su` is a kernel `execve` hook with no
readable file, so `open()` fails before `exec()` ever happens. This module runs a loopback-only
root daemon on the phone side and hands results back into the container.

After install: `r id` → `uid=0(root)`. WebUI: module card → WebUI. API on `127.0.0.1:7000`, token at
`/data/adb/dshgo_rootui/token`.

## 链接

- 仓库：<https://github.com/Shawlei/dsh-go-root-ui>
- 问题反馈：<https://github.com/Shawlei/dsh-go-root-ui/issues>

## License

[MIT](LICENSE)
