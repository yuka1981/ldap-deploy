# 修正摘要：群組建立問題

## 🔴 問題描述

在 monitoring server 上執行部署時遇到錯誤：
```
TASK [prometheus : 建立 Prometheus 使用者]
fatal: [monitoring]: FAILED! => changed=false 
  msg: Group prometheus does not exist
```

## ✅ 根本原因

多個 role 在建立使用者時，沒有先建立對應的群組。Ansible 的 `user` 模組在指定 `group` 參數時，如果群組不存在會導致失敗。

## 🔧 修正內容

### 1. Prometheus Role
**檔案**：`roles/prometheus/tasks/main.yml`

**修正前**：
```yaml
- name: 建立 Prometheus 使用者
  ansible.builtin.user:
    name: '{{ prometheus_user }}'
    group: '{{ prometheus_group }}'  # 群組不存在會失敗
```

**修正後**：
```yaml
- name: 建立 Prometheus 群組
  ansible.builtin.group:
    name: '{{ prometheus_group }}'
    system: true
    state: present

- name: 建立 Prometheus 使用者
  ansible.builtin.user:
    name: '{{ prometheus_user }}'
    group: '{{ prometheus_group }}'
```

### 2. Grafana Role
**檔案**：`roles/grafana/tasks/main.yml`

**修正**：在建立使用者之前先建立群組

### 3. Redmine Role
**檔案**：`roles/redmine/tasks/main.yml`

**修正**：在建立使用者之前先建立群組

## ✅ 驗證部署邏輯

### Monitoring Servers 部署順序
```
system_setup → monitoring → prometheus → grafana
```

**依賴關係**：
- `monitoring` 生成 CA 憑證
- `prometheus` 和 `grafana` 需要 CA 憑證來驗證 node_exporter

### LDAP Servers 部署順序
```
system_setup → security → openldap → monitoring → backup
```

**依賴關係**：
- `security` 設定防火牆規則（必須在 `openldap` 之前）
- `openldap` 部署 FreeIPA 服務
- `monitoring` 部署 node_exporter（需要防火牆規則允許）
- `backup` 設定備份（需要所有服務運行）

### Redmine Servers 部署順序
```
system_setup → monitoring → redmine
```

**依賴關係**：
- `monitoring` 部署 node_exporter
- `redmine` 部署 Redmine 應用程式

## 📋 檢查清單

- [x] Prometheus role 先建立群組再建立使用者
- [x] Grafana role 先建立群組再建立使用者
- [x] Redmine role 先建立群組再建立使用者
- [x] Monitoring role 已有正確的群組建立邏輯（無需修正）
- [x] 所有 linter 檢查通過
- [x] 部署順序邏輯正確

## 🎯 最佳實踐

1. **總是先建立群組**：在使用 `ansible.builtin.user` 模組時，如果指定 `group` 參數，必須先確保群組存在
2. **使用 system 群組**：對於系統服務帳號，使用 `system: true` 建立系統群組
3. **保持一致性**：所有 role 都應該遵循相同的模式：先建立群組，再建立使用者

## 📝 相關檔案

- `roles/prometheus/tasks/main.yml`
- `roles/grafana/tasks/main.yml`
- `roles/redmine/tasks/main.yml`
- `roles/monitoring/tasks/main.yml` (參考範例)

