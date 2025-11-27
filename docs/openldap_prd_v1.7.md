# OpenLDAP for Production – PRD v1.7

## 1. 專案概述

- **專案名稱**：OpenLDAP 目錄服務建置（Production 用）  
- **目的**：  
  - 建立一套穩定、安全的 LDAP 目錄服務，作為公司內部系統的 **統一帳號與認證中樞**。  
  - 首波整合 **Redmine** 與 **GitLab**，未來可擴充至其他內部系統。  
- **目前使用規模**：  
  - 使用者數量級：**少於 50 個帳號**  
  - 短期整合系統：Redmine（規劃中）、GitLab（規劃中）  

## 2. 需求範圍與非目標

- **此專案涵蓋：**
  - 在 Rocky Linux 10 上部署 OpenLDAP（含 LDAPS）
  - 啟用 SELinux（Enforcing）
  - 與 Redmine / GitLab 的 LDAP 整合（認證 + 首次登入自動建立帳號）
  - 基本備份 / 還原、監控、Logging/Audit 的規劃與實作
- **不在此階段範圍（Phase 1 非目標）：**
  - 多台 LDAP 高可用（HA / Multi-master）
  - 與 AD / HR 系統的自動同步
  - LDAP 群組驅動的細粒度授權（Authorization 由各應用自行管理）

## 3. 環境區分

- **Production LDAP（正式環境）**
  - 提供實際 Redmine / GitLab 正式服務使用。
  - Base DN：`dc=qctrd,dc=qct`
- **Test / Staging LDAP（測試環境）**
  - 用途：
    - 測試 OpenLDAP 設定、schema / config 變更
    - 測試 Redmine / GitLab 串接
    - 演練備份與還原流程
  - 結構建議與 Production 一致（同樣使用 `dc=qctrd,dc=qct`），但資料與 VM 獨立。

## 4. 部署平台與資源規劃

- **虛擬化平台**：VMware ESXi
- **Production LDAP VM 建議規格**
  - vCPU：4 vCPU  
  - RAM：8 GB  
  - Disk：100 GB（OS + LDAP DB + log）
- **Test LDAP VM 建議規格**
  - vCPU：2–4 vCPU  
  - RAM：4–8 GB  
  - Disk：50–100 GB  
- VM 由基礎架構團隊統一管理（含 snapshot 與 host-level 監控）。

## 5. OS 與系統基本設定

- **OS**：Rocky Linux 10
- **Repository**：
  - 啟用官方 repo
  - 啟用 **EPEL repository**
- **系統硬化（基本）**：
  - 僅開放必要 port：
    - SSH（22）限管理網段
    - LDAPS（636）限 Redmine / GitLab / 測試 / 監控相關主機
  - 定期套件更新（security update），排程於非尖峰時段。

## 6. 網路拓樸與存取控制

- **LDAP 伺服器位置**：
  - 部署於內網 VLAN，不對公網直接暴露。
- **存取策略**：
  - 由 Redmine / GitLab VM 透過內網使用 **加密連線（LDAPS）** 連至 LDAP。
  - 公網 → LDAP：全部阻擋。
  - 僅允許：
    - Redmine / GitLab VM → LDAP：TCP 636
    - 管理網段 → LDAP VM：SSH / 管理用途
- **Redmine / GitLab 對外**：
  - 對外提供 HTTPS 服務給使用者登入，系統在內部再打 LDAP。

## 7. 安全性設計

### 7.1 SELinux

- **模式**：SELinux 必須為 **Enforcing**。
- 如有自訂 path 或 port，需：
  - 定義對應 SELinux context / booleans / policy。
  - 確保 slapd / LDAPS 運作正常。

### 7.2 加密（LDAPS / TLS）

- 僅允許使用 **LDAPS（TCP 636）** 或 LDAP + StartTLS。
- 若 389 必須啟用，須明確限制用途與來源，並在實作文件註明。

### 7.3 憑證策略（自簽）

- 使用 **自簽憑證（self-signed）或內部簡易 CA**：
  - 在 LDAP Server 產生伺服器憑證與私鑰供 LDAPS 使用。
  - Redmine / GitLab 主機匯入該 CA 憑證，加入信任庫。
- 建議有效期：1–3 年。
- 必須有：
  - 憑證到期追蹤方式（文件或監控／自訂腳本，後續可強化）。
  - 換證流程（產生新憑證 → 更新 slapd 設定 → 驗證 Redmine / GitLab 連線）。

## 8. 目錄結構（DIT）與命名規則

### 8.1 Base DN

- Base DN：`dc=qctrd,dc=qct`
- 與舊系統 (`dc=qpdm,dc=qct`) 不同，需在遷移 / 共存策略中註明。

### 8.2 OU 結構

- 使用者：
  - OU：`ou=People,dc=qctrd,dc=qct`
  - 使用者 DN：
    - `uid={username},ou=People,dc=qctrd,dc=qct`
- 群組（預留）：
  - OU：`ou=Groups,dc=qctrd,dc=qct`
  - 群組 DN 範例：
    - `cn={groupname},ou=Groups,dc=qctrd,dc=qct`
- 其他建議 OU：
  - `ou=ServiceAccounts,dc=qctrd,dc=qct`（系統 / Service 帳號）

### 8.3 帳號命名（uid）

- 格式：`firstname.lastname`
- 字母：全部小寫英文。
- 例：
  - 王大明 → `daming.wang`
  - 林小華 → `xiaohua.lin`
- 命名衝突處理：
  - 透過加數字或額外字元，例如 `daming.wang2`。

## 9. 帳號管理與密碼政策

### 9.1 帳號管理模式

- 初期採 **手動管理**：
  - 管理員手動建立 / 更新 / 停用帳號與群組（CLI 或 Web 工具）。
  - 可選工具（實作階段決定）：`ldapadd` / `ldapmodify` / phpldapadmin / LDAP Account Manager。
- 帳號生命週期：
  - 建立：依申請，由管理員建 LDAP 帳號。
  - 停用：離職或不再使用時，手動停用 / 刪除。
  - 權限：透過 Redmine / GitLab 內部角色管理（LDAP 不管授權）。

### 9.2 密碼政策（Phase 1）

- 最低長度：**8 字元**
- 至少包含：
  - 英文字母
  - 數字  
- 允許但不強制特殊符號。
- 不強制密碼週期到期（未導入 90/180 天到期之類）。
- 建議高權限帳號（例如管理 DN）採更強密碼（長度更長 / 更複雜）。

## 10. Redmine / GitLab LDAP 整合需求

- **認證（Authentication）**
  - 使用 LDAP / LDAPS 驗證 `uid=firstname.lastname` + 密碼。
  - LDAP 提供屬性：
    - `uid`、姓名（`cn` / `givenName` + `sn`）、`mail` 等。
- **自動建立帳號**
  - 啟用「首次登入自動建立使用者」：
    - LDAP 驗證成功時，Redmine / GitLab 自動建立本地帳號：
      - Redmine / GitLab 使用者名稱對應 LDAP `uid`。
      - 顯示名稱、Email 依 LDAP 屬性填入（若有）。
- **授權（Authorization）**
  - Phase 1：權限完全由 Redmine / GitLab 內部管理：
    - Redmine：角色 / 專案成員由管理員設定。
    - GitLab：Group / Project 角色由管理員設定。
  - LDAP 群組暫不綁定至系統角色（保留未來擴充空間）。

## 11. 可用性與備援

- 等級：**中等重要（Level B）**
  - 允許排程維護停機（非工作時間）。
  - 非預期 downtime 目標：一年內控制在數小時等級。
- 故障復原手段：
  - VM snapshot 作為快速復原輔助。
  - 搭配 LDAP 定期備份（見下一節）。

## 12. 備份與還原策略

- **備份範圍**：
  - LDAP 資料（`slapcat` 匯出）。
  - 設定檔（`cn=config` 或 `/etc/openldap/*` 等）。
  - LDAPS 憑證與私鑰。
- **備份頻率**：
  - 每日自動備份一次（排程於非尖峰時段）。
- **保留策略**：
  - 每日備份保留 **30 天**。
  - 每月擇一備份標記為「月備份」，保留 **6–12 個月**（實作時決定具體值）。
- **備份存放位置**：
  - 儲存在與 LDAP VM 不同的儲存設備（備份專用存放區 / NFS / 專用 backup server）。
- **RPO / RTO 目標**：
  - RPO：可接受最多回朔 1 天內的變更。
  - RTO：目標為數小時內可恢復服務（視實際流程而定）。

## 13. 監控與告警（Prometheus + Grafana）

- **監控平台**：
  - 另建一台 VM 安裝：
    - Prometheus
    - Grafana
  - 未來可監控 LDAP / Redmine / GitLab / 其他服務。
- **LDAP VM 監控項目**：
  - 系統：
    - CPU / Load / RAM / Disk 使用率
    - 網路介面流量
  - 服務：
    - slapd process 存活
    - LDAPS 636 連線可用性（建議透過 blackbox_exporter）。
- **告警（初始）**：
  - LDAP VM 不可達（node_exporter 掛 / ping 不通）。
  - LDAPS 探測失敗（連續多次 timeout / connection refused）。
  - 磁碟使用率：
    - > 80%：warning
    - > 90%：critical
- **實作方向**：
  - LDAP VM 安裝 node_exporter。
  - 監控 VM 安裝 blackbox_exporter，對 LDAP 的 LDAPS 做探測。
  - Grafana 建立 LDAP 監控儀表板。

## 14. Logging 與 Audit

- **目標等級**：診斷 + 基本安全稽核。
- **記錄內容**：
  - slapd 啟動 / 停止 / 錯誤 / 警告。
  - LDAP bind 失敗與錯誤（可用來偵測暴力攻擊或設定錯誤）。
  - 管理操作（schema / 重要設定變更）需能被追蹤（必要時評估使用 `auditlog` / `accesslog` overlay 作為後續強化項目）。
- **保留時間**：
  - LDAP 相關 log 保留 **至少 3 個月**。
  - 使用 logrotate 或等效機制輪替與壓縮。
- **磁碟控管**：
  - 透過監控追蹤 log 導致的磁碟使用率。
  - 若 log 量過大，需調整 log 細節或擴增磁碟。

## 15. 驗收標準（Definition of Done）

### 15.1 功能驗收

- 在 **Test 環境**：
  - 可以建立 / 修改 / 刪除使用者與群組，並可由 LDAP 查詢到正確資料。
  - LDAPS（636）運作正常，自簽憑證被 Redmine / GitLab 測試主機信任。
- 在 **Production 環境**：
  - 使用 LDAP 帳號可成功登入 Redmine。
  - 使用 LDAP 帳號可成功登入 GitLab。
  - 首次登入時，Redmine / GitLab 會自動建立本地帳號，屬性（顯示名稱 / Email）正常帶入。

### 15.2 備份 / 還原驗收

- 從 Production 執行完整備份（含資料 + 設定 + 憑證）。
- 將備份還原至 Test 環境：
  - 還原後的 LDAP 資料與結構完整。
  - Test Redmine / GitLab 對還原後 LDAP 驗證成功。

### 15.3 監控驗收

- 在 Test 環境：
  - Prometheus 能成功抓取 Test LDAP VM 的 node_exporter metrics。
  - blackbox_exporter 能成功探測 Test LDAP 的 LDAPS 636。
  - 停止 Test 環境 slapd 服務時：
    - Prometheus / Grafana 顯示服務 down。
    - 對應告警規則觸發（若已設告警管道）。
- 在 Production 環境（受控測試）：
  - 模擬短暫服務中斷（例如停止 slapd 或暫時阻擋 636）：
    - 監控面板能顯示 LDAP 服務狀態變為 down。
    - 告警規則如預期觸發（至少在測試期間）。

### 15.4 安全驗收

- SELinux 設定為 Enforcing，且 slapd / LDAPS 運作正常。
- Firewalld / ACL 已正確限制：
  - 公網無法直接連至 LDAP。
  - 僅 Redmine / GitLab / 管理網段可存取必要 port。
- 自簽憑證部署完成，Redmine / GitLab 能成功建立 TLS 連線。
