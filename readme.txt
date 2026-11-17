
基于linux-7.2.15 内核，适配S5P6818的 九鼎x6818板子


1、清理工程命令：
	make mrproper 


2、生成config
	make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- x6818_defconfig 

3、编译：
	make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 Image dtbs

4、产物：
	内核镜像：arch/arm64/boot/Image
	设备树：arch/arm64/boot/dts/nexell/s5p6818-x6818.dtb
