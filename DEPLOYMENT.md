# OpenLDAP 部署指南

本文件提供詳細的部署步驟和注意事項。

## 前置準備

### 1. 環境檢查

確保控制端（Ansible 執行端）已安裝：

```bash
# 檢查 Ansible 版本
ansible --version

# 檢查 Python 版本
python3 --version

# 安裝必要套件（如需要）
pip install -r requirements.txt
```

### 2. 設定主機清單

編輯 `inventory/hosts.yml`：

```yaml
ldap-prod:
  ansible_host: 192.168.1.10  # 更新為實際 IP
  environment: production
```

### 3. 設定變數

#### 基本變數（`group_vars/all.yml`）

必須修改的變數：

- `ldap_admin_password`: **必須使用 ansible-vault 加密**
- `management_networks`: 管理網段列表
- `redmine_hosts`: Redmine 主機 IP
- `gitlab_hosts`: GitLab 主機 IP
- `monitoring_hosts`: 監控主機 IP

#### 使用 Ansible Vault 加密密碼

```bash
# 建立加密的變數檔案
ansible-vault create group_vars/all_vault.yml

# 在編輯器中加入：
ldap_admin_password: "your_secure_password_here"

# 或編輯現有檔案
ansible-vault edit group_vars/all_vault.yml
```

在 `group_vars/all.yml` 中引用：

```yaml
# 從 vault 檔案載入密碼
ldap_admin_password: "{{ vault_ldap_admin_password | default('CHANGE_ME') }}"
```

## 部署步驟

### 步驟 1: 測試連線

```bash
# 測試 SSH 連線
ansible ldap_servers -m ping

# 測試特定主機
ansible ldap-prod -m ping
```

### 步驟 2: 檢查模式執行（Dry Run）

```bash
# 檢查模式（不會實際執行）
ansible-playbook playbook.yml --check --diff
```

### 步驟 3: 完整部署

```bash
# 完整部署（需要 vault 密碼）
ansible-playbook playbook.yml --ask-vault-pass

# 或使用 vault 密碼檔案
ansible-playbook playbook.yml --vault-password-file ~/.vault_pass
```

### 步驟 4: 分階段部署

```bash
# 僅部署系統設定
ansible-playbook playbook.yml --tags system

# 僅部署 OpenLDAP
ansible-playbook playbook.yml --tags openldap

# 僅部署安全性設定
ansible-playbook playbook.yml --tags security

# 僅部署備份
ansible-playbook playbook.yml --tags backup

# 僅部署監控
ansible-playbook playbook.yml --tags monitoring
```

### 步驟 5: 驗證部署

```bash
# 在目標主機上執行
ssh root@ldap-server

# 檢查服務狀態
systemctl status slapd
systemctl status node_exporter
systemctl status firewalld

# 測試 LDAP 連線
ldapsearch -x -H ldaps://localhost:636 \
  -D "cn=admin,dc=qctrd,dc=qct" \
  -w "your_password" \
  -b "dc=qctrd,dc=qct" \
  -s base "(objectclass=*)"

# 檢查防火牆規則
firewall-cmd --list-all

# 檢查備份
ls -lh /backup/ldap/
```

## 常見問題排除

### 問題 1: SELinux 阻擋服務

**症狀**: slapd 無法啟動或無法存取檔案

**解決方案**:

```bash
# 檢查 SELinux 日誌
ausearch -m avc -ts recent

# 設定 SELinux context
restorecon -R /etc/openldap/
restorecon -R /var/lib/ldap/
restorecon -R /var/log/openldap/
```

### 問題 2: 憑證權限問題

**症狀**: LDAPS 連線失敗

**解決方案**:

```bash
# 檢查憑證權限
ls -la /etc/openldap/certs/

# 修正權限
chown ldap:ldap /etc/openldap/certs/*
chmod 600 /etc/openldap/certs/*.key
chmod 644 /etc/openldap/certs/*.crt
```

### 問題 3: 防火牆阻擋連線

**症狀**: 無法從外部連線 LDAPS

**解決方案**:

```bash
# 檢查防火牆規則
firewall-cmd --list-all

# 手動加入規則（如果需要）
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.30" port port="636" protocol="tcp" accept'
firewall-cmd --reload
```

### 問題 4: LDAP 資料庫初始化失敗

**症狀**: Base DN 或 OU 無法建立

**解決方案**:

```bash
# 檢查 slapd 日誌
tail -f /var/log/openldap/slapd.log

# 手動建立 Base DN
ldapadd -x -D "cn=admin,dc=qctrd,dc=qct" \
  -w "your_password" \
  -H ldaps://localhost:636 \
  -f /tmp/base.ldif
```

## 後續設定

### 1. 匯出 CA 憑證給 Redmine/GitLab

```bash
# 從 LDAP 伺服器複製 CA 憑證
scp /etc/openldap/certs/ca.crt user@redmine-host:/tmp/

# 在 Redmine/GitLab 主機上
# Redmine (Ruby)
sudo cp /tmp/ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# GitLab (通常使用系統 CA store)
sudo cp /tmp/ca.crt /etc/ssl/certs/
sudo update-ca-certificates
```

### 2. 設定 Prometheus 抓取 node_exporter

在 Prometheus 設定檔 (`prometheus.yml`) 中加入：

```yaml
scrape_configs:
  - job_name: 'ldap-servers'
    static_configs:
      - targets:
        - 'ldap-prod:9100'
        - 'ldap-test:9100'
```

### 3. 建立 Grafana 儀表板

使用 node_exporter metrics 建立監控儀表板，監控項目包括：

- CPU 使用率
- 記憶體使用率
- 磁碟使用率
- 網路流量
- slapd 服務狀態

### 4. 設定告警規則

在 Prometheus 中設定告警規則：

```yaml
groups:
  - name: ldap_alerts
    rules:
      - alert: LDAPServiceDown
        expr: up{job="ldap-servers"} == 0
        for: 5m
        annotations:
          summary: "LDAP 服務已停止"
      
      - alert: LDAPDiskSpaceHigh
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.2
        for: 5m
        annotations:
          summary: "LDAP 伺服器磁碟空間不足"
```

## 維護作業

### 定期備份驗證

```bash
# 手動執行備份
/usr/local/bin/backup_ldap.sh

# 檢查備份檔案
ls -lh /backup/ldap/

# 測試還原（在測試環境）
# 1. 停止 slapd
systemctl stop slapd

# 2. 清除現有資料
rm -rf /var/lib/ldap/*

# 3. 還原備份
slapadd -l /backup/ldap/ldap_backup_YYYYMMDD_HHMMSS/ldap_data.ldif

# 4. 啟動服務
systemctl start slapd
```

### 憑證更新

憑證有效期為 3 年，到期前需要更新：

```bash
# 1. 產生新憑證（使用 playbook 或手動）
# 2. 更新 slapd 設定
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/new_tls_config.ldif

# 3. 重啟服務
systemctl restart slapd

# 4. 驗證連線
ldapsearch -x -H ldaps://localhost:636 ...
```

### 日誌輪替

日誌會自動輪替（透過 logrotate），但可以手動檢查：

```bash
# 檢查日誌大小
du -sh /var/log/openldap/

# 手動輪替（如果需要）
logrotate -f /etc/logrotate.d/slapd
```

## 安全建議

1. **定期更新系統套件**
   ```bash
   dnf update --security
   ```

2. **審查防火牆規則**
   ```bash
   firewall-cmd --list-all
   ```

3. **檢查 SELinux 狀態**
   ```bash
   getenforce  # 應顯示 Enforcing
   ```

4. **審查 LDAP 存取日誌**
   ```bash
   tail -f /var/log/openldap/slapd.log
   ```

5. **定期檢查備份完整性**
   ```bash
   # 驗證備份檔案
   tar -tzf /backup/ldap/ldap_backup_*.tar.gz
   ```

## 支援與文件

- [PRD v1.7](docs/openldap_prd_v1.7.md)
- [OpenLDAP 官方文件](https://www.openldap.org/doc/)
- [Ansible 文件](https://docs.ansible.com/)

