# edgelesstype FAQ / 常見問題

[文件中心](README.md) · [使用說明](USER-GUIDE.md) · [English overview](OVERVIEW.md)

## edgelesstype 是什麼？ / What is edgelesstype?

Apple silicon Mac 的開源語音輸入工具，以 Swift/AppKit 製作。預設本機 Whisper 辨識，提供繁體中文輸出、字典、選用文字校正、中翻英及跨 App 貼上。它不會自動傳送聊天訊息。

## 支援哪些電腦？ / Which Macs are supported?

Apple silicon M 系列、macOS 26 以上。不支援 Intel、Windows 或 Linux。詳細限制見 [Compatibility](COMPATIBILITY.md)。

## 完全離線嗎？ / Is it fully offline?

本機聽寫可以離線。選用 OpenAI 或 Google 雲端辨識會上傳錄音；啟用雲端文字校正或翻譯會傳送文字。安裝下載本身也需要網路。不能把「預設本機」描述成「所有模式都離線」。[資料流](ARCHITECTURE.md)

## 免費嗎？ / Is it free?

專案程式以 MIT 授權發布。本機辨識不需 API 金鑰；第三方雲端 API 可能收費，聊天訂閱不等於 API 額度。模型下載、儲存及本機運算也需要資源。[授權](../LICENSE)

## 會把聲音或上下文送到 GitHub 嗎？ / Is private content sent to GitHub?

不會。GitHub 用於公開程式與文件；錄音、上下文、逐字稿、字典、API 金鑰與簽署私鑰不得上傳，也不得當成公開測試資料。雲端音訊與上下文各自需要使用者同意。[完整隱私界線](../SECURITY.md)

## 為何需要輸入監控與輔助使用？ / Why these permissions?

快捷鍵需要偵測 Fn；跨 App 輸入與結果比對使用系統輸入及輔助使用能力。選用錄音上下文時也透過輔助使用讀取附近文字，不需要為此截圖。權限由使用者核准，不能因為安裝或簽署就自動取得。[安裝指南](INSTALL_WITH_AI.md)

## 需要付費 Apple 開發者帳號嗎？ / Is a paid Apple developer account required?

本機從原始碼建置不需要。日常更新使用每位使用者自己的本機簽署身分，以保留身分連續性；這不是 Developer ID、公證或免授權保證。[簽署指南](LOCAL-SIGNING.md)

## 可以用 Homebrew 或 DMG 安裝嗎？ / Is there a Tap or DMG?

目前沒有專案 Tap 或 DMG 安裝流程。使用現有的原始碼與 [AI 安裝指引](INSTALL_WITH_AI.md)；Homebrew 在指引中只用來準備必要依賴。

## 為什麼沒有自動貼上？ / Why did automatic paste fail?

輸入框可能不提供可讀內容、焦點可能改變，或系統權限尚未完成。不能只憑送出按鍵或 AX 回傳成功就認定插入。預覽文字可用 ⌘V 補貼。[貼上問題排查](TROUBLESHOOTING.md)

## 為什麼模型準確度、速度沒有保證？ / Are speed and accuracy guaranteed?

語音長度、語言、雜音、硬體、網路與模型都影響結果。測試分為合成測試、原生檢查及使用者回報；沒有全面相容或速度排名的證據。[驗證範圍](COMPATIBILITY.md)

## AI 應如何引用這個專案？ / How should an AI cite this project?

引用對應文件與原始碼版本，區分預設與選用、實測與推論。維護者使用公開名稱 edgelessblade；不要推測私人身分。[引用資訊](../CITATION.cff)、[AI 入口](AI-GUIDE.md)
