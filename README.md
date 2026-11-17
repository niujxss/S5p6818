# S5p6818-rootfs — 九鼎 X6818 根文件系统与镜像组装

> 板子：九鼎 X6818（底板 X6818BV3 + 核心板 X4418CV3.4，S5P6818，1 GiB DRAM，8 GB eMMC）
> 作用：存放**根文件系统树**、**u-boot 引导 blob**、以及**组装镜像的脚本**。
> 内核源码不在这里，见姊妹仓库 `../S5p6818-kernel`。

---

## 0. 这个仓库是什么

三层东西合在一起，构成"可启动的 eMMC 内容"：

| 层 | 内容 | 谁提供 |
|---|---|---|
| rootfs | Ubuntu 22.04.5 (arm64) 最小根文件系统，注入过配置 | `base/` 官方 tarball + 本仓库脚本 |
| 内核 | `Image` + `s5p6818-x6818.dtb`，放在 rootfs 的 `/boot/` 里 | 姊妹仓库 `../S5p6818-kernel` 编译产出 |
| 引导 | u-boot 2016.01-armbian（预编译 blob，**不是本仓库编译的**） | `uboot/` |

最终产物是一个 **ext4 镜像**，刷到 eMMC 的 `p2` 分区。
u-boot 从 p2 读 `/boot/Image`，内核再把同一个 p2 当根挂载 —— **内核本质上是 rootfs 里的一个普通文件**。

---

## 1. 目录结构

```
S5p6818-rootfs/
├── README.md                                 本文件
├── .gitignore                                忽略 out/ 与内核产物
├── base/
│   └── ubuntu-base-22.04.5-base-arm64.tar.gz 官方最小 rootfs（27 MB，可复原）
├── rootfs/                                   组装好的根文件系统树（135 MB / 2621 文件）
│   ├── boot/Image                            内核（62.5 MB，git 忽略，脚本注入）
│   ├── boot/dtb/nexell/s5p6818-x6818.dtb     设备树（git 忽略，脚本注入）
│   ├── usr/sbin/init                         自写的最小 init（见 §6）
│   ├── etc/fstab, hostname, apt/sources.list
│   └── ...                                   标准 Ubuntu 目录树
├── uboot/
│   ├── boot-nanopi3-1g.img                   u-boot 完整 blob（523,776 B，来源见 §5）
│   ├── boot-nanopi3-1g-emmc.img              刷 eMMC 用的截断版（491,520 B）
│   ├── 1g-bl1-nanopi.bin                     BL1（28,800 B）
│   ├── 2g-bl1-nanopi.bin                     BL1，2 GiB 内存版本
│   └── ROLLBACK-ubootpak-vendor.bin          原厂 u-boot 存档（341,524 B）
├── init/
│   └── init                                  最小 init 模板（mksystem 注入 /usr/sbin/init）
├── diag/
│   ├── x6818-diag.c                          板上诊断/网络小工具源码
│   └── x6818-diag                            aarch64 静态二进制（交叉编译）
├── scripts/
│   ├── mksystem-x6818.sh                     产出 eMMC(p2) 用的 ext4 镜像  ← 常用
│   ├── mkimage-x6818.sh                      产出 SD 卡完整镜像（本板没用上）
│   ├── build-kernel.sh                       调用姊妹内核仓库编译
│   └── board-enable-ssh.sh                   ★板上跑一次：修 DNS/路由 + 装 openssh + root 公钥
└── out/                                      生成物（git 忽略）
```

---

## 2. 前置条件

- Linux 宿主（本机为 Ubuntu 20.04，`honey` 用户，**全程不需要 root**）
- 打包工具：`mke2fs 1.45+`（要支持 `-d`）、`e2fsprogs`、`openssl`、`python3`、`sfdisk`、`mtools`（可选）
- 编译内核另外需要：`aarch64-linux-gnu-gcc`、`bison`、`flex`、`bc`、`libssl-dev`、`libelf-dev`

检查：

```bash
mke2fs -V && aarch64-linux-gnu-gcc --version | head -1
```

---

## 3. 常用操作

### 3.1 组装 eMMC 镜像（最常用）

```bash
cd scripts
./mksystem-x6818.sh
# 产物：../out/system-p2.img（默认 256 MiB）
```

脚本做的事（幂等，可反复跑）：

1. 若 `rootfs/etc` 不存在或带 `--from-base`，从 `base/*.tar.gz` 解包
2. 注入配置：`/etc/fstab`（root=/dev/mmcblk2p2）、hostname、`resolv.conf`、
   APT 源（清华 ubuntu-ports）、root 口令（*仅当当前为空/被锁时才设*）、
   `/usr/sbin/init`、`/etc/securetty`
3. 从内核树取 `Image` 和 `s5p6818-x6818.dtb`，放进 `rootfs/boot/`
4. `mke2fs -d` 直接从目录生成 ext4（**不需要 mount**）
5. `e2fsck -fn` 校验 + `debugfs` 列出 `/boot`

常用参数（都是环境变量）：

```bash
SIZE_MB=512 ./mksystem-x6818.sh                    # 镜像做 512 MiB
./mksystem-x6818.sh --from-base                     # 丢弃 rootfs/ 重建
KERNEL=/path/to/linux-7.2.15 ./mksystem-x6818.sh    # 指定内核树
OUT=/tmp/x.img ./mksystem-x6818.sh                  # 指定输出
ROOTFS=/tmp/some-tree ./mksystem-x6818.sh           # 打包别的树
```

**没有内核树时**，脚本会沿用 `rootfs/boot/` 里已有的 `Image`/`dtb`，所以本仓库可以独立打包。

### 3.2 编译内核（调用姊妹仓库）

```bash
cd scripts
./build-kernel.sh                                   # Image dtbs
./build-kernel.sh x6818_defconfig                   # 重置配置
KERNEL_DIR=/path/to/linux-7.2.15 ./build-kernel.sh   # 指定内核树
```

内核树默认按顺序找 `../S5p6818-kernel`、`../kernel`、`../linux`。

### 3.3 完整替换流程（改内核 → 出新镜像）

```bash
cd scripts
./build-kernel.sh                     # 编内核（产物在姊妹仓库里）
./mksystem-x6818.sh                   # 重新打包，自动带上新 Image/dtb
```

### 3.4 板子联网 + 开 SSH（一次性）

板子第一次只能走串口。在板上跑 `scripts/board-enable-ssh.sh`（由服务器 HTTP 服务出去，
板上用 `x6818-diag fetch` 取），跑完就能从 PC `ssh root@192.168.31.150`。

```sh
# 服务器：~/2026workspace/out 作为 HTTP 根
cd ~/2026workspace/out && python3 -m http.server 8000 --bind 0.0.0.0 &

# 板子（串口，root）：
/usr/local/bin/x6818-diag fetch 192.168.31.146 8000 /board-enable-ssh.sh /tmp/b.sh
sh /tmp/b.sh

# PC：
ssh root@192.168.31.150
```

脚本做的事（都可逆）：

| 步骤 | 内容 | 为什么 |
|---|---|---|
| 换 diag | 取新版 `x6818-diag` 覆盖 `/usr/local/bin/` | 新版多了 `route` 子命令 |
| DNS | `/etc/resolv.conf` 若指向 `127.0.0.53` 就改成 223.5.5.5 / 119.29.29.29 | ubuntu-base 带的是 systemd-resolved 的桩，板上没有 systemd |
| 路由 | `x6818-diag route 192.168.31.1` | `netup` 只配 IP/掩码，出网段必须有默认路由 |
| 装包 | `apt-get install openssh-server` | 板上没有 ssh |
| 免密 | root 的 `authorized_keys` ← 开发机 `~/.ssh/id_rsa.pub` | root 只许公钥登录 |
| init | `/usr/sbin/init` 换成 v2（DNS/路由/sshd 自启），旧的存 `init.bak` | 板子没有 systemd |

成功后 `/etc/ssh/sshd_config` 是 `PermitRootLogin prohibit-password` + `UsePAM no`。

> 铁律：`x6818-diag netup` 只配 IP 和掩码，**不加默认路由**。没有默认路由时只能访问
> 192.168.31.0/24（HTTP 传文件可以），但 apt 和公网 DNS 全部失败。

---

## 4. 怎么刷进板子

⚠️ **先说结论：现在没有可用的刷机通道。**

这块板子原来靠厂商 u-boot 的 fastboot 刷写，但换成 2016.01 的 u-boot 之后：

- `fastboot 0` 报 `g_dnl_register: failed!, error: -19`（没有可用 UDC）
- 也没有 `tftp` / `dhcp` / `ums`

所以：

| 要更新什么 | 可行方式 |
|---|---|
| 内核 / 设备树 | **HTTP**：`x6818-diag fetch 192.168.31.146 8000 /Image /boot/Image`（见手册 5.6）；优盘仍然可用 |
| rootfs 里的个别文件 | 直接在板子上编辑（rootfs 可写） |
| 装软件 | 有网后 `apt-get install`（前提：默认路由 + 可用 DNS，见 §3.4） |
| **整个 rootfs** | **暂时没有干净通道**，见 §7 待办 |

板子上的 `/boot` 就是本仓库 `rootfs/boot` 的镜像，一一对应。

---

## 5. u-boot 的来源（重要）

`uboot/boot-nanopi3-1g.img` **不是本仓库或任何本地工程编译出来的**，它是
[Armbian build 框架](https://github.com/armbian/build.git) 里的预编译 blob：

| 项 | 值 |
|---|---|
| 仓库 | `https://github.com/armbian/build.git` |
| 提交 | `c3aea3a49`（2026-09-11） |
| 仓库内路径 | `packages/blobs/nanopi/boot-nanopi3-1g.img` |
| 内容 | BL1 + NSIH 头 + 2ndboot + u-boot **2016.01-armbian**（Feb 03 2021 构建） |
| 完整大小 | 523,776 B |
| 刷入大小 | **491,520 B**（尾部 32,256 B 全为 0，而 `ubootpak` 分区只有 0x78000=480 KiB） |

Armbian 在配置注释里说明了为什么用它：主线 u-boot v2026.07 的 S5P6818 移植**冷启动会反复重启**；
2016.01 那个 fork 又**在现代主机上编不过**（host tools 与系统 libfdt 冲突）。
所以官方自己也是从已知good的板子上抓取的二进制。

`1g` / `2g` 对应 1 GiB / 2 GiB DRAM。本板 1 GiB，用 `1g`。

**别再动 `ubootpak` 分区**：刷不回去（没有 fastboot），坏了只能走
`s5p6818开发板/tools/IROM_Fusing_ToolV2.0.zip` 的 iROM 级 USB 恢复。

---

## 6. 根文件系统的特殊之处

### 6.1 为什么这么小

`base/` 是 Ubuntu 官方**最小骨架**：解压 135 MB / 2621 文件，
只有 bash、coreutils、apt/dpkg、libc 等。**没有** systemd、内核模块、文档、man、固件、编译工具链。
对比完整 Ubuntu Server 约 2.5 GB。

要长大就靠 apt（需网络，见 §7 第 1 项）。

### 6.2 为什么自己写 init

`ubuntu-base` 的 tarball 里**没有 `systemd` 二进制**（只有 unit 文件），
所以内核按 `/sbin/init`→`/etc/init`→`/bin/init`→`/bin/sh` 逐级回退，最后掉进一个没有 tty 的裸 shell。

因此写了 `/usr/sbin/init`（27 行）：挂 proc/sys/devpts/tmpfs、设 hostname，
然后 `agetty -L -a root 115200 ttySAC0 vt100` —— 串口自动登录 root。

### 6.3 ext4 特性必须受限

`mke2fs` 新版默认会加 `64bit` 和 `metadata_csum`，而
**u-boot 2016.01 的 ext4 驱动读不了这两项**（会直接认为不是合法 ext4）。
两个脚本都显式带：

```
mke2fs -O ^64bit,^metadata_csum,^metadata_csum_seed -I 256
```

改脚本时**不要去掉这三个 `^`**。

---

## 7. 已知问题 / 待办

| # | 问题 | 影响 |
|---|---|---|
| 1 | ~~网口 PHY 未识别~~ | **已解决**（2026-11-17）：PHY 在 MDIO 4，接口一 up 就 1Gbps；真正缺的是 rootfs 里没有 `ip`、没配默认路由、DNS 还指向 `127.0.0.53`。现在 `netup` + `route` + 静态 DNS 一起解决 |
| 2 | 无 systemd | 只有自写 init；已能 apt，可装 openssh-server（见 §3.4） |
| 3 | **整盘替换 rootfs 无通道** | 建议在 p3（`cache`，428 MiB 空着）放一个救援系统，从它启动后 `dd` 覆盖 p2 |
| 4 | 未装内核模块 | `/lib/modules` 不存在；开机必需驱动都已 `=y`，音频等 `=m` 的用不了 |
| 5 | u-boot 无 UDC / 无网络命令 | 无法 fastboot、无法网络启动 |

---

## 8. 与板子的对应关系

| 本仓库 | 板子上 |
|---|---|
| `rootfs/etc/**` | `/etc/**` |
| `rootfs/usr/sbin/init` | `/usr/sbin/init` |
| `rootfs/boot/Image` | `/boot/Image` |
| `rootfs/boot/dtb/nexell/s5p6818-x6818.dtb` | `/boot/dtb/nexell/s5p6818-x6818.dtb` |
| `out/system-p2.img` | eMMC `/dev/mmcblk2p2` 整分区 |

u-boot 侧已保存的环境：

```
bootargs=console=ttySAC0,115200n8 earlycon=s5pv210,mmio32,0xc00a1000 root=/dev/mmcblk2p2 rootwait rootfstype=ext4 rw nr_cpus=4
bootcmd=ext4load mmc 0:2 0x41000000 /boot/Image; ext4load mmc 0:2 0x48000000 /boot/dtb/nexell/s5p6818-x6818.dtb; booti 0x41000000 - 0x48000000
```

注意 u-boot 里 eMMC 是 **mmc 0**（不是厂商 u-boot 的 mmc 2），`nr_cpus=4` 不能删
（cluster1 缓存不一致，8 核会崩）。

---

## 9. 校验和（归档用）

| 文件 | 大小 | sha256 |
|---|---|---|
| `base/ubuntu-base-22.04.5-base-arm64.tar.gz` | 27,671,306 | `075d4abd2817a5023ab0a82f5cb314c5ec0aa64a9c0b40fd3154ca3bfdae979f` |
| `uboot/boot-nanopi3-1g.img` | 523,776 | `d5cc2d81cc899a004fd2929eb4f54d4cb2e2cce01ed857226139e5e59abe7a92` |
| `uboot/boot-nanopi3-1g-emmc.img` | 491,520 | `d1edd68c1742dedfc8c25ba0ce9e46e9db642207db9306ff9733356fabb078fe` |
| `uboot/1g-bl1-nanopi.bin` | 28,800 | `387bc62f6836ec187c57fd106f4a2111c5a425276d8da1bb10f8eb5b602b197c` |
| `uboot/ROLLBACK-ubootpak-vendor.bin` | 341,524 | `99d5d6fa2f03030dde921a7d2106bed72dfc719c6d9a00eca8331d87fae9bf7f` |

---

## 10. 相关文档

姊妹仓库 `../S5p6818-kernel` 里有内核侧的手册；
本工程历史的完整记录（含首次装机的全过程、踩过的坑）在
`s5p6818文档/MANUAL-x6818-mainline.md`、`BUILD-linux7.2-x6818.md`、`FLASH-fastboot-eMMC.md`。
