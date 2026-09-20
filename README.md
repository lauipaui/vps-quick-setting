# VPS Quick Setting Plus

面向新 VPS 的轻量初始化与安全基线脚本，基于 [chzzfly/vps-quick-setting](https://github.com/chzzfly/vps-quick-setting) 改进。

支持 Debian/Ubuntu/Alpine、systemd/OpenRC、SSH 密钥加固、Fail2ban、chrony、可选 Swap、IPv4/IPv6 nftables 防火墙、监听端口自动保留、系统备份与基线报告。

## 一键运行

先配置并测试 SSH 公钥。未发现 `authorized_keys` 时脚本会保留密码登录，避免锁死。

```bash
curl -fsSL https://raw.githubusercontent.com/lauipaui/vps-quick-setting/main/vps-quick-setting.sh | sudo bash -s -- --auto
```

交互模式：

```bash
curl -fsSL -o vps-quick-setting.sh https://raw.githubusercontent.com/lauipaui/vps-quick-setting/main/vps-quick-setting.sh
chmod +x vps-quick-setting.sh
sudo ./vps-quick-setting.sh
```

## 参数示例

```bash
# 自定义 SSH，并放行 Reality/Hysteria2
sudo ./vps-quick-setting.sh --auto --ssh-port 22222 --allow 443/tcp --allow 8443/udp

# Only-IPv6 同样直接使用；inet 表同时管理 IPv4/IPv6
sudo ./vps-quick-setting.sh --auto --hostname edge-jp

# 2 GiB Swap
sudo ./vps-quick-setting.sh --auto --swap-mb 2048

# 不配置防火墙
sudo ./vps-quick-setting.sh --auto --no-firewall
```

自动模式放行实际 SSH 端口、80/tcp、443/tcp、执行前已有的监听端口，以及所有 `--allow PORT/PROTO`。需要严格白名单时使用 `--no-preserve-listeners`。

脚本只创建 input 链，不把 forward 设为拒绝，因此不会主动破坏 Docker、WARP 或路由转发。Docker 发布端口可能绕过普通 input 规则，限制来源时请配置 `DOCKER-USER`。

备份位于 `/root/vps-quick-setting-backup/`，基线报告位于 `/root/baseline/`。运行完成后不要立即断开当前 SSH，应另开终端验证新连接。

## 致谢

改进自 [chzzfly/vps-quick-setting](https://github.com/chzzfly/vps-quick-setting)。保留原作者署名。上游未声明许可证时，不应将代码视为已获得任意再许可授权。
