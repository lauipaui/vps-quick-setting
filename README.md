# VPS Quick Setting Plus

**中文** | [English](README.en.md)

面向新 VPS 的轻量初始化与安全基线脚本，基于 [chzzfly/vps-quick-setting](https://github.com/chzzfly/vps-quick-setting) 改进。当前脚本版本 `2.0.2`，支持 Debian/Ubuntu/Alpine、systemd/OpenRC、SSH、Fail2ban、chrony、可选 Swap 与双栈 nftables input 防火墙。

> **这是会改变系统行为的 root 脚本，不是只读巡检或通用调优工具。** `--auto` 只表示不交互，并不表示安全预览。对已有生产节点应先评估差异，不要为了阅读 README 就重跑安装。

## 使用前检查

- 有可用的厂商控制台/带外入口，保持当前 SSH 会话不关闭。
- 先配置并在另一个终端验证目标登录用户的 SSH 公钥。
- 备份现有 SSH、nftables、Fail2ban、时区、主机名和 `/etc/fstab`，必要时做磁盘快照。
- 明确需要开放的业务端口及容器/路由/WARP/Tailscale 规则，不能只凭监听自动保留判断所有流量安全。
- 需要 Bash（Alpine 需先准备 Bash）与发行版软件源可达；运行过程中会安装包和启用服务。

**注意密钥判断限制：** 代码只搜索 `/root/.ssh` 与 `/home` 下非空 `authorized_keys`，不证明当前登录用户的密钥有效或 Include/Match 的最终配置生效。发现文件后可能关闭密码登录；没发现文件时会保留密码/root 登录以降低锁死风险，并不代表推荐长期如此。

## 下载、审阅和运行

```sh
git clone https://github.com/lauipaui/vps-quick-setting.git
cd vps-quick-setting
less vps-quick-setting.sh
bash -n vps-quick-setting.sh
bash vps-quick-setting.sh --help
# 审阅并完成上述检查后再执行
sudo bash vps-quick-setting.sh
```

公开远程入口（同样需要先审阅；新 VPS 的自动模式示例）：

```sh
curl -fsSL https://raw.githubusercontent.com/lauipaui/vps-quick-setting/main/vps-quick-setting.sh | sudo bash -s -- --auto
```

本次文档更新没有运行初始化脚本、重新配置 SSH/防火墙或验收服务器。

## 参数

| 参数 | 行为 / 默认值 |
| --- | --- |
| `--auto` | 无交互执行，仍修改系统 |
| `--hostname NAME` | 设置主机名；未指定时自动模式不修改 |
| `--timezone ZONE` | 默认 `Asia/Shanghai`，会修改存在的时区路径 |
| `--ssh-port PORT` | 自定义 1024–65535；未指定时读取现有端口（回退 22） |
| `--allow PORT/PROTO` | 额外开放 `tcp`/`udp` 端口，可重复 |
| `--swap-mb MB` | 默认 0，不新建；已有活动 Swap 时跳过 |
| `--no-preserve-listeners` | 不自动放行执行前已有监听端口，仍保留默认放行项 |
| `--no-firewall` | 不写本项目 nftables 规则，其他初始化照常执行 |
| `-h` / `--help` | 显示帮助并退出，不初始化 |

```sh
# 自定义 SSH，额外放行 Reality/Hysteria2
sudo bash vps-quick-setting.sh --auto --ssh-port 22222 --allow 443/tcp --allow 8443/udp
# Only-IPv6 主机；inet 表同时处理 IPv4/IPv6
sudo bash vps-quick-setting.sh --auto --hostname edge-jp
# 2 GiB Swap
sudo bash vps-quick-setting.sh --auto --swap-mb 2048
# 跳过防火墙，不是跳过 SSH/时区等改动
sudo bash vps-quick-setting.sh --auto --no-firewall
```

## 实际变更

- 安装 OpenSSH、chrony、Fail2ban、nftables 等基础组件；启用时间同步和 Fail2ban。
- 写 `/etc/ssh/sshd_config.d/99-vps-quick-setting.conf`，必要时追加 Include；`sshd -t` 校验后 reload/restart SSH。**语法正确不保证目标端口或 Match 块的最终值符合预期**，需再检查 `sshd -T` 与新连接。
- 默认设置时区，按参数改 hostname；可创建 `/swapfile` 并写 `/etc/fstab`。
- 写 `/etc/nftables.d/90-vps-quick-setting.nft`，创建 `table inet vps_quick_setting`，input policy drop，允许回环、已建立连接、ICMP 与配置端口。
- 自动开放 SSH、80/tcp、443/tcp、检测到的已有监听端口和所有 `--allow`。自动保留可能开放本不该公网可达的端口，严格场景使用 `--no-preserve-listeners` 并审阅白名单；该选项仍不移除 80/443 默认项。

安装时只替换自己的 nftables 表，不 reload 整个规则集，不创建 forward 拒绝链；**不能据此保证与任何现有防火墙、Docker 或隧道配置完全兼容**。其他 input base chain 的 drop 仍可能阻断，Docker 发布端口可能走 forward 绕过 input，需另行限制。

脚本可能创建包含 `flush ruleset` 的 `/etc/nftables.conf`，并启用开机加载。安装当次没清空其他表不代表后续重启/reload 也不会；**重启前审查完整 nftables 启动配置及 Docker/WARP/Tailscale 恢复顺序**。

## 备份、验证与回滚

- 脚本备份：`/root/vps-quick-setting-backup/<timestamp>/`，主要是部分将被覆盖的 SSH/nftables 文件；**不是整机备份**，并不自动保存所有包、时区、hostname、Fail2ban、fstab 或完整运行时规则。
- 基线报告：`/root/baseline/<timestamp>-system-baseline.txt`，可能含真实 IP、端口和账户路径，分享前脱敏。
- 保持旧 SSH 会话，另开终端确认公钥认证、新端口、业务连通、IPv4/IPv6 和时间同步，再关闭旧会话。
- 只有 SSH 语法失败路径会尝试局部恢复相关文件；没有通用 `--uninstall`、dry-run 或全系统自动回滚。
- 回归时通过仍可用会话/控制台，恢复自己记录的对应配置，先用 `sshd -t` 和 `nft -c -f /etc/nftables.conf`（或你要恢复的规则文件路径）校验，再按实际服务加载。只删除自己的表不能撤销其他配置和安装包；不盲目 `flush ruleset`。
- Swap 回滚需确认容量、占用和 fstab，再决定 swapoff/删除，不提供可对所有生产机直接执行的删除命令。

## 致谢与许可

保留 [chzzfly/vps-quick-setting](https://github.com/chzzfly/vps-quick-setting) 原作者署名。本仓库未附独立 `LICENSE`；上游未声明许可证时，不应将代码视为获得任意再许可授权。系统组件有各自许可与使用约束。
