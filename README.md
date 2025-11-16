# Redmine Freee Plugin

Redmine のチケット番号（Issue ID）と freee の見積・請求データを自動連携し、

- 見積書送信
- 請求書送信
- 入金済

これら freee のイベントに応じて **Redmine の Issue ステータスを自動更新**し、
さらに **URL 付きのコメントを自動投稿**するプラグインです。

---

# 🔧 機能概要

## 1. freee OAuth 認証

Redmine の設定画面で Client ID / Secret を登録し、
「認証を開始する」リンクから freee OAuth を実行できます。

認証後はアクセストークンが `freee_credentials` テーブルに保存されます。

---

## 2. freee API 経由でデータ取得

### 見積一覧 API

```
GET /iv/quotations?company_id=XXX
```

### 請求書一覧 API

```
GET /iv/invoices?company_id=XXX
```

権限のない company_id は freee 側の仕様により自動的に 401 となるため、
プラグイン内で安全にスキップしています。

---

# 🔄 Issue 自動ステータス更新ルール（実装準拠）

freee の番号と Issue ID の対応は以下：

```
"#1234" → Issue ID 1234
```

---

## 1. 見積送信（quotation.sending_status = "sent"）

Redmine → **見積発行**

コメント例：

```
🤖 freee で 33,000 円の見積書が送信されました 📨
URL: https://invoice.secure.freee.co.jp/reports/quotations/xxxx
```

---

## 2. 請求書送信（invoice.sending_status = "sent"）

Redmine → **請求中**

コメント例：

```
🤖 freee で 33,000 円の請求書が送信されました 📤
URL: https://invoice.secure.freee.co.jp/reports/invoices/xxxx
```

---

## 3. 入金確認（invoice.payment_status = "settled"）

Redmine → **入金済**

コメント例：

```
🤖 freee で 33,000 円の入金が確認されました 💰
URL: https://invoice.secure.freee.co.jp/reports/invoices/xxxx
```

---

# 📌 Redmine ステータス名

プラグインは以下のステータス名で ID を検索します：

| Redmine ステータス名 | freee イベント |
|----------------------|----------------|
| **見積発行** | 見積書送信 |
| **請求中**   | 請求書送信 |
| **入金済**   | 入金確認 |

これらのステータス名を事前に Redmine 側で作成しておいてください。

---

# ⚙️ インストール

## 1. プラグイン配置

```
cd /home/redmine/plugins
git clone git@github.com:USERNAME/redmine_freee.git
```

## 2. Gem インストール

```
bundle install
```

## 3. DB マイグレーション

```
RAILS_ENV=production bundle exec rake db:migrate_plugins
```

## 4. Redmine 再起動

```
service puma restart
```

---

# 🚀 使用方法

## 1. freee デベロッパーアプリ作成

作成URL：
https://app.secure.freee.co.jp/developers/applications/new

- 権限 → **[freee請求書] 見積書・請求書・納品書**
- Callback URL：

```
https://YOUR_HOST/redmine_freee/auth/callback
```

## 2. Redmine のプラグイン設定で Client ID / Secret を入力
→ 「適用」
→ 「認証を開始する」リンクから OAuth

---

# 🧪 DRY RUN（確認用）

```
RAILS_ENV=production bundle exec rake freee:dry_run
```

freee データを読み込み、一切変更せずログ出力のみ行います。

---

# 🔄 同期（本番更新）

```
RAILS_ENV=production bundle exec rake freee:sync
```

- ステータス更新
- コメント投稿
を自動で行います。

---

# ⏱ Cron 設定例（平日9,12,15,18,21時更新）

```
0 9,12,15,18,21 * * 1-5 RAILS_ENV=production bundle exec rake freee:sync
```

---

# 📂 ディレクトリ構成

```
redmine_freee/
├── app/
│   ├── controllers/redmine_freee_auth_controller.rb
│   ├── models/freee_credential.rb
│   └── services/freee_api_client.rb
├── lib/tasks/sync.rake
├── db/migrate/20251115080912_create_freee_credentials.rb
├── config/routes.rb
└── init.rb
```

---

# ⚠️ 注意事項

- freee の見積・請求番号は `#1234` の形式（Issue ID と一致必須）
- sending_status の `nil` / `""` / `"unsent"` は全て未送信扱いに統一
- 権限エラー(401)は安全にスキップ
- コメント投稿ユーザー ID は **settings[user_id]** で変更可能

---

# 👤 Author

**Kota Shiratsuka**
INSANEWORKS LLC
https://www.insaneworks.llc
