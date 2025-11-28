# FreeIPA 部署 Ansible Playbook

本專案提供完整的 Ansible playbook 用於在 Rocky Linux 10 上部署 FreeIPA 生產環境，完全符合 [PRD v1.7](docs/openldap_prd_v1.7.md) 文件規範。

**注意：** 本專案使用 **FreeIPA** 取代 OpenLDAP，提供更完整的身份管理解決方案（包含 LDAP、Kerberos、DNS、CA 等服務）。

## 專案結構

```
ldap-deploy/
├── ansible.cfg              # Ansible 設定檔
├── playbook.yml             # 主 playbook
├── inventory/               # 主機清單
│   └── hosts.yml
├── group_vars/              # 群組變數
│   ├── all.yml
│   └── ldap_servers.yml
├── roles/                   # Ansible roles
│   ├── system_setup/        # 系統基本設定
│   ├── openldap/            # FreeIPA 安裝與設定
│   ├── security/            # 安全性設定（SELinux、防火牆）
│   ├── backup/              # 備份腳本與排程
│   ├── monitoring/          # 監控設定（node_exporter）
│   ├── prometheus/          # Prometheus 監控系統
│   ├── grafana/             # Grafana 視覺化平台
│   └── redmine/             # Redmine 專案管理系統
└── docs/
    └── openldap_prd_v1.7.md # PRD 文件
```

## 前置需求

### 控制端（Ansible 執行端）

- Ansible >= 2.9
- Python >= 3.6
- 必要的 Python 模組：
  - `dnf` (用於 Rocky Linux 套件管理)
  - `cryptography` (用於憑證管理)
- 必要的 Ansible Collections：

  ```bash
  # 安裝所有必要的 collections
  ansible-galaxy collection install -r collections.yml

  # 如果遇到 SSL 證書問題，可以使用以下方式：
  # 1. 設定環境變數忽略 SSL 驗證（不建議用於生產環境）
  #    export ANSIBLE_GALAXY_IGNORE_CERTS=1
  #    ansible-galaxy collection install -r collections.yml
  #
  # 2. 或手動安裝 FreeIPA collection
  #    ansible-galaxy collection install freeipa.ansible_freeipa
  ```

### 目標主機

**LDAP 伺服器（ldap_servers）**

- Rocky Linux 10
- 至少 4 vCPU、8 GB RAM、100 GB Disk（Production）
- 網路連線（可存取 EPEL repository）
- Root 或 sudo 權限

**監控伺服器（monitoring_servers）**

- Rocky Linux 10
- 至少 2 vCPU、4 GB RAM、50 GB Disk
- 網路連線（可存取 EPEL repository）
- Root 或 sudo 權限

**Redmine 伺服器（redmine_servers）**

- Rocky Linux 10
- 至少 4 vCPU、8 GB RAM、100 GB Disk
- 網路連線（可存取 EPEL repository）
- Root 或 sudo 權限
- 需要編譯工具（gcc、make 等）

## 快速開始

### 1. 設定主機清單

編輯 `inventory/hosts.yml`，更新主機 IP 和相關設定：

```yaml
ldap-prod:
  ansible_host: 192.168.1.10 # 更新為實際 IP
  environment: production
```

### 2. 設定變數

編輯 `group_vars/all.yml`，設定必要的變數：

- `ipadm_password`: FreeIPA Directory Manager 密碼（**強烈建議使用 ansible-vault 加密**）
- `ipaadmin_password`: FreeIPA Admin 密碼（**強烈建議使用 ansible-vault 加密**）
- `ipa_domain`: FreeIPA Domain（例如：`qctrd.qct`）
- `ipa_realm`: FreeIPA Realm（例如：`QCTRD.QCT`）
- `management_networks`: 管理網段
- `redmine_hosts`: Redmine 主機 IP 列表
- `monitoring_hosts`: 監控主機 IP 列表

### 3. 加密敏感資訊（建議）

使用 ansible-vault 加密管理員密碼：

```bash
# 建立加密的變數檔案
ansible-vault create group_vars/all_vault.yml

# 在編輯器中加入：
# ipadm_password: "your_dm_password_here"
# ipaadmin_password: "your_admin_password_here"

# 或在 playbook 執行時使用 --ask-vault-pass
```

### 4. 執行 Playbook

```bash
# 完整部署所有伺服器
ansible-playbook playbook.yml

# 部署特定伺服器群組
ansible-playbook playbook.yml --limit ldap_servers      # 僅部署 LDAP 伺服器
ansible-playbook playbook.yml --limit monitoring_servers # 僅部署監控伺服器
ansible-playbook playbook.yml --limit redmine_servers    # 僅部署 Redmine 伺服器

# 部署特定主機
ansible-playbook playbook.yml --limit ldap
ansible-playbook playbook.yml --limit monitoring
ansible-playbook playbook.yml --limit redmine

# 僅部署特定 role（使用 tags）
ansible-playbook playbook.yml --tags openldap    # FreeIPA
ansible-playbook playbook.yml --tags security    # 防火牆和 SELinux
ansible-playbook playbook.yml --tags backup      # 備份設定
ansible-playbook playbook.yml --tags prometheus  # Prometheus
ansible-playbook playbook.yml --tags grafana    # Grafana
ansible-playbook playbook.yml --tags redmine    # Redmine

# 使用 vault 密碼
ansible-playbook playbook.yml --ask-vault-pass

# 檢查模式（不會實際執行）
ansible-playbook playbook.yml --check --diff
```

## 功能說明

本 playbook 包含三個主要的部署場景，每個場景都有對應的 roles 和 tasks。

### 部署場景 1: LDAP 伺服器（ldap_servers）

部署 FreeIPA 身份管理服務，包含以下 roles：

#### system_setup Role

- 啟用 EPEL repository
- 安裝必要套件
- 設定時區與 NTP
- 確保 SELinux 為 Enforcing 模式

#### openldap Role（FreeIPA）

- 使用 `freeipa.ansible_freeipa.ipaserver` role 部署 FreeIPA Server
- 自動設定 LDAP、Kerberos、CA 等服務
- 初始化 Domain: `qctrd.qct`，Base DN: `dc=qctrd,dc=qct`
- 使用 FreeIPA 預設的 OU 結構：
  - `cn=users,cn=accounts,dc=qctrd,dc=qct`
  - `cn=groups,cn=accounts,dc=qctrd,dc=qct`
  - `cn=services,cn=accounts,dc=qctrd,dc=qct`

#### security Role

- 設定 firewalld 規則：
  - 僅允許管理網段 SSH（22）
  - 僅允許 Redmine 主機連線 LDAPS（636）
  - 僅允許監控主機連線 node_exporter（9100）
- 設定 SELinux boolean 允許 FreeIPA 服務運作

#### backup Role

- 建立每日備份腳本（使用 `ipa-backup` 匯出）
- 備份設定檔與憑證
- 設定 cron job 自動備份
- 自動清理過期備份（保留 30 天，月備份保留 6 個月）

#### monitoring Role

- 安裝並設定 node_exporter（版本 1.7.0）
- 啟動 systemd service
- 監聽 port 9100 提供 metrics

**執行方式：**

```bash
# 部署 LDAP 伺服器
ansible-playbook playbook.yml --limit ldap_servers

# 僅部署特定 role
ansible-playbook playbook.yml --limit ldap_servers --tags openldap
ansible-playbook playbook.yml --limit ldap_servers --tags security
ansible-playbook playbook.yml --limit ldap_servers --tags backup
```

### 部署場景 2: 監控伺服器（monitoring_servers）

部署 Prometheus 和 Grafana 監控服務，包含以下 roles：

#### system_setup Role

- 與 LDAP 伺服器相同的系統基本設定

#### monitoring Role

- 安裝並設定 node_exporter
- 啟動 systemd service

#### prometheus Role

- 從官方下載並安裝 Prometheus（版本 2.48.0）
- 配置 Prometheus 抓取規則
- 自動發現並抓取 LDAP 伺服器的 node_exporter metrics
- 設定防火牆規則（port 9090）
- 設定 SELinux 規則
- 啟動 systemd service

#### grafana Role

- 從官方下載並安裝 Grafana（版本 10.4.2）
- 配置 Grafana 資料來源（自動連線 Prometheus）
- 設定防火牆規則（port 3000）
- 設定 SELinux 規則
- 啟動 systemd service

**執行方式：**

```bash
# 部署監控伺服器
ansible-playbook playbook.yml --limit monitoring_servers

# 僅部署特定 role
ansible-playbook playbook.yml --limit monitoring_servers --tags prometheus
ansible-playbook playbook.yml --limit monitoring_servers --tags grafana
```

### 部署場景 3: Redmine 伺服器（redmine_servers）

部署 Redmine 專案管理系統，包含以下 roles：

#### system_setup Role

- 與其他伺服器相同的系統基本設定

#### redmine Role

此 role 包含完整的 Redmine 部署流程：

**1. SELinux 設定**

- 設定 SELinux context 和 boolean
- 允許 HTTP 服務連接資料庫

**2. 編譯依賴套件安裝**

- 安裝 gcc、make、autoconf 等編譯工具
- 安裝開發套件（openssl-devel、readline-devel 等）

**3. Ruby 編譯安裝（ruby.yml）**

- 從源碼編譯安裝 Ruby 3.4.7
- 安裝到 `/opt/ruby`
- 安裝 Bundler gem

**4. PostgreSQL 16 資料庫安裝（database.yml）**

- 安裝 PostgreSQL 16 伺服器
- 建立 Redmine 資料庫和使用者
- 配置 socket 連線（使用 peer 認證）
- 設定 `pg_hba.conf` 允許 socket 連線

**5. Redis 編譯安裝（redis.yml）**

- 從源碼編譯安裝 Redis 8.2.0
- 安裝到 `/opt/redis`
- 配置 Redis 服務
- 啟動 systemd service

**6. Nginx + Passenger 編譯安裝（nginx_passenger.yml）**

- 安裝 Passenger gem
- 使用 Passenger 編譯安裝 Nginx（含 Passenger 模組）
- 配置 Nginx（配置目錄：`/etc/nginx`）
- 建立 systemd service
- 支援 SSL 配置（可選）

**7. Redmine 應用程式安裝（redmine_install.yml）**

- 下載 Redmine 5.1.2
- 配置資料庫連線（使用 PostgreSQL socket）
- 安裝 Redmine 依賴（Bundler）
- 初始化資料庫（migrate）
- 載入預設資料
- 設定檔案權限
- 配置 LDAP 認證（連線 FreeIPA）

**8. Nginx 虛擬主機配置**

- 建立 Redmine 虛擬主機配置
- 支援 HTTP 和 HTTPS（SSL 可選）
- 配置 Passenger 應用程式環境
- 設定靜態檔案快取和安全標頭

**執行方式：**

```bash
# 部署 Redmine 伺服器
ansible-playbook playbook.yml --limit redmine_servers

# 僅部署特定部分
ansible-playbook playbook.yml --limit redmine_servers --tags redmine
```

## 重要設定

### Base DN

預設 Base DN 為 `dc=qctrd,dc=qct`，可在 `group_vars/all.yml` 中修改。

### 憑證管理

- FreeIPA 自動管理 CA 和憑證
- CA 憑證位置：`/etc/ipa/ca.crt`（需匯出給 Redmine 主機）
- 憑證由 FreeIPA 內建 CA 自動簽發

### 備份

- 備份目錄：`/backup/ldap`
- 備份時間：每日凌晨 2:00
- 保留策略：
  - 每日備份：30 天
  - 月備份：6 個月

### 監控

- node_exporter 監聽 port：9100
- Metrics 端點：`http://<ldap-server>:9100/metrics`

## 驗證部署

### LDAP 伺服器驗證

**檢查服務狀態：**

```bash
# 檢查 FreeIPA 服務狀態
ipa-server-status
systemctl status dirsrv@{{ ipa_realm | lower }}
systemctl status httpd
systemctl status krb5kdc
systemctl status node_exporter
systemctl status firewalld
```

**測試 FreeIPA LDAP 連線：**

```bash
# 測試 LDAPS 連線（使用 Directory Manager）
ldapsearch -x -H ldaps://localhost:636 \
  -D "cn=Directory Manager" \
  -w "your_dm_password" \
  -b "dc=qctrd,dc=qct" \
  -s base "(objectclass=*)"

# 或使用 FreeIPA admin 帳號
ldapsearch -x -H ldaps://localhost:636 \
  -D "uid=admin,cn=users,cn=accounts,dc=qctrd,dc=qct" \
  -w "your_admin_password" \
  -b "dc=qctrd,dc=qct" \
  -s base "(objectclass=*)"
```

**檢查防火牆規則：**

```bash
firewall-cmd --list-all
```

**檢查備份：**

```bash
ls -lh /backup/ldap/
```

### 監控伺服器驗證

**檢查服務狀態：**

```bash
systemctl status node_exporter
systemctl status prometheus
systemctl status grafana
```

**測試 Prometheus：**

```bash
# 檢查 Prometheus Web UI
curl http://localhost:9090

# 檢查 Prometheus targets
curl http://localhost:9090/api/v1/targets

# 檢查 metrics
curl http://localhost:9090/metrics
```

**測試 Grafana：**

```bash
# 檢查 Grafana Web UI
curl http://localhost:3000

# 預設登入資訊
# 使用者名稱: admin
# 密碼: 在 group_vars/all.yml 中設定的 grafana_admin_password
```

### Redmine 伺服器驗證

**檢查服務狀態：**

```bash
systemctl status postgresql-16
systemctl status redis
systemctl status nginx
```

**測試資料庫連線：**

```bash
# 使用 socket 連線測試 PostgreSQL
sudo -u redmine /usr/pgsql-16/bin/psql -d redmine -c "SELECT version();"
```

**測試 Redis：**

```bash
redis-cli ping
# 應該回應: PONG
```

**測試 Nginx：**

```bash
# 檢查 Nginx 配置
/opt/nginx/sbin/nginx -t

# 檢查 Nginx 狀態
curl http://localhost
```

**測試 Redmine：**

```bash
# 檢查 Redmine Web UI
curl http://localhost

# 檢查 Redmine 日誌
tail -f /var/log/redmine/production.log
tail -f /var/log/nginx/redmine_error.log
```

## 後續步驟

### LDAP 伺服器後續設定

1. **匯出 FreeIPA CA 憑證給 Redmine**

   ```bash
   # 從 FreeIPA 伺服器複製 CA 憑證
   scp /etc/ipa/ca.crt user@redmine-host:/tmp/
   ```

2. **驗證備份流程**
   - 檢查 cron job 是否正常執行
   - 測試備份還原流程

### 監控伺服器後續設定

1. **設定 Prometheus 抓取規則**

   - Prometheus 已自動配置抓取 LDAP 伺服器的 node_exporter
   - 可在 `{{ prometheus_config_dir }}/prometheus.yml` 中查看配置

2. **建立 Grafana 儀表板**

   - 登入 Grafana Web UI（預設 http://monitoring-server:3000）
   - 使用預設的 Prometheus 資料來源
   - 建立 node_exporter 儀表板
   - 設定告警規則（磁碟使用率、服務狀態等）

3. **設定 Grafana 通知**
   - 配置 Email、Slack 等通知管道
   - 設定告警規則

### Redmine 伺服器後續設定

1. **設定 Redmine LDAP 整合**

   - Redmine 已自動配置 LDAP 認證
   - 配置檔案位置：`{{ redmine_app_dir }}/config/configuration.yml`
   - 使用 Base DN: `dc=qctrd,dc=qct`
   - 使用 LDAPS: `ldaps://ldap-server:636`
   - 匯入 FreeIPA CA 憑證到系統信任庫

2. **啟用 SSL（可選）**

   - 在 `group_vars/all.yml` 中設定 `nginx_enable_ssl: true`
   - 將 SSL 憑證放置到 `/etc/nginx/ssl/`
   - 重新執行 playbook 或重新載入 Nginx 配置

3. **設定 Redmine 管理員帳號**

   - 首次登入使用預設帳號（需查看 Redmine 安裝日誌）
   - 或使用 LDAP 帳號登入

4. **設定 Redmine 備份**
   - 備份 PostgreSQL 資料庫
   - 備份 Redmine 檔案和附件

## 故障排除

### LDAP 伺服器問題

**SELinux 問題：**

```bash
# 檢查 SELinux 日誌
ausearch -m avc -ts recent

# 如果 FreeIPA 服務無法正常運作，檢查 SELinux boolean
getsebool -a | grep httpd
```

**憑證問題：**

```bash
# 檢查 FreeIPA CA 憑證
ls -la /etc/ipa/ca.crt
# FreeIPA 自動管理憑證，通常不需要手動調整

# 檢查 LDAPS 連線
openssl s_client -connect localhost:636 -showcerts
```

**防火牆問題：**

```bash
# 檢查防火牆規則
firewall-cmd --list-all --zone=public

# 檢查特定 port
firewall-cmd --list-ports
```

### 監控伺服器問題

**Prometheus 無法啟動：**

```bash
# 檢查 Prometheus 配置
/opt/prometheus/prometheus --config.file=/etc/prometheus/prometheus.yml --check-config

# 檢查 Prometheus 日誌
journalctl -u prometheus -f
```

**Grafana 無法連線 Prometheus：**

```bash
# 檢查 Grafana 配置
cat /etc/grafana/grafana.ini | grep prometheus

# 檢查 Grafana 日誌
journalctl -u grafana -f
```

**node_exporter 無法被 Prometheus 抓取：**

```bash
# 檢查 node_exporter 是否正常運行
curl http://ldap-server:9100/metrics

# 檢查 Prometheus targets
curl http://monitoring-server:9090/api/v1/targets | jq
```

### Redmine 伺服器問題

**PostgreSQL 連線問題：**

```bash
# 檢查 PostgreSQL socket
ls -la /var/run/postgresql/.s.PGSQL.5432

# 檢查 pg_hba.conf
cat /var/lib/pgsql/16/data/pg_hba.conf | grep redmine

# 測試 socket 連線
sudo -u redmine /usr/pgsql-16/bin/psql -d redmine -c "SELECT 1;"
```

**Redis 無法啟動：**

```bash
# 檢查 Redis 配置
/opt/redis/bin/redis-server /etc/redis/redis.conf --test-memory 1

# 檢查 Redis 日誌
journalctl -u redis -f
```

**Nginx 無法啟動：**

```bash
# 檢查 Nginx 配置語法
/opt/nginx/sbin/nginx -t

# 檢查 Nginx 錯誤日誌
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/redmine_error.log
```

**Redmine 應用程式問題：**

```bash
# 檢查 Redmine 日誌
tail -f /var/log/redmine/production.log

# 檢查 Redmine 資料庫連線
cd {{ redmine_app_dir }}
sudo -u redmine {{ ruby_install_dir }}/bin/rake db:migrate:status RAILS_ENV=production

# 檢查 Passenger 狀態
/opt/ruby/bin/passenger-status
```

**編譯問題（Ruby/Redis/Nginx）：**

```bash
# 檢查編譯日誌
ls -la /tmp/build/

# 重新編譯（清除舊的編譯結果）
rm -rf /tmp/build/*
# 然後重新執行 playbook
```

## 安全注意事項

1. **密碼管理**：強烈建議使用 `ansible-vault` 加密 `ipadm_password` 和 `ipaadmin_password`
2. **憑證安全**：FreeIPA 自動管理憑證，確保 `/etc/ipa/` 目錄權限正確
3. **網路隔離**：LDAP 伺服器應部署在內網，不直接暴露公網
4. **定期更新**：定期執行 security updates
5. **備份驗證**：定期測試備份還原流程

## 參考文件

- [PRD v1.7](docs/openldap_prd_v1.7.md)
- [FreeIPA 官方文件](https://www.freeipa.org/page/Documentation)
- [FreeIPA Ansible Collection](https://github.com/freeipa/ansible-freeipa)
- [Ansible 文件](https://docs.ansible.com/)

## 授權

本專案為內部使用，請遵守公司資訊安全政策。
