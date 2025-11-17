Redmine::Plugin.register :redmine_freee do
  name        'Redmine Freee Plugin'
  author      'Kota Shiratsuka'
  description 'freee Invoice Status Sync'
  version     '0.2.0'
  url         'https://github.com/kotashiratsuka/redmine_freee'
  author_url  'https://github.com/kotashiratsuka/'
  requires_redmine version_or_higher: '6.0.0'

  settings default: {
  'client_id' => '',
  'client_secret' => '',
  'user_id' => '',

  # --- 同期 ON/OFF ---
  'sync_quotations' => '0',
  'sync_invoices' => '0',

  # --- ステータス設定 ---
  'quotation_sent_status' => '0',
  'quotation_unsent_status' => '0',
  'invoice_sent_status' => '0',
  'invoice_unsent_status' => '0',
  'invoice_paid_status' => '0',
  'invoice_unpaid_status' => '0',

  # --- コメントテンプレ ---

  'quotation_unsent_comment' =>
    "📝 freee に {amount} 円の見積書が作成されました\nURL: {url}",

  'quotation_sent_comment' =>
    "📤 freee で {amount} 円の見積書が送信されました\nURL: {url}",

  'invoice_unsent_comment' =>
    "📝 freee に {amount} 円の請求書が作成されました\nURL: {url}",

  'invoice_sent_comment' =>
    "📤 freee で {amount} 円の請求書が送信されました\nURL: {url}",

  'invoice_unpaid_comment' =>
    "💰 freee で {amount} 円の入金待ちです\nURL: {url}",

  'invoice_paid_comment' =>
    "💰 freee で {amount} 円の入金が確認されました\nURL: {url}",

  }, partial: 'settings/freee_settings'
end
