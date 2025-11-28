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
│   └── monitoring/          # 監控設定（node_exporter）
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
  ansible-galaxy collection install -r collections.yml
  ```

### 目標主機（LDAP 伺服器）

- Rocky Linux 10
- 至少 4 vCPU、8 GB RAM、100 GB Disk（Production）
- 網路連線（可存取 EPEL repository）
- Root 或 sudo 權限

## 快速開始

### 1. 設定主機清單

編輯 `inventory/hosts.yml`，更新主機 IP 和相關設定：

```yaml
ldap-prod:
  ansible_host: 192.168.1.10  # 更新為實際 IP
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
- `gitlab_hosts`: GitLab 主機 IP 列表
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
# 完整部署
ansible-playbook playbook.yml

# 僅部署特定 role
ansible-playbook playbook.yml --tags openldap

# 使用 vault 密碼
ansible-playbook playbook.yml --ask-vault-pass

# 僅針對測試環境
ansible-playbook playbook.yml --limit ldap-test
```

## 功能說明

### system_setup Role

- 啟用 EPEL repository
- 安裝必要套件
- 設定時區與 NTP
- 確保 SELinux 為 Enforcing 模式

### openldap Role（FreeIPA）

- 使用 `freeipa.ansible_freeipa.ipaserver` role 部署 FreeIPA Server
- 自動設定 LDAP、Kerberos、CA 等服務
- 初始化 Domain: `qctrd.qct`，Base DN: `dc=qctrd,dc=qct`
- 使用 FreeIPA 預設的 OU 結構：
  - `cn=users,cn=accounts,dc=qctrd,dc=qct`
  - `cn=groups,cn=accounts,dc=qctrd,dc=qct`
  - `cn=services,cn=accounts,dc=qctrd,dc=qct`

### security Role

- 設定 firewalld 規則：
  - 僅允許管理網段 SSH（22）
  - 僅允許 Redmine/GitLab 主機連線 LDAPS（636）
  - 僅允許監控主機連線 node_exporter（9100）
- 設定 SELinux boolean 允許 FreeIPA 服務運作

### backup Role

- 建立每日備份腳本（使用 `ipa-backup` 匯出）
- 備份設定檔與憑證
- 設定 cron job 自動備份
- 自動清理過期備份（保留 30 天，月備份保留 6 個月）

### monitoring Role

- 安裝並設定 node_exporter
- 啟動 systemd service
- 開放防火牆 port 9100 給監控主機

## 重要設定

### Base DN

預設 Base DN 為 `dc=qctrd,dc=qct`，可在 `group_vars/all.yml` 中修改。

### 憑證管理

- FreeIPA 自動管理 CA 和憑證
- CA 憑證位置：`/etc/ipa/ca.crt`（需匯出給 Redmine/GitLab 主機）
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

### 檢查服務狀態

```bash
# 檢查 FreeIPA 服務狀態
ipa-server-status
systemctl status dirsrv@{{ ipa_realm | lower }}
systemctl status httpd
systemctl status krb5kdc
systemctl status node_exporter
systemctl status firewalld
```

### 測試 FreeIPA LDAP 連線

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

### 檢查防火牆規則

```bash
firewall-cmd --list-all
```

### 檢查備份

```bash
ls -lh /backup/ldap/
```

## 後續步驟

1. **匯出 FreeIPA CA 憑證給 Redmine/GitLab**
   ```bash
   # 從 FreeIPA 伺服器複製 CA 憑證
   scp /etc/ipa/ca.crt user@redmine-host:/tmp/
   ```

2. **設定 Redmine/GitLab LDAP 整合**
   - 使用 Base DN: `dc=qctrd,dc=qct`
   - 使用 LDAPS: `ldaps://ldap-server:636`
   - 匯入 CA 憑證到信任庫

3. **設定 Prometheus 抓取 node_exporter**
   - 在 Prometheus 設定檔中加入 LDAP 伺服器作為 target

4. **建立 Grafana 儀表板**
   - 使用 node_exporter metrics
   - 設定告警規則（磁碟使用率、服務狀態等）

## 故障排除

### SELinux 問題

如果 FreeIPA 服務無法正常運作，檢查 SELinux 日誌：

```bash
ausearch -m avc -ts recent
```

### 憑證問題

如果 LDAPS 連線失敗，檢查 FreeIPA CA 憑證：

```bash
ls -la /etc/ipa/ca.crt
# FreeIPA 自動管理憑證，通常不需要手動調整
```

### 防火牆問題

如果無法連線，檢查防火牆規則：

```bash
firewall-cmd --list-all --zone=public
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

