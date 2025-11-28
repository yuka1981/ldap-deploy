# Ansible Collections 安裝指南

## 問題說明

如果在安裝 Ansible Collections 時遇到 SSL 證書驗證失敗的錯誤：

```
ERROR! Unknown error when attempting to call Galaxy at 'https://galaxy.ansible.com/api/': 
<urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: 
unable to get local issuer certificate (_ssl.c:997)>
```

這通常是因為 Python 環境缺少系統 SSL 證書。

## 解決方案

### 方案 1: 更新 Python SSL 證書（推薦）

**macOS:**
```bash
# 如果使用 Python.org 安裝的 Python
/Applications/Python\ 3.*/Install\ Certificates.command

# 或使用 pip 更新證書
pip3 install --upgrade certifi
```

**Linux:**
```bash
# 更新系統 CA 證書
sudo update-ca-certificates

# 或使用 pip 更新證書
pip3 install --upgrade certifi
```

### 方案 2: 手動安裝 Collections

如果方案 1 仍然無法解決問題，可以使用手動安裝腳本：

```bash
./install-collections-manual.sh
```

或手動逐一安裝：

```bash
ansible-galaxy collection install freeipa.ansible_freeipa --force
ansible-galaxy collection install community.crypto --force
ansible-galaxy collection install community.general --force
ansible-galaxy collection install community.postgresql --force
ansible-galaxy collection install ansible.posix --force
```

### 方案 3: 使用 pip 直接安裝（如果可用）

某些 collections 可以通過 pip 安裝：

```bash
pip3 install ansible-freeipa
```

### 方案 4: 設定代理或使用 VPN

如果是在受限的網路環境中，可能需要設定代理或使用 VPN。

## 驗證安裝

安裝完成後，驗證 collections 是否已正確安裝：

```bash
ansible-galaxy collection list | grep -E "(freeipa|community|ansible.posix)"
```

應該看到以下 collections：
- `freeipa.ansible_freeipa`
- `community.crypto`
- `community.general`
- `community.postgresql`
- `ansible.posix`

## 常見問題

### Q: 為什麼會出現 SSL 證書錯誤？

A: 這通常是因為：
1. Python 環境缺少系統 CA 證書
2. 系統時間不正確
3. 網路環境限制（公司防火牆等）

### Q: 如何確認問題已解決？

A: 執行以下命令測試：
```bash
ansible-galaxy collection install freeipa.ansible_freeipa --force
```

如果沒有錯誤訊息，表示問題已解決。

