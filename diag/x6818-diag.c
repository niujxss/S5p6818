// x6818-diag v2 —— 只读诊断 + 网络最小工具集（aarch64 静态）
//   ./x6818-diag mdio            扫描 MDIO 地址，打印 PHY ID / 链路
//   ./x6818-diag pmic [bus]      读 AXP228 关键寄存器
//   ./x6818-diag netinfo [if]    看接口状态
//   ./x6818-diag netup <ip/len> [if]   起网卡并配 IPv4（如 192.168.31.150/24）
//   ./x6818-diag route [gw] [if]       加默认路由（gw 省略时用 192.168.31.1）
//   ./x6818-diag fetch <ip> <port> <url路径> <本地文件>   最小 HTTP GET
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <net/route.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>

/* ================= DWMAC MDIO ================= */
#define GMAC_BASE   0xc0060000UL
#define GMAC_MII_ADDR  0x10
#define GMAC_MII_DATA  0x14
#define CLK_CSR     4
static volatile uint32_t *gmac;

static int mdio_read(int phy, int reg, uint16_t *out)
{
	uint32_t v = ((uint32_t)(phy & 0x1f) << 11) |
	             ((uint32_t)(reg & 0x1f) << 6) |
	             ((uint32_t)(CLK_CSR & 0xf) << 2) | 1u;
	gmac[GMAC_MII_ADDR / 4] = v;
	for (int i = 0; i < 10000; i++) {
		if (!(gmac[GMAC_MII_ADDR / 4] & 1u)) {
			*out = (uint16_t)(gmac[GMAC_MII_DATA / 4] & 0xffff);
			return 0;
		}
		usleep(20);
	}
	return -1;
}

static int do_mdio(void)
{
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }
	long page = sysconf(_SC_PAGESIZE);
	off_t off = GMAC_BASE & ~(page - 1);
	void *m = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, off);
	if (m == MAP_FAILED) { perror("mmap"); close(fd); return 1; }
	gmac = (volatile uint32_t *)((char *)m + (GMAC_BASE - off));

	printf("MDIO scan (GMAC 0x%lx, CR=%d)\n", GMAC_BASE, CLK_CSR);
	printf("  PHYAD  ID1     ID2     link\n");
	int found = 0;
	for (int a = 0; a < 32; a++) {
		uint16_t id1 = 0, id2 = 0, bmsr = 0;
		if (mdio_read(a, 2, &id1) != 0) continue;
		mdio_read(a, 3, &id2);
		if (id1 == 0xffff || id1 == 0x0000) continue;
		mdio_read(a, 1, &bmsr);          /* 第一次读清锁存 */
		mdio_read(a, 1, &bmsr);          /* 第二次才是当前状态 */
		found++;
		printf("  %-5d 0x%04x  0x%04x  %s  %s\n", a, id1, id2,
		       (bmsr & 0x0004) ? "UP  " : "down",
		       (id1 == 0x001c && (id2 & 0xfff0) == 0xc910) ? "RTL8211E" : "");
	}
	if (!found) printf("  none answered\n");
	munmap(m, page); close(fd);
	return 0;
}

/* ================= AXP228 ================= */
static int i2c_rd_rw(int fd, uint8_t reg, uint8_t *val)
{
	struct i2c_rdwr_ioctl_data d;
	struct i2c_msg m[2];
	m[0].addr = 0x34; m[0].flags = 0;          m[0].len = 1; m[0].buf = &reg;
	m[1].addr = 0x34; m[1].flags = I2C_M_RD;   m[1].len = 1; m[1].buf = val;
	d.msgs = m; d.nmsgs = 2;
	return ioctl(fd, I2C_RDWR, &d) < 0 ? -1 : 0;
}

static int i2c_rd_2x(int fd, uint8_t reg, uint8_t *val)
{
	if (write(fd, &reg, 1) != 1) return -1;
	if (read(fd, val, 1) != 1) return -1;
	return 0;
}

static int do_pmic(int bus)
{
	char path[32];
	int fd = -1;
	if (bus < 0) {
		for (int b = 0; b < 16; b++) {
			snprintf(path, sizeof path, "/dev/i2c-%d", b);
			int t = open(path, O_RDWR);
			if (t < 0) continue;
			ioctl(t, I2C_SLAVE, 0x34);
			uint8_t v = 0;
			int r = i2c_rd_rw(t, 0x03, &v);
			if (r < 0) r = i2c_rd_2x(t, 0x03, &v);
			fprintf(stderr, "  probe i2c-%d: %s (0x03=0x%02x)\n",
			        b, r == 0 ? "OK" : strerror(errno), v);
			if (r == 0) { fd = t; bus = b; break; }
			close(t);
		}
		if (fd < 0) { fprintf(stderr, "AXP228 not found\n"); return 1; }
	} else {
		snprintf(path, sizeof path, "/dev/i2c-%d", bus);
		fd = open(path, O_RDWR);
		if (fd < 0) { perror(path); return 1; }
		ioctl(fd, I2C_SLAVE, 0x34);
	}
	printf("AXP228 on i2c-%d (0x34)\n\n", bus);
	struct { uint8_t r; const char *n; } regs[] = {
		{0x00,"power status"},{0x01,"mode/charge"},{0x03,"IC_TYPE"},
		{0x10,"DCDC1-5/ALDO1-2/DC5LDO en"},{0x12,"ELDO1-3/DLDO1-4/DC1SW en"},
		{0x13,"ALDO3 en"},{0x15,"DLDO1 volt"},{0x16,"DLDO2 volt"},
		{0x19,"ELDO1 volt"},{0x1A,"ELDO2 volt"},{0x21,"DCDC1 volt"},{0x28,"ALDO1 volt"},
	};
	for (unsigned i = 0; i < sizeof regs/sizeof regs[0]; i++) {
		uint8_t v = 0;
		int r = i2c_rd_rw(fd, regs[i].r, &v);
		if (r < 0) r = i2c_rd_2x(fd, regs[i].r, &v);
		if (r == 0) printf("  0x%02x = 0x%02x   %s\n", regs[i].r, v, regs[i].n);
		else        printf("  0x%02x = <err>    %s\n", regs[i].r, regs[i].n);
	}
	close(fd);
	return 0;
}

/* ================= 网络 ================= */
static int do_netinfo(const char *name)
{
	int s = socket(AF_INET, SOCK_DGRAM, 0);
	struct ifreq ifr;
	struct ifconf ifc;
	char buf[1024];
	ifc.ifc_len = sizeof buf;
	ifc.ifc_buf = buf;
	if (ioctl(s, SIOCGIFCONF, &ifc) < 0) { perror("SIOCGIFCONF"); return 1; }
	printf("%-8s %-16s %-18s %s\n", "if", "IPv4", "MAC", "flags");
	for (struct ifreq *p = ifc.ifc_req; (char *)p < buf + ifc.ifc_len;
	     p = (struct ifreq *)((char *)p + sizeof(struct ifreq))) {
		if (name && strcmp(p->ifr_name, name)) continue;
		memset(&ifr, 0, sizeof ifr);
		strncpy(ifr.ifr_name, p->ifr_name, IFNAMSIZ - 1);
		char ip[32] = "-";
		if (ioctl(s, SIOCGIFADDR, &ifr) == 0)
			inet_ntop(AF_INET, &((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr, ip, sizeof ip);
		memset(&ifr, 0, sizeof ifr);
		strncpy(ifr.ifr_name, p->ifr_name, IFNAMSIZ - 1);
		char mac[32] = "-";
		if (ioctl(s, SIOCGIFHWADDR, &ifr) == 0) {
			unsigned char *h = (unsigned char *)ifr.ifr_hwaddr.sa_data;
			snprintf(mac, sizeof mac, "%02x:%02x:%02x:%02x:%02x:%02x",
			         h[0], h[1], h[2], h[3], h[4], h[5]);
		}
		memset(&ifr, 0, sizeof ifr);
		strncpy(ifr.ifr_name, p->ifr_name, IFNAMSIZ - 1);
		unsigned fl = 0;
		if (ioctl(s, SIOCGIFFLAGS, &ifr) == 0) fl = ifr.ifr_flags;
		printf("%-8s %-16s %-18s %s%s%s\n", p->ifr_name, ip, mac,
		       (fl & IFF_UP) ? "UP " : "down ",
		       (fl & IFF_RUNNING) ? "RUNNING " : "",
		       (fl & IFF_LOOPBACK) ? "LOOP" : "");
	}

	printf("\n/proc/net/route:\n");
	FILE *rf = fopen("/proc/net/route", "r");
	if (rf) {
		char line[256];
		while (fgets(line, sizeof line, rf)) printf("  %s", line);
		fclose(rf);
	} else {
		printf("  (unavailable)\n");
	}
	close(s);
	return 0;
}

static int do_netup(const char *cidr, const char *name)
{
	int s = socket(AF_INET, SOCK_DGRAM, 0);
	struct ifreq ifr;
	struct sockaddr_in *sin;
	char tmp[64];
	strncpy(tmp, cidr, sizeof tmp - 1); tmp[sizeof tmp - 1] = 0;
	char *slash = strchr(tmp, '/');
	int plen = 24;
	if (slash) { *slash = 0; plen = atoi(slash + 1); }
	unsigned long addr = inet_addr(tmp);
	if (addr == INADDR_NONE) { fprintf(stderr, "bad ip: %s\n", tmp); return 1; }

	memset(&ifr, 0, sizeof ifr);
	strncpy(ifr.ifr_name, name, IFNAMSIZ - 1);
	sin = (struct sockaddr_in *)&ifr.ifr_addr;
	sin->sin_family = AF_INET;
	sin->sin_addr.s_addr = addr;
	if (ioctl(s, SIOCSIFADDR, &ifr) < 0) { perror("SIOCSIFADDR"); close(s); return 1; }

	unsigned long mask = plen ? htonl(~0UL << (32 - plen)) : 0;
	memset(&ifr, 0, sizeof ifr);
	strncpy(ifr.ifr_name, name, IFNAMSIZ - 1);
	sin = (struct sockaddr_in *)&ifr.ifr_netmask;
	sin->sin_family = AF_INET;
	sin->sin_addr.s_addr = mask;
	ioctl(s, SIOCSIFNETMASK, &ifr);

	memset(&ifr, 0, sizeof ifr);
	strncpy(ifr.ifr_name, name, IFNAMSIZ - 1);
	ioctl(s, SIOCGIFFLAGS, &ifr);
	ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
	if (ioctl(s, SIOCSIFFLAGS, &ifr) < 0) { perror("SIOCSIFFLAGS"); close(s); return 1; }
	close(s);
	printf("configured %s = %s/%d\n", name, tmp, plen);
	sleep(2);
	return do_netinfo(name);
}

/* 加默认路由：netup 只配 IP/掩码，出本网段（apt、公网 DNS）必须有默认路由 */
static int do_route(const char *gw, const char *name)
{
	int s = socket(AF_INET, SOCK_DGRAM, 0);
	struct rtentry rt;
	struct sockaddr_in *sin;

	if (s < 0) { perror("socket"); return 1; }

	memset(&rt, 0, sizeof rt);
	sin = (struct sockaddr_in *)&rt.rt_gateway;
	sin->sin_family = AF_INET;
	if (inet_pton(AF_INET, gw, &sin->sin_addr) != 1) {
		fprintf(stderr, "bad gateway: %s\n", gw);
		close(s);
		return 1;
	}
	sin = (struct sockaddr_in *)&rt.rt_dst;
	sin->sin_family = AF_INET;
	sin->sin_addr.s_addr = INADDR_ANY;
	sin = (struct sockaddr_in *)&rt.rt_genmask;
	sin->sin_family = AF_INET;
	sin->sin_addr.s_addr = INADDR_ANY;

	rt.rt_flags = RTF_UP | RTF_GATEWAY;
	rt.rt_dev = (char *)name;

	if (ioctl(s, SIOCADDRT, &rt) < 0) {
		if (errno == EEXIST) {
			printf("default route already present\n");
			close(s);
			return 0;
		}
		perror("SIOCADDRT");
		close(s);
		return 1;
	}
	close(s);
	printf("default route via %s dev %s\n", gw, name);
	return 0;
}

/* ================= 最小 HTTP GET ================= */
static int do_fetch(const char *host, int port, const char *path, const char *out)
{
	int s = socket(AF_INET, SOCK_STREAM, 0);
	struct sockaddr_in sa;
	memset(&sa, 0, sizeof sa);
	sa.sin_family = AF_INET;
	sa.sin_port = htons((uint16_t)port);
	if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) { fprintf(stderr, "bad host\n"); return 1; }
	printf("connect %s:%d ...\n", host, port);
	if (connect(s, (struct sockaddr *)&sa, sizeof sa) < 0) { perror("connect"); return 1; }

	char req[512];
	int n = snprintf(req, sizeof req,
	                 "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: x6818-diag\r\n\r\n", path, host);
	if (write(s, req, n) != n) { perror("write"); return 1; }

	static char buf[65536];
	char hdr[4096];
	int hlen = 0, in_body = 0, got = 0;
	FILE *f = NULL;

	for (;;) {
		if (!in_body) {
			/* 逐字节读，直到遇到 \r\n\r\n —— 避免 TCP 拆包把状态头拆散 */
			char c;
			ssize_t r = read(s, &c, 1);
			if (r <= 0) break;
			if (hlen < (int)sizeof hdr - 1) hdr[hlen++] = c;
			if (hlen >= 4 && !memcmp(hdr + hlen - 4, "\r\n\r\n", 4)) {
				hdr[hlen - 4] = 0;
				if (hlen < 13 || hdr[9] != '2') {
					printf("HTTP 状态异常: %.40s\n", hdr);
					close(s);
					return 1;
				}
				f = fopen(out, "wb");
				if (!f) { perror(out); close(s); return 1; }
				in_body = 1;
			}
		} else {
			ssize_t r = read(s, buf, sizeof buf);
			if (r <= 0) break;
			if (fwrite(buf, 1, r, f) != (size_t)r) { perror("fwrite"); break; }
			got += (int)r;
		}
	}
	if (f) fclose(f);
	close(s);
	if (!in_body) { printf("没有收到合法 HTTP 响应\n"); return 1; }
	printf("saved %s (%d bytes)\n", out, got);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr,
		        "用法:\n"
		        "  %s mdio\n"
		        "  %s pmic [i2c总线号]\n"
		        "  %s netinfo [接口]\n"
		        "  %s netup <ip/掩码位> [接口=eth0]\n"
		        "  %s route [网关=192.168.31.1] [接口=eth0]\n"
		        "  %s fetch <ip> <端口> <url路径> <本地文件>\n", argv[0], argv[0], argv[0], argv[0], argv[0], argv[0]);
		return 1;
	}
	if (!strcmp(argv[1], "mdio"))    return do_mdio();
	if (!strcmp(argv[1], "pmic"))    return do_pmic(argc > 2 ? atoi(argv[2]) : -1);
	if (!strcmp(argv[1], "netinfo")) return do_netinfo(argc > 2 ? argv[2] : NULL);
	if (!strcmp(argv[1], "netup")) {
		if (argc < 3) { fprintf(stderr, "需要 ip/掩码\n"); return 1; }
		return do_netup(argv[2], argc > 3 ? argv[3] : "eth0");
	}
	if (!strcmp(argv[1], "route"))
		return do_route(argc > 2 ? argv[2] : "192.168.31.1",
		                argc > 3 ? argv[3] : "eth0");
	if (!strcmp(argv[1], "fetch")) {
		if (argc < 6) { fprintf(stderr, "需要 <ip> <端口> <路径> <文件>\n"); return 1; }
		return do_fetch(argv[2], atoi(argv[3]), argv[4], argv[5]);
	}
	fprintf(stderr, "未知子命令: %s\n", argv[1]);
	return 1;
}