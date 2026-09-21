#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

VERSION="2.0.2"; AUTO=false; TIMEZONE="Asia/Shanghai"; NEW_HOSTNAME=""
REQUESTED_SSH_PORT=""; SWAP_MB=0; PRESERVE_LISTENERS=true; ENABLE_FIREWALL=true
ALLOW_SPECS=(); OS=""; OS_FAMILY=""; INIT_SYSTEM=""; SSH_SERVICE=""; SSH_PORT=22; BACKUP_DIR=""
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info(){ printf "${CYAN}→ %s${NC}\n" "$*"; }; ok(){ printf "${GREEN}✓ %s${NC}\n" "$*"; }
warn(){ printf "${YELLOW}⚠ %s${NC}\n" "$*"; }; die(){ printf "${RED}✗ %s${NC}\n" "$*" >&2; exit 1; }

usage(){ cat <<'EOF'
用法：vps-quick-setting.sh [选项]
  --auto                  无交互执行
  --hostname NAME         设置主机名
  --timezone ZONE         设置时区（默认 Asia/Shanghai）
  --ssh-port PORT         修改 SSH 端口（1024-65535）
  --allow PORT/PROTO      额外放行端口，可重复
  --swap-mb MB            创建 Swap
  --no-preserve-listeners 不保留当前监听端口
  --no-firewall           不配置防火墙
EOF
}
while (($#)); do
 case "$1" in
  --auto) AUTO=true;; --hostname) NEW_HOSTNAME=${2:?}; shift;; --timezone) TIMEZONE=${2:?}; shift;;
  --ssh-port) REQUESTED_SSH_PORT=${2:?}; shift;; --swap-mb) SWAP_MB=${2:?}; shift;;
  --allow) ALLOW_SPECS+=("${2:?}"); shift;; --no-preserve-listeners) PRESERVE_LISTENERS=false;;
  --no-firewall) ENABLE_FIREWALL=false;; -h|--help) usage; exit 0;; *) die "未知选项：$1";;
 esac; shift
done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 或 sudo 运行"

detect_platform(){
 [[ -r /etc/os-release ]] || die "无法识别操作系统"; . /etc/os-release; OS=${ID:-unknown}
 case "$OS" in
  debian|ubuntu) OS_FAMILY=debian; INIT_SYSTEM=systemd; SSH_SERVICE=ssh;;
  alpine) OS_FAMILY=alpine; INIT_SYSTEM=openrc; SSH_SERVICE=sshd;;
  *) die "仅支持 Debian、Ubuntu、Alpine，当前为 $OS";;
 esac
}
svc_enable_start(){ if [[ $INIT_SYSTEM == systemd ]]; then systemctl enable --now "$1" >/dev/null; else rc-update add "$1" default >/dev/null 2>&1 || true; rc-service "$1" restart >/dev/null; fi; }
svc_reload(){ if [[ $INIT_SYSTEM == systemd ]]; then systemctl reload "$1" 2>/dev/null || systemctl restart "$1"; else rc-service "$1" reload 2>/dev/null || rc-service "$1" restart; fi; }
enable_nftables_boot(){
 if [[ $INIT_SYSTEM == systemd ]]; then
  systemctl enable nftables >/dev/null
 else
  rc-update add nftables default >/dev/null 2>&1 || true
 fi
}
install_packages(){
 info "更新索引并安装基础组件"
 if [[ $OS_FAMILY == debian ]]; then
  export DEBIAN_FRONTEND=noninteractive; apt-get update -qq
  apt-get install -y --no-install-recommends openssh-server chrony fail2ban nftables ca-certificates curl iproute2 >/dev/null
 else apk update >/dev/null; apk add --no-cache openssh chrony fail2ban nftables ca-certificates curl iproute2 tzdata util-linux >/dev/null
 fi; ok "基础组件已安装"
}
get_ssh_port(){ local p; p=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2;exit}') || true; [[ -n $p ]] || p=$(awk 'tolower($1)=="port"{print $2;exit}' /etc/ssh/sshd_config 2>/dev/null) || true; echo "${p:-22}"; }
valid_port(){ [[ $1 =~ ^[0-9]+$ ]] && ((1<=10#$1 && 10#$1<=65535)); }
valid_allow(){ [[ $1 =~ ^([0-9]{1,5})/(tcp|udp)$ ]] && valid_port "${BASH_REMATCH[1]}"; }
has_key(){ find /root/.ssh /home -maxdepth 3 -type f -name authorized_keys -size +0c 2>/dev/null | grep -q .; }
ask(){ local a; $AUTO && [[ ${2:-N} == Y ]] && return 0; $AUTO && return 1; read -r -p "$1 [${2:-N}] " a </dev/tty || a=${2:-N}; [[ ${a:-${2:-N}} =~ ^[Yy]$ ]]; }

configure_timezone(){ [[ -e /usr/share/zoneinfo/$TIMEZONE ]] || { warn "时区不存在：$TIMEZONE"; return 0; }; ln -snf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime; echo "$TIMEZONE" >/etc/timezone 2>/dev/null || true; ok "时区：$TIMEZONE"; }
configure_hostname(){
 [[ -n $NEW_HOSTNAME ]] || return 0; [[ $NEW_HOSTNAME =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] || die "主机名无效"
 echo "$NEW_HOSTNAME" >/etc/hostname; hostname "$NEW_HOSTNAME" 2>/dev/null || true
 if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts; else echo "127.0.1.1 $NEW_HOSTNAME" >>/etc/hosts; fi
 ok "主机名：$NEW_HOSTNAME"
}
configure_time(){ svc_enable_start chronyd 2>/dev/null || svc_enable_start chrony; ok "chrony 已启用"; }
configure_ssh(){
 local target=${REQUESTED_SSH_PORT:-$SSH_PORT} drop=/etc/ssh/sshd_config.d/99-vps-quick-setting.conf
 valid_port "$target" || die "SSH 端口无效"; ((10#$target>=1024)) || [[ $target == 22 ]] || die "自定义 SSH 端口应为 1024-65535"
 mkdir -p /etc/ssh/sshd_config.d
 if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then cp -a /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config"; echo 'Include /etc/ssh/sshd_config.d/*.conf' >>/etc/ssh/sshd_config; fi
 cp -a "$drop" "$BACKUP_DIR/99-vps-quick-setting.conf" 2>/dev/null || true
 { echo "Port $target"; echo 'PubkeyAuthentication yes'; echo 'PermitEmptyPasswords no'; echo 'KbdInteractiveAuthentication no'; echo 'X11Forwarding no'; echo 'MaxAuthTries 4'; echo 'LoginGraceTime 30'
   if has_key; then echo 'PasswordAuthentication no'; echo 'PermitRootLogin prohibit-password'; else echo 'PasswordAuthentication yes'; echo 'PermitRootLogin yes'; fi; } >"$drop"
 if ! sshd -t; then [[ -f $BACKUP_DIR/sshd_config ]] && cp -a "$BACKUP_DIR/sshd_config" /etc/ssh/sshd_config; [[ -f $BACKUP_DIR/99-vps-quick-setting.conf ]] && cp -a "$BACKUP_DIR/99-vps-quick-setting.conf" "$drop" || rm -f "$drop"; die "SSH 校验失败，已回滚"; fi
 SSH_PORT=$target; has_key && ok "SSH 密钥加固完成（端口 $SSH_PORT）" || warn "未发现 authorized_keys，已保留密码登录防止锁死"
}
collect_listeners(){
 $PRESERVE_LISTENERS || return 0
 while read -r proto port; do valid_allow "$port/$proto" && ALLOW_SPECS+=("$port/$proto"); done < <(ss -H -lntu 2>/dev/null | awk '$1=="tcp"||$1=="udp"{a=$5;sub(/^.*:/,"",a);gsub(/[[\]]/,"",a);if(a~/^[0-9]+$/)print $1,a}' | sort -u)
}
dedupe_rules(){ local i; declare -A seen=(); local out=(); for i in "${ALLOW_SPECS[@]}"; do valid_allow "$i" || die "端口规则无效：$i"; [[ ${seen[$i]+x} ]] || { seen[$i]=1; out+=("$i"); }; done; ALLOW_SPECS=("${out[@]}"); }
configure_firewall(){
 $ENABLE_FIREWALL || { warn "已跳过防火墙"; return 0; }
 ALLOW_SPECS+=("$SSH_PORT/tcp" "80/tcp" "443/tcp"); collect_listeners; dedupe_rules
 local rules=/etc/nftables.d/90-vps-quick-setting.nft main=/etc/nftables.conf i port proto
 mkdir -p /etc/nftables.d; cp -a "$rules" "$BACKUP_DIR/" 2>/dev/null || true
 { echo 'table inet vps_quick_setting {'; echo ' chain input {'; echo '  type filter hook input priority -10; policy drop;'; echo '  iifname "lo" accept'; echo '  ct state established,related accept'; echo '  ct state invalid drop'; echo '  ip protocol icmp accept'; echo '  ip6 nexthdr ipv6-icmp accept'; echo '  udp sport 67 udp dport 68 accept'
   for i in "${ALLOW_SPECS[@]}"; do port=${i%/*}; proto=${i#*/}; echo "  $proto dport $port accept"; done; echo ' }'; echo '}'; } >"$rules"
 if [[ ! -f $main ]]; then printf '#!/usr/sbin/nft -f\nflush ruleset\ninclude "/etc/nftables.d/*.nft"\n' >"$main"; elif ! grep -qF 'include "/etc/nftables.d/*.nft"' "$main"; then cp -a "$main" "$BACKUP_DIR/nftables.conf"; echo 'include "/etc/nftables.d/*.nft"' >>"$main"; fi
 nft -c -f "$main" || die "nftables 校验失败"
 nft delete table inet vps_quick_setting 2>/dev/null || true
 nft -f "$rules"
 # Do not restart/reload the full nftables service here: a distro config may
 # contain 'flush ruleset', which would temporarily erase Docker/WARP rules.
 enable_nftables_boot
 ok "双栈防火墙已启用，放行：${ALLOW_SPECS[*]}"
 if command -v docker >/dev/null 2>&1; then warn "Docker 发布端口需在 DOCKER-USER 链另行限制来源"; fi
}
configure_fail2ban(){ mkdir -p /etc/fail2ban/jail.d; printf '[sshd]\nenabled=true\nport=%s\nbackend=auto\nmaxretry=5\nfindtime=10m\nbantime=12h\n' "$SSH_PORT" >/etc/fail2ban/jail.d/sshd.local; svc_enable_start fail2ban; ok "Fail2ban 已启用"; }
configure_swap(){
 [[ $SWAP_MB =~ ^[0-9]+$ ]] || die "Swap 大小应为整数 MB"; ((SWAP_MB>0)) || return 0
 swapon --show=NAME --noheadings 2>/dev/null | grep -q . && { warn "已有 Swap，跳过"; return 0; }; [[ ! -e /swapfile ]] || die "/swapfile 已存在"
 fallocate -l "${SWAP_MB}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=progress
 chmod 600 /swapfile; mkswap /swapfile >/dev/null; swapon /swapfile; grep -qF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab; ok "已创建 ${SWAP_MB}MB Swap"
}
write_baseline(){
 local d=/root/baseline f; mkdir -p "$d"; f="$d/$(date +%Y%m%d-%H%M%S)-system-baseline.txt"
 { echo "VPS Quick Setting Plus $VERSION"; echo "Generated: $(date -Is)"; echo "OS: $OS ${VERSION_ID:-}"; echo "Kernel: $(uname -r)"; echo "SSH: $SSH_PORT"; echo "Allowed: ${ALLOW_SPECS[*]:-firewall skipped}"; echo; ip -brief address 2>/dev/null || true; echo; ss -lntup 2>/dev/null || true; echo; df -hT; echo; free -h 2>/dev/null || true; echo; nft list ruleset 2>/dev/null || true; } >"$f"; ok "基线报告：$f"
}
main(){
 printf "\n${GREEN}VPS Quick Setting Plus v%s${NC}\n" "$VERSION"; detect_platform
 BACKUP_DIR="/root/vps-quick-setting-backup/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP_DIR"; install_packages; SSH_PORT=$(get_ssh_port)
 if ! $AUTO; then [[ -n $NEW_HOSTNAME ]] || read -r -p '新主机名（留空跳过）：' NEW_HOSTNAME </dev/tty || true; [[ -n $REQUESTED_SSH_PORT ]] || ! ask '修改 SSH 端口？' N || read -r -p '新 SSH 端口：' REQUESTED_SSH_PORT </dev/tty; ((SWAP_MB>0)) || ! ask '创建 Swap？' N || read -r -p 'Swap 大小（MB）：' SWAP_MB </dev/tty; fi
 configure_timezone; configure_hostname; configure_time; configure_ssh; configure_firewall; configure_fail2ban; configure_swap; svc_reload "$SSH_SERVICE"; write_baseline
 ok "完成。保留当前会话，另开终端测试 SSH 后再退出。"; echo "备份目录：$BACKUP_DIR"
}
trap 'printf "${RED}✗ 第 %s 行失败：%s${NC}\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
main "$@"
