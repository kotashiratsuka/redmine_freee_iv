# Redmine Freee Plugin

Redmine のチケット番号（Issue ID）と freee 請求書番号を連携し、
freee 側で **入金済（settled）になると自動で Redmine のチケットを更新**するプラグインです。

- freee OAuth 認証
- 請求書一覧の取得
- 入金済みチェック
- Redmine のステータス自動変更
- 自動コメント追加（Slack 通知と連携）
- DRY-RUN での試験実行
- 複数の freee 事業所に対応（権限なしは自動スキップ）

---

## 🔧 機能概要

### 1. freee OAuth 認証
`/redmine_freee/auth/start` にアクセスすると freee のログイン画面が表示されます。
認証が成功すると access_token・refresh_token が DB に保存されます。

保存テーブル：`freee_credentials`

### 2. freee API 経由で請求書を取得
各事業所（company_id）ごとに

```
GET /iv/invoices?company_id=XXX&payment_status=settled
```

を実行します。
権限がない company は自動でスキップされます。

---

## 3. Issue 自動更新仕様

- freee の **請求書番号 = `#1234` → Redmine Issue ID = 1234**
- 入金済み（settled）の場合：
- Redmine ステータスを「入金済」に変更（ID は名称から自動取得）

コメント例：

```
🤖 2025-11-15 12:02 に freeeで 22,448円 の入金が確認されました 💰
請求書URL: https://invoice.secure.freee.co.jp/reports/invoices/44600944
```

---

## 📦 インストール

### 1. plugins/ 配下へ配置

```
cd /home/redmine/plugins
git clone https://github.com/kotashiratsuka/redmine_freee.git
```

### 2. 必要な Gem をインストール

```
bundle install
```

### 3. DB マイグレーション

```
RAILS_ENV=production bundle exec rake db:migrate_plugins
```

### 4. サービス再起動

```
service puma restart
```

---

## 🚀 使い方

### 1. アプリの作成
https://app.secure.freee.co.jp/developers/applications/new で新しいアプリを作成します

アプリ名、概要は適宜、権限は "[freee請求書] 見積書・請求書・納品書" です

callback URLは `https://YOUR_HOST/redmine_freee/auth/callback` を設定し、表示されている
`Client ID` と `Client Secret` を `app/controllers/redmine_freee_auth_controller.rb` に設定します

### 2. freee 認証開始

ブラウザで：

```
https://YOUR_HOST/redmine_freee/auth/start
```

### 3. DRY-RUN

```
RAILS_ENV=production bundle exec rake freee:dry_run_match
```

### 4. 同期

```
RAILS_ENV=production bundle exec rake freee:sync_invoices
```

---

## 🔄 Cron の例

```
*/10 * * * * cd /home/redmine && RAILS_ENV=production bundle exec rake freee:sync_invoices
```

---

## 🧱 ディレクトリ構成

```
redmine_freee/
├── app/
│ ├── controllers/redmine_freee_auth_controller.rb
│ ├── models/freee_credential.rb
│ └── services/freee_api_client.rb
├── lib/tasks/sync.rake
├── db/migrate/20251115080912_create_freee_credentials.rb
├── config/routes.rb
├── init.rb
└── README.md
```

---

## ⚠️ 注意事項

- freee の請求書番号が `#1234` の形式である必要あり
- ステータス「入金済」は名称検索で ID を取得
- 既に入金済みステータスなら更新しない
- User ID は `312` を使用（環境に合わせて変更可）

---

## 👤 Author

**Kota Shiratsuka**
INSANEWORKS LLC
https://www.insaneworks.llc
