# Stable local signing / 每位使用者建立自己的本機簽署憑證

## 這能解決什麼

臨時（ad-hoc）簽章可能讓 macOS 把每次重新編譯視為不同程式。日常本機 App 改用同一張個人簽署憑證與固定識別碼，可以避免這個原因造成的反覆授權。這不是免除 macOS 安全機制：首次安裝或從舊身分遷移，仍由本人核准必要權限；憑證更換、手動撤銷及系統政策改變仍可能要求重授權。

每位使用者在自己的 Mac 建立自己的憑證，不使用專案作者的憑證或私鑰。下列步驟只供本機使用，不是 Developer ID、公證或對外發行 App 的替代方案。

## 1. 一次性建立自己的簽署身分

1. 開啟 macOS「鑰匙圈存取」（Keychain Access），選擇自己的「登入」鑰匙圈。
2. 選單選「憑證輔助程式 → 製作憑證」（Certificate Assistant → Create a Certificate；文字可能因系統語言不同）。
3. 名稱使用 `Local Edgeless Type Signing`，Identity Type 選 `Self Signed Root`，Certificate Type 選 `Code Signing`。
4. 依系統指示完成建立。若調整有效期限，選擇符合自己管理需求的期限；不要在每次更新時重新建立。名稱與可選欄位不需要填入要公開的真實個資。
5. 在「我的憑證」確認該憑證可以展開，底下有對應私鑰。不要匯出私鑰，也不要把憑證檔加入專案。
6. 若本機簽署驗證不接受該自簽憑證，打開該憑證的「信任」，由本人僅針對 `Code Signing` 設定信任；不要把所有用途改成永遠信任，也不要增加 SSL／網站信任。

系統密碼只輸入在 macOS 的授權視窗，不貼到聊天、終端命令、環境變數或設定檔。若有多張同名憑證，先確認正確那張，不要任意刪除或輪替。

## 2. 建立本機簽署設定

首次安裝先依[安裝指南](INSTALL_WITH_AI.md)建置公開產物，再建立全新的私人使用目錄：

```sh
python3 Scripts/prepare-private-runtime.py --target "/path/to/private/runtime"
```

工具只複製允許的公開產物及驗證過的模型，產生全新預設設定與 `Local Edgeless Type.app`；此時先不要開啟 App。它拒絕覆蓋既有目錄，不會搬移私人資料。已存在且正常使用的私人安裝請跳過準備步驟，沿用原目錄、App 名稱與既有簽署設定。公開原始碼與私人使用目錄必須分開。

從公開原始碼專案執行；範例路徑請替換成自己的私人使用目錄：

```sh
python3 Scripts/configure-local-signing.py --target "/path/to/private/runtime"
```

此工具只查詢可用簽署身分的公開中繼資料，精確選取上述名稱，並在私人目錄建立權限 600 的 `LOCAL-SIGNING.json`。不讀取、匯出或複製私鑰。已有相同設定時不重建；有不同設定或同名憑證不唯一時停止，避免意外改變身分。若選用自己的其他憑證名稱，可加 `--identity-name "Your Local Signing Name"`；進階使用者可用 `--identity-sha1` 精確選擇憑證指紋。

## 3. 建置、簽署與首次授權

先退出日常 App，再從公開原始碼專案執行：

```sh
bash Scripts/pack-app.sh
python3 Scripts/update-local-app.py --target "/path/to/private/runtime"
```

公開建置產物仍可用 ad-hoc 簽章跑 CI；更新工具只在使用者自己的 Mac 用其憑證簽署私人安裝，不把簽署金鑰交給 GitHub Actions。實際開啟私人目錄裡的 `Local Edgeless Type.app`，不要開公開建置副本。

兩種不同的提示要分開理解：

- **鑰匙圈的 codesign 提示：**簽署工具要使用你剛建立的私鑰。「允許」通常只核准當次操作；如果已確認請求者是 Apple 的 `codesign`、對象是自己的專用簽署私鑰，可以由本人選「永遠允許」，減少以後建置時重複詢問。不要授予所有 App 無限制取用私鑰。
- **macOS 輔助使用／輸入監控／麥克風提示：**這是 App 功能所需的系統權限，由使用者本人確認。首次身分遷移可能需要逐項核准；不會因為建立憑證就自動取得這些權限。

## 4. 後續更新與驗證

後續沿用同一個原始碼專案、私人安裝位置、憑證與本機識別碼，重複上一節的建置及更新命令即可。不要刪掉簽署私鑰、不要重製憑證，不要把 `tccutil reset` 當更新流程。更新工具會驗證新版本符合原本的憑證身分，不符合就停止並回復原簽署檔案。

若選了正確 App 卻無法加入權限清單，先比較 App、LaunchServices 與 Spotlight 的識別碼是否一致；不要要求使用者反覆盲目重選。更新工具會刷新外層 App 時間、註冊與索引，索引完成可能稍有延遲。

最後分別確認 Fn 能開始／結束錄音、文字實際貼入一次、預覽框會收起。簽章驗證成功不等於這三項都通過；不要為了測試而錄製或上傳私人內容。

## 隱私界線

GitHub 只包含通用工具、文件與合成測試。`LOCAL-SIGNING.json`、`LOCAL-BUILD.json`、簽署私鑰、個人憑證、API 金鑰、私人設定、字典、錄音、逐字稿、個人路徑和登入資訊不得提交或放進公開問題回報。簽署憑證的公開部分本身不是秘密，但可能包含身分資訊，同樣不需要發布。

## Implementation details

Public CI builds remain ad-hoc signed and contain no signing secrets. Do not run the public build as the daily permission-granted app.

The local updater requires `LOCAL-SIGNING.json` in the private runtime, with `identitySHA1` (the fingerprint of an existing Keychain code-signing identity) and `bundleIdentifier` set to `edgelessblade.opentypeless.local`. The local bundle ID is distinct from the public build and old test copies. The profile contains no private key but must not be published or synchronized into the public checkout.

Use a user-selected existing certificate, or, only with explicit permission, create a dedicated local code-signing certificate. Keep its private key in the user's Keychain, never in Git or the runtime folder. Do not export existing private keys, silently regenerate the signer, grant broad key access, add TLS trust, disable Gatekeeper, or change the TCC database. Keychain or system permission prompts belong to the user. A local certificate is not Developer ID or notarization and is not suitable as public distribution assurance.

The updater signs the local app with the exact identity fingerprint, verifies the signature, rejects a bare `cdhash` requirement and requires each subsequent update to satisfy the previous designated requirement. A failed update restores executable, metadata, public assets and signature bytes without re-signing the rollback ad hoc. Missing/changed signers stop the update before continuing; restore the original signer or plan an explicit identity migration instead of silently falling back.

One final user approval of Accessibility/Input Monitoring and microphone access may be needed during migration. This does not guarantee that macOS will never ask again after certificate replacement, permission revocation or system policy changes. Test two different locally signed builds against the same requirement, then separately confirm real Fn and paste behavior after the user grants access.

Apple references: [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

After installation, the updater refreshes the bundle directory timestamp, LaunchServices registration and Spotlight import. These metadata operations do not change the signed contents or grant permissions. Indexing may complete asynchronously. When migrating a bundle ID, compare Info.plist, codesign, LaunchServices and Spotlight before asking the user to select the app again; stale picker metadata can submit the old ID even when the correct file is selected.
