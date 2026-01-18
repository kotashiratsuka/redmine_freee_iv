# Redmine freee Iv Plugin

Redmine のチケット番号（Issue ID）と、 freee請求書 の

- 件名（subject）」
- 見積書番号（quotation_number）
- 請求書番号（invoice_number）
- 納品書番号（delivery_slip_number）

のいずれかに含まれる **[#1234]** を Redmine Issue ID として扱います

- 見積書：送付済み / 未送付 / 取消済み
- 請求書：送付済み / 未送付 / 入金済み / 入金待ち / 取消済み
- 納品書：送付済み / 未送付 / 入金済み / 入金待ち / 取消済み

などの freee請求書 イベントに応じて Redmine の Issue ステータスを自動更新します

コメントテンプレートを使用して Issue に自動コメント内容を設定可能です

------------------------------------------------------------

# 🔧 機能概要

## freee OAuth 認証に対応

- 設定画面から Client ID / Secret を登録
- 「認証を開始する」から freee OAuth を実行
- アクセストークンの有効期限を表示
- 「認証を解除する」ボタンで revoke も可能

# 🏢 複数事業所（multi-company）対応

freee のアカウントに複数の「事業所（company）」が紐づいている場合、
本プラグインは **事業所ごとの OAuth 認証** に対応しています。

## 🔐 認証の仕組み

- freee OAuth 認証時に freee 側で「事業所選択画面」が表示されます
- 選択した事業所（company_id）のアクセストークンが保存されます
- 認証情報は `freee_iv_credentials` テーブルへ **事業所ごとに 1 レコード** 保存されます

保存されるカラム：

| カラム名 | 説明 |
|---------|------|
| company_id | freee の事業所 ID |
| access_token | アクセストークン |
| refresh_token | リフレッシュトークン |
| expires_at | トークン有効期限 |

→ **事業所が 2 つなら、レコードも 2 つ**になります

# 🔄 Issue 自動ステータス更新の仕組み

## 🎯 マッチング仕様

freee請求書で

- 件名（subject）」もしくは
- 見積書番号（quotation_number）もしくは
- 請求書番号（invoice_number）もしくは
- 納品書番号（delivery_slip_number）

に

```
[#1234]
```

を含めてください。これを **Issue ID 1234** として扱います

# 🎯 最終ステータスのみ適用モード（推奨）

```
[✔] 最終ステータスのみに反映
```

以下の順でステータスを評価し、最後のステータスだけを Issue に反映します

最終ステータス判定ロジックでは以下の優先度を使用します：

1. 見積書（Quotations） score = 0
2. 請求書（Invoices） score = 1
3. 納品書（DeliverySlips） score = 2（最優先）

- Issue ID が同じ場合は score の高い方が採用されます
- 設定を誤るとステータス遷移ループが起きてしまうので通常は **ONのままを強く推奨** します
- コメントも「最終ステータス」のテンプレートだけ適用されます
- 複数の事業所からデータを取得し Issue ID が同じ場合は score の高い方が採用されます

# 🛡️ 保護するステータス

特定のステータスにある Issue は、freee請求書 からの更新対象から除外されます

- 「完了」「クローズ」など、更新したくないステータスを保護したい場合
- 手動のステータスを freee請求書連携が上書きするのを防ぎたい場合
- 過去 Issue の誤更新を防ぎたい場合

設定画面で複数ステータスを複数選択できます

選択されたステータスに設定されている Issue はステータス保護され変更されません

------------------------------------------------------------

------------------------------------------------------------

## 2. freee請求書 API 経由で見積書・請求書を取得

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

------------------------------------------------------------

# ⚙️ 設定画面の構成（実際の UI に準拠）

## ◆ 見積書
- 送付済み (sent)
- 未送付 (unsent)
- 取消済み (canceled)

## ◆ 請求書
- 送付済み (sent)
- 未送付 (unsent)
- 入金済み (settled)
- 入金待ち (unsettled)
- 取消済み (canceled)

## ◆ 納品書
- 送付済み (sent)
- 未送付 (unsent)
- 入金済み (settled)
- 入金待ち (unsettled)
- 取消済み (canceled)

各項目で以下を設定できます：

- チケット番号の抽出元となる項目
- 「変更しない」または任意のステータス
- コメントテンプレート（後述の変数が利用可能）

------------------------------------------------------------

# 📝 コメントテンプレートで使用可能な変数

## ■ 見積書（Quotation）
- `{amount}`  見積金額（カンマ区切り）
- `{url}`     見積書の freee請求書 URL
- `{mail}`    送付ステータス（sent / unsent）

## ■ 請求書（Invoice）
- `{amount}`   請求金額（カンマ区切り）
- `{url}`      請求書の freee請求書 URL
- `{mail}`     送付ステータス（sent / unsent）
- `{payment}`  入金ステータス（settled / unsettled）

## ■ 納品書（DeliverySlip）
- `{amount}`   納品金額
- `{url}`      納品書 URL
- `{mail}`     送付ステータス（sent / unsent）
- `{payment}`  入金ステータス（settled / unsettled）

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

#  インストール

## 1. プラグイン配置
```
cd /home/redmine/plugins
git clone https://github.com/kotashiratsuka/redmine_freee_iv.git
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
https://YOUR_HOST/redmine_freee_iv/auth/callback
```

## 2. Redmine 設定で OAuth を実行
- Client ID / Secret を入力して保存する
- 「認証を開始する」で 使用する事業所を許可して OAuth 認証を完了します
- 複数の事業所を使う場合は繰り返して認証します

------------------------------------------------------------

# 🧪 DRY-RUN（動作確認用）

```
RAILS_ENV=production bundle exec rake freee_iv:dry_run
```

- freee請求書 API から取得
- Redmine のステータス／コメントは変更しない
- ログで反映内容だけ確認可能

------------------------------------------------------------

# 🔄 同期

```
RAILS_ENV=production bundle exec rake freee_iv:sync
```

- ステータス更新
- コメント投稿（設定 ON の場合）
を自動で実行します

------------------------------------------------------------

# 📅 Cron 設定例（平日 9,12,15,18,21 時）

```
0 9,12,15,18,21 * * 1-5 RAILS_ENV=production bundle exec rake freee_iv:sync
```

------------------------------------------------------------

# 📂 ディレクトリ構成

```
redmine_freee_iv/
  app/
    controllers/redmine_freee_iv_auth_controller.rb
    models/freee_credential.rb
    services/freee_api_client.rb
    views/settings/_freee_settings.html.erb
  lib/tasks/sync.rake
  db/migrate/20251115080912_create_freee_credentials.rb
  db/migrate/20251120025636_add_company_to_freee_iv_credentials.rb
  config/routes.rb
  init.rb
```

------------------------------------------------------------

# ⚠️ 注意事項

- freee の 書類番号（見積書番号 / 請求書番号 / 納品書番号） または 件名（subject）に **[#1234]** を含めてください
  - 例：`2025年12月 請求書 [#1234]`
- 「変更しない」を選んだイベントはスキップされます
- コメント投稿ユーザーは `settings[user_id]` で指定
- それぞれの取得件数を（100,200,300,400,unlimited）で選択可能
- [freee API レートリミットについて](https://developer.freee.co.jp/reference/iv/reference#api_rate_limit) に注意

------------------------------------------------------------

# 👤 Author

Kota Shiratsuka
