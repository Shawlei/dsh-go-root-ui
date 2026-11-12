# 为什么 proot 容器里用不了 su

一句话：**KernelSU/SukiSU 的 `su` 是内核 `execve` 钩子，不是磁盘文件；而 proot 必须先 `open()`
读到文件内容才决定怎么 `exec`，所以第一步就失败了。**

## 实测证据

在搭载 SukiSU 的 Android 17（arm64）上，从 dsh-go 的 proot 容器里：

```console
$ id
uid=0(root) gid=0(root)          # 假的

$ grep Uid /proc/self/status
Uid:	10306	10306	10306	10306   # 真实：App uid

$ cat /proc/self/attr/current
u:r:untrusted_app_27:s0:c50,c257,c512,c768

$ stat /system/bin/su
  size=5326360  mode=755  inode=808143     # 看起来像个 5MB 的可执行文件

$ dd if=/system/bin/su of=/dev/null bs=1 count=1
0 bytes copied                            # 一个字节都读不出来

$ /system/bin/su -c id
bash: /system/bin/su: cannot execute: required file not found

$ ls /system/bin/su
/system/bin/su                            # ls -l 能看到，但 readdir 里没有它
```

而以 root 身份（`u:r:ksu:s0`）执行同样的 `su` 是正常的：

```console
$ su -c 'id'
uid=0(root) gid=0(root) context=u:r:ksu:s0
```

## 机制

1. **KernelSU 的 su 是内核钩子**
   `ksu_handle_execveat()` 在内核层拦截对 `su` 路径的 `execve`，直接给调用者换掉 uid/domain。
   磁盘上并不存在可读的实体文件 —— `stat()` 能返回元数据（虚拟节点），`open()`/`read()` 却拿不到内容。

2. **proot 的启动流程**
   proot 用 `ptrace` 接管子进程的每个系统调用，把容器路径翻译成宿主路径。执行一个程序时，它需要
   **先 `open()` 读取 ELF 头**，判断架构、决定是否走 qemu、重写 interpreter 路径等。

3. **两者顺序冲突**
   `open("/system/bin/su")` 在内核里被解析到不存在的实体 → `ENOENT`。
   内核的 `execve` 钩子只对真正的 `execve` 生效，`open` 阶段轮不到它。
   `execve` 根本走不到，钩子也就永远不会触发。

同样的道理适用于：

- Magisk 的 `su`（symlink 到 `magisk` 单文件，被 magic mount 隐藏）
- 通过 `LD_PRELOAD` / `ptrace` 注入去 `setuid(0)`：SELinux 的 `untrusted_app` 域不允许转换到
  `kernel`/`su` 域，系统调用直接返回 `EPERM`

## 正确的做法

**别让容器去"获得"root，而是把 root 的执行结果"递"进来。**

```
容器进程 (uid 10306)
   │  HTTP POST /api/exec  + token
   ▼
守护进程 (uid 0, u:r:ksu:s0)   ← 由模块在开机时用 root 拉起
   │  /system/bin/sh -c "<命令>"
   ▼
stdout / stderr → 回传容器
```

守护进程本身就是 root 上下文（模块由 root 管理器在 `service.sh` 阶段启动），所以它执行任何命令
都带 root 身份，不需要再经过 `su`。

这也是本模块的架构：

| 组件 | 角色 |
|---|---|
| `service.sh` → `rootd.sh` | 开机时以 root 拉起监听 |
| `bin/handler.sh` | 每个连接一个实例，解析 HTTP/1.1、校验 token、执行 |
| `bin/client.sh` → `r` | 容器里的客户端，`r <cmd>` 把命令递出去 |

## 顺带的坑

- 通过 root 侧写出的文件属主是 `0:0`。写到容器可见的 rootfs 里（`<app>/files/runtime/rootfs`）
  之后，App（uid 10306）再读写会失败，甚至导致引擎起不来 —— 所以要有 `rfix`。
- 不要试图把 `su` 拷进 rootfs：它读出来是 0 字节，`cp` 只会得到一个空文件。
