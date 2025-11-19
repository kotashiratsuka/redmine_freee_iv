Redmine::Plugin.register :redmine_freee_iv do
  name        'Redmine freee Iv Plugin'
  author      'Kota Shiratsuka'
  description 'freee Invoice Status Sync'
  version     '0.2.1'
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
  'sync_delivery_slips' => '0',

  # --- ステータス設定 ---
  'quotation_sent_status' => '0',
  'quotation_unsent_status' => '0',
  'invoice_sent_status' => '0',
  'invoice_unsent_status' => '0',
  'invoice_paid_status' => '0',
  'invoice_unpaid_status' => '0',
  'delivery_slip_sent_status' => '0',
  'delivery_slip_unsent_status' => '0',
  'delivery_slip_paid_status' => '0',
  'delivery_slip_unpaid_status' => '0',

  # --- コメントテンプレ ---
  'quotation_unsent_comment' => "🧾 freee に {amount} 円の見積書が作成されました\nURL: {url}",
  'quotation_sent_comment' => "📤 freee で {amount} 円の見積書が送信されました\nURL: {url}",
  'invoice_unsent_comment' => "🧾 freee に {amount} 円の請求書が作成されました\nURL: {url}",
  'invoice_sent_comment' => "📤 freee で {amount} 円の請求書が送信されました\nURL: {url}",
  'invoice_unpaid_comment' => "💰 freee で {amount} 円の入金待ちです\nURL: {url}",
  'invoice_paid_comment' => "💰 freee で {amount} 円の入金が確認されました\nURL: {url}",
  'delivery_slip_unsent_comment' => " 📦 freee に {amount} 円の納品書が作成されました\nURL: {url}",
  'delivery_slip_sent_comment' => "📤 freee で {amount} 円の納品書が送信されました\nURL: {url}",
  'delivery_slip_unpaid_comment' => "💰 freee で {amount} 円の入金待ちです\nURL: {url}",
  'delivery_slip_paid_comment' => "💰 freee で {amount} 円の入金が確認されました\nURL: {url}",

  # --- 最大取得件数 ---
  'apply_final_only' => '1',
  'max_fetch_total' => '100'
  }, partial: 'settings/freee_settings'
end
