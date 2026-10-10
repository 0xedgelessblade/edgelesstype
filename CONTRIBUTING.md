# Contributing / 如何改造與貢獻

歡迎 fork、研究與改造。請保留 MIT 授權與原始著作權聲明，並清楚說明自己的變更。

## Start small

1. 先讀 [架構](docs/ARCHITECTURE.md) 及相關 [問題案例](docs/TROUBLESHOOTING.md)。
2. 找到可重現的失敗，用固定測試句或假的金鑰建立測試。
3. 修改對應層：模型代號、API adapter、校正驗證、焦點解析或貼入確認。
4. 執行 Core 測試、文件連結檢查、App 建置與公開檔案檢查。
5. PR 說明問題、最後行為、驗證方法、適用範圍和未驗證項目。

```sh
python3 Scripts/test-core.py
python3 Scripts/check-docs.py
bash Scripts/pack-app.sh
python3 Scripts/public-check.py --app-only
```

## Reproduce without private data

- 使用空白或可丟棄的輸入欄，由測試者先放好游標。
- 不自動點標成「傳送」的 wrapper；不按 Enter。
- 不附 API 金鑰、金鑰表、密文存檔、錄音或整段私人聊天。
- 記錄 OS、App 版本、欄位類型、是否手動補貼、文字是否重複與提示框是否收起。
- 真實 API 測試需要自己的金鑰與額度；fixtures 測試不需要。

## Publish responsibly

使用自己的公開 Git 作者名稱與 GitHub noreply Email。不要沿用工作機的私人全域 Git 身分。
檢查 `git diff --cached`，並使用 `Scripts/public-check.py` 建立來源包；不要直接壓縮整個工作資料夾。

若加入新的文件或資源，更新公開檔案清單。新增模型時查官方文件，不要只換名稱後就宣稱相容。

本專案目前只支援 M 系列 Mac。其他平台的實驗請在 fork 清楚標示，不要把未測平台加進支援聲明。
