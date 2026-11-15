# S5p6818 U-Boot（自包含副本）

## 编译
```sh
./build.sh              # 首次自动配置 + 并行编译
```

## 自包含说明
| 内容 | 位置 |
|---|---|
| 交叉工具链 arm-eabi 4.8 | `prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/` |
| 芯片底层驱动 (Nexell prototype) | `arch/arm/cpu/slsiap/s5p6818/prototype/` |
| 打包脚本/mk6818 + nsih 头 | `tools/mk6818`、`nsih*.txt`、`2ndboot` |

不再有软链接指向上层目录，整棵树可 `cp -a` 到任意路径/机器直接编译。

## 产物
- `u-boot.bin`：裸 u-boot
- `ubootpak.bin`：NSIH 头 + 2ndboot + u-boot.bin，刷机用这个

## 刷写
```sh
fastboot flash ubootpak ubootpak.bin
```
分区名是 `ubootpak`（不是 `ubootapk`）。
