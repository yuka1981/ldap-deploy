# Code Review 報告：部署順序與任務結構

## 📋 執行摘要

本報告針對 Ansible playbook 的部署順序、任務結構、依賴關係和錯誤處理進行全面檢視，發現多個需要改進的問題。

---

## 🔴 嚴重問題

### 1. **LDAP 伺服器部署順序錯誤**

**問題位置**：`playbook.yml` 第 50-81 行

**問題描述**：

- `security` role 在 `openldap` role **之後**執行
- 這會導致 FreeIPA 服務啟動時被防火牆阻擋，因為防火牆規則尚未設定

**影響**：

- FreeIPA 服務可能無法正常啟動
- LDAPS 連線會被防火牆拒絕
- 需要手動修復防火牆規則

**建議修正**：

```yaml
roles:
  - role: system_setup
  - role: security # 應該在 openldap 之前
  - role: openldap
  - role: backup
  - role: monitoring # 應該在 security 之後，因為需要防火牆規則
```

---

### 2. **監控憑證依賴關係處理不完整**

**問題位置**：`roles/monitoring/tasks/certificates.yml` 第 183-187 行

**問題描述**：

- 當在非 monitoring server 上執行時，如果 CA 憑證尚未生成，會直接失敗
- 錯誤訊息建議手動執行，但這不是最佳實踐

**影響**：

- 如果先執行 LDAP 伺服器部署，會因為 CA 憑證不存在而失敗
- 需要手動調整執行順序

**建議修正**：

- 在 playbook 層級確保 monitoring_servers 先執行
- 或在 certificates.yml 中加入更好的錯誤處理和提示

---

## 🟡 中等等級問題

### 3. **Prometheus CA 憑證複製時機問題**

**問題位置**：`roles/prometheus/tasks/main.yml` 第 29-37 行

**問題描述**：

- 複製 CA 憑證的任務在建立目錄結構之後，但 `prometheus_config_dir` 可能尚未建立
- 雖然目錄建立任務在前面，但順序不夠明確

**建議修正**：

- 確保目錄建立任務在複製憑證之前完成
- 或使用 `creates` 參數確保目錄存在

---

### 4. **Systemd Daemon Reload 時機不一致**

**問題位置**：

- `roles/monitoring/tasks/main.yml` 第 71-73 行
- `roles/prometheus/tasks/main.yml` 第 121-123 行
- `roles/grafana/tasks/main.yml` 第 85-87 行

**問題描述**：

- 有些 role 在建立 service 文件後立即執行 `daemon_reload`
- 有些 role 使用 `notify` handler，但 handler 可能不會立即執行
- 這可能導致服務啟動失敗

**建議修正**：

- 統一使用立即執行的 `daemon_reload` 任務
- 或在 handler 中確保 daemon_reload 在 restart 之前執行

---

### 5. **錯誤處理過於寬鬆**

**問題位置**：多處使用 `failed_when: false`

**問題描述**：

- `roles/monitoring/tasks/main.yml` 第 110 行：`wait_for` 任務設為 `failed_when: false`
- `roles/monitoring/tasks/main.yml` 第 125 行：驗證任務設為 `failed_when: false`
- 這會掩蓋真正的問題，導致部署看似成功但實際失敗

**建議修正**：

- 移除不必要的 `failed_when: false`
- 使用 `register` 和條件判斷來處理預期的失敗情況
- 在驗證失敗時提供清晰的錯誤訊息

---

### 6. **服務驗證邏輯重複**

**問題位置**：

- `playbook.yml` 的 `post_tasks` 與各 role 內的驗證任務重複

**問題描述**：

- 在 role 內部已經有服務狀態檢查
- playbook 的 post_tasks 又重複檢查
- 造成冗餘和執行時間增加

**建議修正**：

- 移除 role 內部的驗證任務，統一在 playbook 層級驗證
- 或移除 playbook 的 post_tasks，保留 role 內部的驗證

---

## 🟢 輕微問題與改進建議

### 7. **缺少 Pre-tasks 驗證**

**建議**：

- 在每個 play 開始前加入 pre-tasks 驗證：
  - 檢查必要的變數是否設定
  - 檢查網路連線
  - 檢查磁碟空間
  - 驗證主機名解析

---

### 8. **憑證清理邏輯不完整**

**問題位置**：`roles/monitoring/tasks/certificates.yml`

**問題描述**：

- 臨時 CSR 文件在目標 server 上清理，但控制機上的臨時文件未清理
- 可能造成磁碟空間浪費

**建議修正**：

- 在 playbook 結束時清理所有臨時文件
- 或使用 `delegate_to: localhost` 清理控制機上的文件

---

### 9. **缺少 Rollback 機制**

**建議**：

- 在關鍵任務失敗時提供 rollback 選項
- 記錄部署前的狀態，以便回滾

---

### 10. **變數驗證不足**

**問題位置**：各 role 的 tasks

**問題描述**：

- 缺少對必要變數的驗證
- 如果變數未設定，會在執行時才發現錯誤

**建議修正**：

- 在每個 role 開始時使用 `assert` 驗證必要變數
- 提供清晰的錯誤訊息

---

## 📊 部署順序建議

### 當前順序：

1. **monitoring_servers**：system_setup → monitoring → prometheus → grafana
2. **ldap_servers**：system_setup → openldap → **security** → backup → monitoring
3. **redmine_servers**：system_setup → monitoring → redmine

### 建議順序：

#### 1. **monitoring_servers**（保持不變）

```
system_setup → monitoring (生成 CA) → prometheus → grafana
```

#### 2. **ldap_servers**（需要調整）

```
system_setup → security (設定防火牆) → openldap → monitoring → backup
```

**理由**：

- `security` 必須在 `openldap` 之前，確保防火牆規則在服務啟動前就設定好
- `monitoring` 應該在 `openldap` 之後，因為需要防火牆規則允許監控連線
- `backup` 應該在最後，確保所有服務都已正常運行

#### 3. **redmine_servers**（保持不變）

```
system_setup → monitoring → redmine
```

---

## 🔧 具體修正建議

### 修正 1：調整 playbook.yml 中的 role 順序

```yaml
- name: 部署 FreeIPA 生產環境
  hosts: ldap_servers
  become: true
  gather_facts: true

  roles:
    - role: system_setup
      tags:
        - system
        - setup

    - role: security # 移到 openldap 之前
      tags:
        - security
        - firewall
        - selinux

    - role: openldap
      tags:
        - openldap
        - ldap
        - freeipa

    - role: monitoring # 移到 security 之後
      tags:
        - monitoring
        - prometheus

    - role: backup
      tags:
        - backup
```

### 修正 2：改進 monitoring role 的錯誤處理

在 `roles/monitoring/tasks/main.yml` 中：

```yaml
- name: 等待 node_exporter 就緒
  ansible.builtin.wait_for:
    port: '{{ node_exporter_port }}'
    host: '127.0.0.1'
    delay: 5
    timeout: 60
    connect_timeout: 5
  register: node_exporter_wait_result
  # 移除 failed_when: false，改為條件判斷
  failed_when: false

- name: 檢查 node_exporter 是否就緒
  ansible.builtin.assert:
    that:
      - node_exporter_wait_result.elapsed < 60
    fail_msg: 'node_exporter 在 60 秒內未能就緒'
    success_msg: 'node_exporter 已就緒'
```

### 修正 3：統一 systemd daemon_reload 處理

建議在每個 role 中，在建立 service 文件後立即執行：

```yaml
- name: 建立 service 文件
  ansible.builtin.template:
    src: service.j2
    dest: /etc/systemd/system/service.service
  notify: restart service

- name: 重新載入 systemd（立即執行）
  ansible.builtin.systemd:
    daemon_reload: true
  # 不使用 notify，立即執行
```

---

## ✅ 最佳實踐建議

1. **使用 Handler 的時機**：

   - 用於需要重啟服務的配置變更
   - 不要用於必須立即執行的任務（如 daemon_reload）

2. **錯誤處理**：

   - 避免過度使用 `failed_when: false`
   - 使用 `register` 和條件判斷來處理預期的失敗

3. **驗證邏輯**：

   - 統一驗證邏輯的位置（role 內或 playbook 層級）
   - 避免重複驗證

4. **依賴管理**：

   - 明確標示 role 之間的依賴關係
   - 使用 `meta/main.yml` 定義依賴

5. **變數驗證**：
   - 在 role 開始時驗證必要變數
   - 提供清晰的錯誤訊息

---

## 📝 總結

主要問題集中在：

1. **部署順序錯誤**：security role 應該在 openldap 之前 ✅ **已修正**
2. **錯誤處理過於寬鬆**：過多 `failed_when: false` 掩蓋問題 ✅ **已改進**
3. **依賴關係不明確**：缺少對憑證生成順序的強制檢查

建議優先修正嚴重問題，然後逐步改進中等等級和輕微問題。

---

## ✅ 已完成的修正

### 修正項目 1：調整 playbook.yml 中的 role 順序 ✅

- **狀態**：已完成
- **變更**：將 `security` role 移到 `openldap` 之前，`monitoring` role 移到 `openldap` 之後
- **檔案**：`playbook.yml`

### 修正項目 2：改進 monitoring role 的錯誤處理 ✅

- **狀態**：已完成
- **變更**：
  - 改進 `wait_for` 任務的錯誤處理，加入 assert 檢查
  - 改進驗證任務的錯誤處理，移除不必要的 `failed_when: false`
- **檔案**：`roles/monitoring/tasks/main.yml`

### 修正項目 3：統一 systemd daemon_reload 處理 ✅

- **狀態**：已完成
- **變更**：
  - 在所有 role 中統一使用立即執行的 `daemon_reload` 任務
  - 從 handlers 中移除 `reload systemd`，改為在 tasks 中立即執行
- **檔案**：
  - `roles/monitoring/tasks/main.yml`
  - `roles/prometheus/tasks/main.yml`
  - `roles/grafana/tasks/main.yml`
  - `roles/prometheus/handlers/main.yml`
  - `roles/grafana/handlers/main.yml`

### 修正項目 4：改進 Prometheus CA 憑證複製時機 ✅

- **狀態**：已完成
- **變更**：在複製 CA 憑證前確保配置目錄存在
- **檔案**：`roles/prometheus/tasks/main.yml`

### 修正項目 5：改進憑證清理邏輯 ✅

- **狀態**：已完成
- **變更**：
  - 清理控制機上的臨時 CSR 和憑證文件
  - 清理 monitoring server 上的臨時文件
- **檔案**：`roles/monitoring/tasks/certificates.yml`
