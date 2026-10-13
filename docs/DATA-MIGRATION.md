# Private data migration / 私人資料遷移

Swift 模組已統一改名。正常執行路徑只讀 v2 憑證格式；v1 只由一次性的離線遷移工具讀取。設定與字典的資料結構沒有必要改動，因此保留原始內容，只修正使用者明確指定的舊安裝根路徑。

## 保留的身分與契約

既有 App bundle ID、簽署憑證與私鑰不變。語音 worker 的既有 header/environment 名稱保留，讓已安裝引擎繼續可用；它們不是 Swift 模組。不要為了字串一致性重新簽發憑證或改掉這些契約。Git 歷史仍保留早期名稱，本次不是歷史匿名化。

## 一次性流程

此操作需要使用者明確授權讀取、備份與遷移該 App 的私人資料。先退出所有日常 App 副本，不能在 App 正寫設定或更新金鑰時執行。不要把真正路徑、日誌、備份或憑證內容貼到公開 issue。

從公開來源建置；所有命令中的路徑改成自己的位置：

```sh
bash Scripts/pack-app.sh
python3 Scripts/migrate-local-data.py prepare --runtime "/path/to/private/runtime" --previous-root "/path/to/previous/runtime"
python3 Scripts/update-local-app.py --target "/path/to/private/runtime"
```

`prepare` 先複製並驗證本機備份，再以 CryptoKit 在記憶體中解密 v1、以 v2 AAD 重新加密，逐筆核對明文相等；不印出任何憑證值。密文改為 `private/credentials.encrypted.json`，金鑰表改為本機 `~/.config/codex-secrets/edgelesstype-keyring.json`。維持 AES-256-GCM、原有 provider/record IDs 與原有金鑰，不重新產生帳號秘密。

- 設定、字典、舊密文與本機簽署設定備份在私人 runtime 的 `.private-backups/<migration-id>/`。
- 解密金鑰表備份只在本機 key directory 的 `edgelesstype-backups/<migration-id>/`，不與 runtime 備份放在一起。
- 檔案使用 600、備份目錄使用 700 權限。模型與引擎保持原地，不為了改名複製大型模型。
- 目的檔衝突、缺少匹配金鑰、損壞密文或找不到設定指定的資源時停止；可完成回復的變更會還原。意外中止時先檢查私人 manifest，不可覆寫或盲目重跑。

更新工具會要求新簽署符合既有 requirement。確認建置、自測、新憑證離線驗證與資源路徑正常，且 App 仍關閉時，再撤下舊的使用中檔案：

```sh
python3 Scripts/migrate-local-data.py finalize --runtime "/path/to/private/runtime" --backup "/path/to/private/runtime/.private-backups/<migration-id>"
```

備份仍保留，正常 runtime 不再同時維護兩套憑證格式。首次啟動後確認按鍵、字典與選項；真實 API 可用性必須另經使用者授權測試，不可拿私人音訊自動測試。

## 回復

在 finalize 前，App 保持關閉時可執行：

```sh
python3 Scripts/migrate-local-data.py rollback --runtime "/path/to/private/runtime" --backup "/path/to/private/runtime/.private-backups/<migration-id>"
```

若已換上 v2 App，資料回復必須搭配還原更新工具保留的舊程式；不可用新 App 讀舊資料。工具會拒絕覆蓋遷移後已改動的檔案。finalize 後保留離線備份，但不自動回復，必須先檢查後續資料變更並規劃回復範圍。

遷移工具：[Python orchestration](../Scripts/migrate-local-data.py)、[CryptoKit conversion](../Sources/EdgelessTypeCore/CredentialMigration.swift)。測試：[credential equality](../Tests/EdgelessTypeTests/CredentialMigrationTests.swift)、[backup/rollback fixtures](../Scripts/test-data-migration.py)。
