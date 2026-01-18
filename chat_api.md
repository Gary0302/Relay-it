# Chat API 文件

## 端點

```
POST /api/chat
```

## 請求格式 (Request)

### ChatRequest

```json
{
  "sessionId": "string (UUID)",
  "userMessage": "string",
  "currentNote": "string",
  "context": {
    "screenshots": [
      {
        "id": "string (UUID)",
        "rawText": "string",
        "summary": "string"
      }
    ],
    "sessionName": "string | null",
    "sessionCategory": "string | null"
  }
}
```

### 欄位說明

| 欄位 | 類型 | 必填 | 說明 |
|------|------|------|------|
| `sessionId` | string | ✅ | Session 的 UUID |
| `userMessage` | string | ✅ | 使用者輸入的訊息 |
| `currentNote` | string | ✅ | 目前筆記的內容 |
| `context` | object | ❌ | 上下文資訊（可為 null） |

### Context 物件

| 欄位 | 類型 | 必填 | 說明 |
|------|------|------|------|
| `screenshots` | array | ❌ | 截圖資訊陣列 |
| `sessionName` | string | ❌ | Session 名稱 |
| `sessionCategory` | string | ❌ | Session 類別 |

### ChatScreenshot 物件

| 欄位 | 類型 | 必填 | 說明 |
|------|------|------|------|
| `id` | string | ✅ | 截圖的 UUID |
| `rawText` | string | ✅ | 截圖的原始文字 (OCR) |
| `summary` | string | ✅ | 截圖的摘要 |

---

## 回應格式 (Response)

### ChatResponse

```json
{
  "reply": "string",
  "updatedNote": "string | null",
  "noteWasModified": true | false
}
```

### 欄位說明

| 欄位 | 類型 | 說明 |
|------|------|------|
| `reply` | string | AI 的回覆訊息 |
| `updatedNote` | string \| null | 更新後的筆記內容（如果 AI 修改了筆記） |
| `noteWasModified` | boolean | 表示筆記是否被 AI 修改 |

---

## 使用範例

### 請求範例

```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "userMessage": "幫我總結這個 session 的重點",
  "currentNote": "# 我的筆記\n\n- 第一點\n- 第二點",
  "context": {
    "screenshots": [
      {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "rawText": "這是從截圖中提取的文字內容...",
        "summary": "這是一個關於產品比較的截圖"
      }
    ],
    "sessionName": "產品研究",
    "sessionCategory": "shopping"
  }
}
```

### 回應範例 - AI 回答問題

```json
{
  "reply": "根據您的截圖，這個 session 的重點包括：\n1. 比較了三款產品的價格\n2. 功能差異分析\n3. 使用者評價比較",
  "updatedNote": null,
  "noteWasModified": false
}
```

### 回應範例 - AI 修改筆記

```json
{
  "reply": "好的，我已經幫您更新筆記了！",
  "updatedNote": "# 我的筆記\n\n- 第一點\n- 第二點\n\n## AI 總結\n\n這是新增的內容...",
  "noteWasModified": true
}
```

---

## Swift 結構定義

```swift
struct ChatContext: Encodable {
    let screenshots: [ChatScreenshot]?
    let sessionName: String?
    let sessionCategory: String?
}

struct ChatScreenshot: Encodable {
    let id: String
    let rawText: String
    let summary: String
}

struct ChatRequest: Encodable {
    let sessionId: String
    let userMessage: String
    let currentNote: String
    let context: ChatContext?
}

struct ChatResponse: Decodable {
    let reply: String
    let updatedNote: String?
    let noteWasModified: Bool
}
```

---

## 錯誤處理

API 可能回傳以下 HTTP 狀態碼：

| 狀態碼 | 說明 |
|--------|------|
| 200 | 成功 |
| 400 | 請求格式錯誤 |
| 500 | 伺服器內部錯誤 |

---

## 注意事項

1. `context` 欄位是可選的，但提供完整的上下文可以讓 AI 給出更精準的回答
2. 當 `noteWasModified` 為 `true` 時，客戶端應該用 `updatedNote` 的內容更新本地筆記
3. 請求超時時間設定為 60 秒，以配合 AI 分析所需時間

