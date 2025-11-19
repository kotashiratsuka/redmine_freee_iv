# Redmine freee Plugin

Redmine のチケット番号（Issue ID）と freee の納品書、見積書、請求書ステータスを自動連携し、
freee 側の「件名（subject）」に含まれる **[#1234]** を Redmine Issue ID として扱います

- 見積書：送付済み / 未送付
- 請求書：送付済み / 未送付 / 入金済み / 入金待ち
- 納品書：送付済み / 未送付 / 入金済み / 入金待ち

などの freee イベントに応じて Redmine の Issue ステータスを自動更新します
コメントテンプレートを使用して Issue に自動コメント内容を設定可能です

------------------------------------------------------------

# 🔧 機能概要

## 1. freee OAuth 認証に対応

- 設定画面から Client ID / Secret を登録
- 「認証を開始する」から freee OAuth を実行
- アクセストークンの有効期限を表示
- 「認証を解除する」ボタンで revoke も可能

認証情報は `freee_credentials` テーブルに保存されます

------------------------------------------------------------

## 2. freee API 経由で見積書・請求書を取得

利用 API:

### 見積書一覧
```
GET /iv/quotations?company_id=XXX
```

### 請求書一覧
```
GET /iv/invoices?company_id=XXX
```

### 納品書一覧
```
GET /iv/delivery_slips?company_id=XXX
```

権限がない company_id は freee 仕様で必ず 401 が返されるため、
プラグイン側で安全にスキップします

------------------------------------------------------------

# 🔄 Issue 自動ステータス更新の仕組み

## 🎯 マッチング仕様

freee の **件名（subject）** に以下の形式を含めてください：

```
[#1234]
```

これを **Issue ID 1234** として扱います
番号ではなく subject ベースのマッチングに変更されています

# 🆕 最終ステータスのみ適用モード（推奨）

```
[✔] 最終ステータスのみに反映
```

以下の順でステータスを評価し、最後のステータスだけを Issue に反映します

3. 請求書（Invoice）
1. 見積書（Quotation）
2. 納品書（DeliverySlip）

- コメントも「最終ステータス」のテンプレートだけ適用されます
- 各書類で同じIssueを参照する場合のみOFFにしてください。設定を誤るとステータス遷移ループが起きてしまうので通常はONのままを推奨します

------------------------------------------------------------

# ⚙️ 設定画面の構成（実際の UI に準拠）

## ◆ 見積書
- 送付済み (sent)
- 未送付 (unsent)

## ◆ 請求書
- 送付済み (sent)
- 未送付 (unsent)
- 入金済み (settled)
- 入金待ち (unsettled)

## ◆ 納品書
- 送付済み (sent)
- 未送付 (unsent)
- 入金済み (settled)
- 入金待ち (unsettled)

各項目で以下を設定できます：

- 「変更しない」または任意のステータス
- コメントテンプレート（後述の変数が利用可能）

------------------------------------------------------------

# 📝 コメントテンプレートで使用可能な変数

## ■ 見積書（Quotation）
- `{amount}`  見積金額（カンマ区切り）
- `{url}`     見積書の freee 管理画面 URL
- `{status}`  送付ステータス（sent / unsent）

## ■ 請求書（Invoice）
- `{amount}`   請求金額（カンマ区切り）
- `{url}`      請求書の freee 管理画面 URL
- `{mail}`     送付ステータス（sent / unsent）
- `{payment}`  入金ステータス（settled / unsettled）

## ■ 納品書（DeliverySlip）
- `{amount}`   納品金額
- `{url}`      納品書 URL
- `{mail}`     送付ステータス（sent / unsent）
- `{payment}`  入金ステータス（settled / unsettled）

※請求書では `{status}` は使用できません（値が渡らないため）

------------------------------------------------------------

# 💬 コメントテンプレート例

```
💰 freee で入金を確認しました（{amount} 円）
URL: {url}
```

```
📤 freee で請求書が送付されました
金額: {amount} 円
URL: {url}
```

------------------------------------------------------------

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

------------------------------------------------------------

# 🚀 使用方法

## 1. freee デベロッパーアプリ作成

作成 URL
https://app.secure.freee.co.jp/developers/applications/new

必要な権限：
**freee請求書（見積書・請求書・納品書）**

Callback URL：
```
https://YOUR_HOST/redmine_freee/auth/callback
```

## 2. Redmine 設定で OAuth を実行
- Client ID / Secret を入力して保存
- 「認証を開始する」で OAuth 認証を完了

------------------------------------------------------------

# 🧪 DRY-RUN（動作確認用）

```
RAILS_ENV=production bundle exec rake freee:dry_run
```

- freee API から取得
- Redmine のステータス／コメントは変更しない
- ログで反映内容だけ確認可能

------------------------------------------------------------

# 🔄 同期

```
RAILS_ENV=production bundle exec rake freee:sync
```

- ステータス更新
- コメント投稿（設定 ON の場合）
を自動で実行します

------------------------------------------------------------

# 📅 Cron 設定例（平日 9,12,15,18,21 時）

```
0 9,12,15,18,21 * * 1-5 RAILS_ENV=production bundle exec rake freee:sync
```

------------------------------------------------------------

# 📂 ディレクトリ構成

```
redmine_freee/
  app/
    controllers/redmine_freee_auth_controller.rb
    models/freee_credential.rb
    services/freee_api_client.rb
    views/settings/_freee_settings.html.erb
  lib/tasks/sync.rake
  db/migrate/20251115080912_create_freee_credentials.rb
  config/routes.rb
  init.rb
```

------------------------------------------------------------

# ⚠️ 注意事項

- freee の **件名（subject）に [#1234] を含めてください**
  - 例：`2025年12月 請求書 [#1234]`
- 「変更しない」を選んだイベントはスキップされます
- 権限エラー（401）は安全にスキップ
- コメント投稿ユーザーは `settings[user_id]` で指定
- それぞれの取得件数を（100,200,300,400,unlimited）で選択可能

------------------------------------------------------------

# 👤 Author

Kota Shiratsuka
