# S5P6818 (X6818) — Ubuntu 26.04 根文件系统构建与部署手册

本仓库提供 **在 x86 主机上构建 arm64 Ubuntu 26.04 LTS (resolute) 根文件系统**，并把它部署到
九鼎 X6818（S5P6818，1 GB RAM / 8 GB eMMC）板子上的完整链路。

> 目标读者：拿到本仓库、手上有一块已经能跑主线 Linux 的 X6818 板子的人。
> 按本文从第 1 节走到第 8 节，即可复现「x86 上构建 → eMMC 落地 → 26.04 正常启动」。
>
> 本手册对应 2026-11 实测环境：内核 `7.2.15+`、u-boot 2016.01、eMMC 布局
> `p2`(754 MiB 中转/救援) + `p7`(5.9 GiB 最终根)。

---

## 目录

1. 整体链路
2. 前置条件
3. 主机准备：qemu binfmt
4. 构建根文件系统
5. 发布与传输
6. 板子部署
7. 首次启动验证
8. 回滚
9. 踩坑记录（务必先看）
10. 附录

---

## 1. 整体链路

```
┌──────────────── x86_64 主机（Ubuntu 20.04+，有 sudo）───────────────┐
│  qemu-user-static + binfmt_misc（跑 arm64 的 apt/dpkg）            │
│                                                                    │
│  build-2604.sh                                                     │
│    ① 解包 ubuntu-base-26.04.1-base-arm64.tar.gz                    │
│    ② chroot 装包（dropbear/iproute2/chrony/…）                     │
│    ③ 写 init v4、fstab、fw_env.config、DNS 等                      │
│    ④ 打 r2604.tar.gz（约 52 MB）                                   │
│    ⑤ （可选）发布到 HTTP :8000                                     │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ HTTP / scp
┌──────────────────────────────▼─────────────────────────────────────┐
│  X6818 板子（eMMC）                                                 │
│                                                                    │
│  p2 (754 MiB)  ← 先解包到这里，改 u-boot env 从 p2 启动做“真机验证” │
│       │                                                            │
│       └── 验证 OK 后：mkfs p7 → tar 整棵复制 → env 改回 p7          │
│                                                                    │
│  p7 (5.9 GiB)  ← 最终根文件系统（旧 22.04 被替换）                  │
└────────────────────────────────────────────────────────────────────┘
```

为什么不能直接 `mkfs p7`：p7 是正在运行的根，无法自我格式化；必须先用 p2（或 SD 卡）
当临时宿主。p2 验证也是一次真机冒烟测试，失败随时切回 p7。

---

## 2. 前置条件

### 2.1 板子侧（必须已具备）

| 项 | 要求 | 说明 |
|---|---|---|
| 引导 | u-boot 2016.01，能从 eMMC 启动 | `ubootpak` 分区**绝对不要动**（没有 recovery 通道） |
| 内核 | 主线 `7.2.15+`，`booti` 可启动 | 由另一仓库 `S5p6818-kernel` 构建，或从现有板子 `/boot` 取 |
| 现有根 | eMMC `p7` 上有一套能起来的 22.04 | 作为回滚与操作入口 |
| 中转分区 | eMMC `p2`（约 690 MB 可用） | 本手册用 p2 做中转；没有的话可用 SD 卡 |
| 串口 | `ttySAC0` 115200 | 首次启动看 log / 救砖唯一通道 |
| 网络 | 能访问构建主机（HTTP） | 板子静态 IP 由 init 配 |

需要准备的 4 个文件（**不在本仓库**，必须从现有板子或内核仓库取）：

```sh
/boot/Image                                   # 内核（约 60 MB）
/boot/dtb/nexell/s5p6818-x6818.dtb            # 设备树（约 19 KB）
/usr/local/bin/x6818-diag                     # 静态小工具：配 IP / 路由（init 依赖它）
/root/.ssh/authorized_keys                    # 你的公钥（没有就只能串口进）
```

> `x6818-diag` 很关键：init 用它把 eth0 配起来。没有它 → 板子起得来但没网，只能串口操作。
> 源码/二进制从原项目仓库取，或 `scp root@原板:/usr/local/bin/x6818-diag .`

### 2.2 主机侧

| 项 | 要求 |
|---|---|
| 系统 | x86_64 Ubuntu 20.04 / 22.04 / 24.04，有 `sudo` |
| 磁盘 | 至少 2 GB 空闲（解包 ~160 MB + 装包 ~500 MB + tar 52 MB） |
| 软件 | `qemu-user-static >= 6`、`binfmt-support`、`wget/curl/tar/gzip/python3` |
| 网络 | 能访问 `cdimage.ubuntu.com` 和清华 `ubuntu-ports` 镜像 |

---

## 3. 主机准备：qemu binfmt

### 3.1 检查是否可用

```sh
qemu-aarch64-static --version        # 需要 >= 6；4.x 会段错误
cat /proc/sys/fs/binfmt_misc/qemu-aarch64   # 需要 enabled，interpreter 指向 qemu-aarch64-static
```

### 3.2 如果只有 4.2（Ubuntu 20.04 默认）

症状：`chroot` 进 26.04 报 `qemu: uncaught target signal 11 (Segmentation fault)`。
原因：26.04 的二进制带 **BTI/PAC** 分支保护，qemu 4.2 不认识。

处理（不需要加 apt 源，直接换静态二进制）：

```sh
cd /tmp
wget http://mirrors.tuna.tsinghua.edu.cn/ubuntu/pool/universe/q/qemu/qemu-user-static_8.2.2+ds-0ubuntu1.16_amd64.deb
mkdir -p /tmp/q8 && dpkg-deb -x qemu-user-static_8.2.2+ds-0ubuntu1.16_amd64.deb /tmp/q8

# 先注销 binfmt（否则内核 F 标志钉住旧文件，覆盖会报 "文本文件忙"）
sudo update-binfmts --disable qemu-aarch64
sudo mv /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static.bak-4.2
sudo cp /tmp/q8/usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static
sudo chmod 755 /usr/bin/qemu-aarch64-static
sudo update-binfmts --enable qemu-aarch64

qemu-aarch64-static --version       # 期望 8.2.2
```

> 这是手动覆盖包管理的文件，以后 `apt upgrade qemu-user-static` 会盖回去，需要重做。

---

## 4. 构建根文件系统

```sh
git clone <本仓库> S5p6818-rootfs
cd S5p6818-rootfs
sudo bash build-2604.sh --clean --publish
```

### 4.1 参数与环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `WORKDIR` | 脚本所在目录 | 构建工作目录（`r2604/`、tar、日志都放这） |
| `PUBDIR` | `<OWNER 家目录>/2026workspace/out` | `--publish` 的发布目录 |
| `HOST_IP` | `hostname -I` 第一个 | 打印 URL 用 |
| `ROOTDEV` | `/dev/mmcblk2p2` | 写进 fstab 的目标设备；装 p7 时传 `/dev/mmcblk2p7` |
| `MIRROR` | 清华 `ubuntu-ports` | apt 源 |
| `OWNER` | sudo 发起用户 | 产物属主 |

示例（产物不落在 git 仓库里）：

```sh
sudo WORKDIR=$HOME/build-2604 bash build-2604.sh --clean --publish
```

### 4.2 脚本做了什么

| 步骤 | 内容 |
|---|---|
| 0 | 检查 root / 架构 / qemu 版本 / 磁盘 ≥ 2 GB |
| 1 | 下载 base tarball 并校验 sha256（`SHA256SUMS` 用 `*文件名` 格式，脚本已处理） |
| 2 | 解包到 `$WORKDIR/r2604`（`--numeric-owner`）；先卸载残留挂载，防止 `rm -rf` 误删宿主机 `/dev` |
| 3 | bind 挂载 `/dev /proc /sys /dev/pts`，退出时反序卸载 |
| 4 | 写 DNS（不用宿主机 127.0.0.53）、`policy-rc.d`（禁服务启动）、deb822 源、apt 防 IPv6/时钟选项 |
| 5 | `apt-get update` |
| 6 | 装包：dropbear、iproute2、ethtool、kmod、procps、less、nano、util-linux(-extra)、e2fsprogs、fdisk、rsync、netbase、iputils-ping、logrotate、tzdata、chrony、ca-certificates、wget、u-boot-tools |
| 7 | 写 init v4；删 systemd 的 OSC 3008 钩子；写 hostname/hosts/fstab/fw_env.config |
| 8 | chroot 冒烟（os-release、uname、dropbear、apt 模拟安装） |
| 9 | 反序卸载，`tar --numeric-owner --one-file-system` 打包 |
| 10 | `--publish`：复制到 `PUBDIR`，没起服务就 `python3 -m http.server 8000` |

### 4.3 产物

```
r2604.tar.gz          ~52 MB（解包后约 160 MB 文件 / 230 MB 占用）
r2604.tar.gz.sha256   sha256 校验
build-2604.log        完整日志
```

`r2604.tar.gz` 是**纯用户态**：不含内核、dtb、diag、公钥、引导器。这些在板子侧补。

---

## 5. 发布与传输

```sh
# 方式 A：--publish（推荐）
sudo bash build-2604.sh --clean --publish
# 输出 URL: http://<HOST_IP>:8000/r2604.tar.gz

# 方式 B：手动 scp
scp r2604.tar.gz root@<板子IP>:/tmp/
```

板子上先校验再解包：

```sh
wget -qO- http://<HOST_IP>:8000/r2604.tar.gz.sha256     # 对比 r2604.tar.gz 的 sha256sum
```

---

## 6. 板子部署

### 6.1 准备（在现有 22.04 上）

```sh
# 装 u-boot 工具并写对 env 配置（大小必须是 0x1000，错一个字节 CRC 就失败）
apt install -y u-boot-tools e2fsprogs
printf '/dev/mmcblk2 0x80000 0x1000\n' > /etc/fw_env.config
fw_printenv | head          # 必须能打印 bootcmd/bootargs
fw_printenv > /root/env-2204.txt    # 备份

# 确认 p2 没被占用
findmnt /dev/mmcblk2p2 || echo "p2 未挂载，可以格式化"
```

> 若 `fw_printenv` 报 `Cannot read environment`，说明 `fw_env.config` 的 size 不对。
> 本板实测为 `0x1000`（4 KB），可用 CRC 反推：读 `0x80000` 起 256 KB，
> 对 `data[4:N]` 算 CRC32 与头部 4 字节比对，命中的 N 就是 env 区长度。

### 6.2 把 26.04 装进 p2（中转 + 真机验证）

```sh
# 1) 格式化 p2（ext4 特性必须能被 2016 年的 u-boot 读取）
mkfs.ext4 -m 1 -O ^64bit,^metadata_csum -L ub2604 /dev/mmcblk2p2

# 2) 流式解包（不落中间文件）
mkdir -p /mnt/p2 && mount /dev/mmcblk2p2 /mnt/p2
wget -qO- http://<HOST_IP>:8000/r2604.tar.gz | tar -C /mnt/p2 -xzpf - --numeric-owner
du -shx /mnt/p2              # 约 230 MB，p2 有 690 MB，足够

# 3) 补板子专属文件
mkdir -p /mnt/p2/boot/dtb/nexell /mnt/p2/usr/local/bin /mnt/p2/root/.ssh
cp /boot/Image /mnt/p2/boot/
cp /boot/dtb/nexell/s5p6818-x6818.dtb /mnt/p2/boot/dtb/nexell/
cp /usr/local/bin/x6818-diag /mnt/p2/usr/local/bin/ && chmod 755 /mnt/p2/usr/local/bin/x6818-diag
cp /root/.ssh/authorized_keys /mnt/p2/root/.ssh/ && chmod 600 /mnt/p2/root/.ssh/authorized_keys
chown -R root:root /mnt/p2/root /mnt/p2/usr/local/bin
# fstab 已在 tar 里写成 p2，不用改
sync && umount /mnt/p2

# 4) 临时从 p2 启动
fw_setenv bootcmd 'ext4load mmc 0:2 0x41000000 /boot/Image; ext4load mmc 0:2 0x48000000 /boot/dtb/nexell/s5p6818-x6818.dtb; booti 0x41000000 - 0x48000000'
fw_setenv bootargs 'console=ttySAC0,115200n8 earlycon=s5pv210,mmio32,0xc00a1000 root=/dev/mmcblk2p2 rootwait rootfstype=ext4 rw nr_cpus=4'
fw_printenv bootcmd bootargs
sync; echo s > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger
```

> 板上没有 `reboot` 命令，用 `sysrq`。
> `nr_cpus=4` **不能删**（2016 年 u-boot 没开 cluster1 的 CCI snoop）。

### 6.3 验证通过后，落到 p7

```sh
# 确认已经跑在 26.04 / p2 上
. /etc/os-release; echo "$PRETTY_NAME"; findmnt -o SOURCE -n /

# 1) 格式化 p7（26.04 的 e2fsprogs 1.47，多关两个新特性最稳）
mkfs.ext4 -m 1 -O ^64bit,^metadata_csum,^metadata_csum_seed,^orphan_file -L ub2604 /dev/mmcblk2p7

# 2) 整棵复制 p2 -> p7
mkdir -p /mnt/p7 && mount /dev/mmcblk2p7 /mnt/p7
sync
tar -C / -cpf - --one-file-system --numeric-owner --exclude=./mnt . | tar -C /mnt/p7 -xpf - --numeric-owner
mkdir -p /mnt/p7/{proc,sys,dev,tmp,run,mnt}
chmod 1777 /mnt/p7/tmp
chown -R root:root /mnt/p7/root
sed -i 's|/dev/mmcblk2p2|/dev/mmcblk2p7|' /mnt/p7/etc/fstab
grep mmcblk2p7 /mnt/p7/etc/fstab
sync && umount /mnt/p7

# 3) env 改回 p7，重启
fw_setenv bootcmd 'ext4load mmc 0:7 0x41000000 /boot/Image; ext4load mmc 0:7 0x48000000 /boot/dtb/nexell/s5p6818-x6818.dtb; booti 0x41000000 - 0x48000000'
fw_setenv bootargs 'console=ttySAC0,115200n8 earlycon=s5pv210,mmio32,0xc00a1000 root=/dev/mmcblk2p7 rootwait rootfstype=ext4 rw nr_cpus=4'
sync; echo s > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger
```

> 注意：`sed` 改 fstab 那步不能省，否则从 p7 启动时会去挂 p2。
> 从这一步起旧 22.04 就被覆盖了；p2 里保留了一份 26.04 副本，可当救援槽。

### 6.4 u-boot env 速查

| 槽 | bootcmd | root |
|---|---|---|
| p2 | `ext4load mmc 0:2 ... /boot/Image` | `/dev/mmcblk2p2` |
| p7 | `ext4load mmc 0:7 ... /boot/Image` | `/dev/mmcblk2p7` |

u-boot 侧 `mmc 0:N` = Linux 侧 `/dev/mmcblk2pN`。

---

## 7. 首次启动验证

串口接好，看到 `--- x6818: Ubuntu 26.04 up, serial console ttySAC0 ---` 后：

```sh
cat /etc/os-release                 # Ubuntu 26.04.1 LTS (resolute)
uname -r                            # 7.2.15+
findmnt -o SOURCE,FSTYPE -n /       # /dev/mmcblk2p7 ext4
df -h /                             # 约 5.9G，已用 ~450M
free -m
ip -4 a; ip r                       # 192.168.31.150/24 + 默认路由
ssh root@<板子IP>                   # dropbear 免密
apt update                          # 26.04 apt 正常
date                                # 预期自动校准到当前时间（NTP）
dmesg | grep -iE 'error|fail|panic'
```

期望的「正常噪音」（不是错误）：

- `arch_timer: No interrupt available, giving up` + `Failed to initialize '/timer': -22`
  → DT 里 armv8 timer 没配中断，内核回落到 `samsung_clocksource_timer`
- `debconf: unable to initialize frontend: Readline` → 缺 perl `Term::ReadLine`，apt 自动退回 Teletype

---

## 8. 回滚

任何时候只要 u-boot 还能进命令行，改 env 即可：

```sh
# 回滚到 p2（26.04 副本）
fw_setenv bootcmd 'ext4load mmc 0:2 0x41000000 /boot/Image; ext4load mmc 0:2 0x48000000 /boot/dtb/nexell/s5p6818-x6818.dtb; booti 0x41000000 - 0x48000000'
fw_setenv bootargs 'console=ttySAC0,115200n8 earlycon=s5pv210,mmio32,0xc00a1000 root=/dev/mmcblk2p2 rootwait rootfstype=ext4 rw nr_cpus=4'

# 回滚到 p7（旧 22.04，仅在 6.3 之前有效）
fw_setenv bootargs 'console=ttySAC0,115200n8 earlycon=s5pv210,mmio32,0xc00a1000 root=/dev/mmcblk2p7 rootwait rootfstype=ext4 rw nr_cpus=4'
```

最坏情况：串口 → u-boot 提示符 → `setenv` / `saveenv` 手动改。
**`ubootpak` 分区、`boot0/boot1`、前 1 MiB 裸区永远不要写。**

---

## 9. 踩坑记录（务必先看）

### 9.1 构建阶段

| 现象 | 原因 | 解决 |
|---|---|---|
| `qemu: uncaught target signal 11` | qemu 4.2 不认识 26.04 的 BTI/PAC 指令 | 换成 8.2 静态二进制（见 3.2） |
| `cp: 无法创建 '/usr/bin/qemu-aarch64-static': 文本文件忙` | binfmt 的 `F` 标志把旧文件钉住 | 先 `update-binfmts --disable`，换完再 `--enable` |
| `tar: 无法识别的选项 "--numeric-ids"` | `--numeric-ids` 是 rsync 的，tar 用 `--numeric-owner` | 改参数 |
| `tar: *ubuntu-base-...: 无法 open` | `SHA256SUMS` 格式是 `<hash> *<file>` | 用 awk 去掉 `*` 再比 |
| `sha256sum -c` 报 26.04 文件不存在 | SUMS 同时列了 26.04 和 26.04.1 | 只挑当前文件名 |
| `du: cannot access .../r2604/proc/...` 后脚本退出 | `du` 跨进 bind 的 `/proc`，进程 fd 消失导致非 0；`pipefail` 直接退出 | 用 `du -x` 不跨文件系统 |
| `umount: .../r2604/dev: target is busy` | 卸载顺序错（先父后子） | 反序：`dev/pts` → `sys` → `proc` → `dev` |
| `rm -rf r2604` 删到宿主机 `/dev` | 残留 bind 挂载时递归删除 | 脚本先卸载并做安全检查 |

### 9.2 板子阶段

| 现象 | 原因 | 解决 |
|---|---|---|
| `fw_printenv: command not found` | 26.04 base 不带 u-boot-tools | `apt install u-boot-tools` |
| `Cannot read environment, using default` | `fw_env.config` 的 size 不对 | 本板是 `0x80000 0x1000` |
| SSH 密码登不上 | ubuntu-base 的 root 是锁定态（`root:*`） | `echo 'root:root' \| chpasswd`，或改用密钥 |
| SSH 密钥被拒（22.04 迁移时） | tar 解包后 `/root` 属主是 1000:1000，dropbear StrictModes 拒绝 | `chown root:root /root`；脚本 init 里也有兜底 |
| 启动后不响 / 没网 | 忘了拷 `x6818-diag`，init 跳过网络配置 | 补齐 diag 或串口手动配 IP |
| `Kernel panic: No init found` | `/sbin/init` 不存在 | usrmerge 下确认 `/sbin/init -> /usr/sbin/init` |
| 串口满屏 `]3008;start=...` | systemd 259 的 OSC 3008 shell 集成，串口终端不认 | 删 `/etc/profile.d/80-systemd-osc-context.sh`、`70-systemd-shell-extra.sh`，mask `tmpfiles.d` |
| `date` 显示 2072 年 | RTC 无电池，冷启动寄存器是垃圾值 | init 里 NTP 校准 + `hwclock -w`（脚本已内置） |
| apt 卡住 / HTTPS 证书失效 | 时钟错 | 先校时；apt 全程 HTTP 源 |
| Ctrl-C 导致 `Attempted to kill init` | init `exec agetty`，PID1 被替换 | init 必须是 PID1，循环拉 getty（脚本已实现） |

---

## 10. 附录

### 10.1 为什么不用 `do-release-upgrade`

- 本板 PID1 是自写 `/usr/sbin/init`，不是 systemd，升级期 maintainer 脚本大量失败；
- 22.04 → 26.04 要跳两个 LTS，每跳一次重启；
- 8 GB eMMC 空间紧张，升级峰值要 +1.5 GB；
- 就地升级**没有回滚**。本手册的方案全程保留旧根，直到最后一步才覆盖。

### 10.2 A/B 双根方案（可选）

若想同时保留 22.04 与 26.04：重排分区为 `p1 boot 64M + p2 root-A + p3 root-B`，
u-boot env 切换槽位。代价：一次分区重排 + 两次数据复制。
本手册采用的是「p2 中转 → p7 最终」的更简单路径。

### 10.3 ext4 特性与老 u-boot

2016 年的 u-boot ext4 驱动不认 `64bit` / `metadata_csum` / `metadata_csum_seed` / `orphan_file`。
格式化根分区（u-boot 要读 `/boot`）时必须关掉：

```sh
# 22.04 的 e2fsprogs 1.46 只能关前两个
mkfs.ext4 -O ^64bit,^metadata_csum ...
# 26.04 的 1.47 再加两个
mkfs.ext4 -O ^64bit,^metadata_csum,^metadata_csum_seed,^orphan_file ...
```

### 10.4 init v4 的职责

| 功能 | 说明 |
|---|---|
| 挂载 `/proc /sys /dev/pts /tmp` | 基础文件系统 |
| 静态 IP + 默认路由 | 调 `x6818-diag netup/route` |
| DNS | 写 `223.5.5.5` / `119.29.29.29`（不依赖 resolved） |
| 关 IPv6 | 避免 DNS 返回 AAAA 卡住 apt |
| THP=never | 本板开 THP 时 apt 会触发 kernel panic |
| NTP 校时 + 写 RTC | RTC 无电池，冷启动是 2072 年 |
| 启动 dropbear | 密钥登录 |
| `panic=10` | 挂了自己重启 |
| getty 循环 | PID1 保持为 init，避免 Ctrl-C 杀 init |

### 10.5 相关仓库

| 仓库 | 内容 |
|---|---|
| `S5p6818-kernel` | 内核 7.2.15+、DT `s5p6818-x6818.dts`、AXP228 支持 |
| `S5p6818-rootfs`（本仓库） | 构建脚本、基础文档 |
| 板子原厂资料 | u-boot 2016.01 blob，`ubootpak` 分区，**不要动** |

---

*文档版本：2026-11-21　实测环境：x86_64 Ubuntu 20.04 构建机 + X6818 (S5P6818) 板卡*
