# frozen_string_literal: true

module DocumentTypeDefinitions
  STATUS_LABELS = {
    sent: "送付済み (sent)",
    unsent: "未送付 (unsent)",
    paid: "入金済み (settled)",
    unpaid: "入金待ち (unsettled)",
    canceled: "取消済み (canceled)"
  }.freeze

  STATUS_SHORT_LABELS = {
    sent: "送付済",
    unsent: "未送付",
    paid: "入金済み",
    unpaid: "入金待ち",
    canceled: "取消済み"
  }.freeze

  DOCUMENT_TYPES = {
    quotation: {
      label: "見積書",
      emoji: "📄",
      sync_key: "sync_quotations",
      sync_checkbox_id: "sync_quotations",
      settings_block_id: "quotation_settings",
      ticket_source_key: "ticket_source_quotation",
      ticket_sources: [
        ["subject", "件名 (subject)"],
        ["quotation_number", "見積書番号 (quotation_number)"]
      ],
      endpoint: "/iv/quotations",
      report_path: "/reports/quotations",
      priority_score: 0,
      settings_prefix: "quotation",
      statuses: [:sent, :unsent, :canceled],
      include_payment: false,
      status_rules: [
        { field: "cancel_status", value: "canceled", status: :canceled },
        { field: "sending_status", value: "sent", status: :sent },
        { field: "sending_status", value: "unsent", status: :unsent }
      ],
      default_templates: {
        unsent: "🧾 freee に {amount} 円の見積書が作成されました\nURL: {url}",
        sent: "📤 freee で {amount} 円の見積書が送信されました\nURL: {url}",
        canceled: "❌ freee で見積書が取り消されました\nURL: {url}"
      }
    },
    invoice: {
      label: "請求書",
      emoji: "🧾",
      sync_key: "sync_invoices",
      sync_checkbox_id: "sync_invoices",
      settings_block_id: "invoice_settings",
      ticket_source_key: "ticket_source_invoice",
      ticket_sources: [
        ["subject", "件名 (subject)"],
        ["invoice_number", "請求書番号 (invoice_number)"]
      ],
      endpoint: "/iv/invoices",
      report_path: "/reports/invoices",
      priority_score: 1,
      settings_prefix: "invoice",
      statuses: [:sent, :unsent, :paid, :unpaid, :canceled],
      include_payment: true,
      status_rules: [
        { field: "cancel_status", value: "canceled", status: :canceled },
        { field: "payment_status", value: "settled", status: :paid },
        { field: "sending_status", value: "sent", status: :sent },
        { field: "sending_status", value: "unsent", status: :unsent },
        { field: "payment_status", value: "unsettled", status: :unpaid }
      ],
      default_templates: {
        unsent: "🧾 freee に {amount} 円の請求書が作成されました\nURL: {url}",
        sent: "📤 freee で {amount} 円の請求書が送信されました\nURL: {url}",
        unpaid: "💰 freee で {amount} 円の入金待ちです\nURL: {url}",
        paid: "💰 freee で {amount} 円の入金が確認されました\nURL: {url}",
        canceled: "❌ freee で請求書が取り消されました\nURL: {url}"
      }
    },
    delivery_slip: {
      label: "納品書",
      emoji: "🧾",
      sync_key: "sync_delivery_slips",
      sync_checkbox_id: "sync_delivery_slips",
      settings_block_id: "delivery_settings",
      ticket_source_key: "ticket_source_delivery",
      ticket_sources: [
        ["subject", "件名 (subject)"],
        ["delivery_slip_number", "納品書番号 (delivery_slip_number)"]
      ],
      endpoint: "/iv/delivery_slips",
      report_path: "/reports/delivery_slips",
      priority_score: 2,
      settings_prefix: "delivery_slip",
      statuses: [:sent, :unsent, :paid, :unpaid, :canceled],
      include_payment: true,
      status_rules: [
        { field: "cancel_status", value: "canceled", status: :canceled },
        { field: "payment_status", value: "settled", status: :paid },
        { field: "sending_status", value: "sent", status: :sent },
        { field: "sending_status", value: "unsent", status: :unsent },
        { field: "payment_status", value: "unsettled", status: :unpaid }
      ],
      default_templates: {
        unsent: " 📦 freee に {amount} 円の納品書が作成されました\nURL: {url}",
        sent: "📤 freee で {amount} 円の納品書が送信されました\nURL: {url}",
        unpaid: "💰 freee で {amount} 円の入金待ちです\nURL: {url}",
        paid: "💰 freee で {amount} 円の入金が確認されました\nURL: {url}",
        canceled: "❌ freee で納品書が取り消されました\nURL: {url}"
      }
    }
  }.freeze

  def self.document_types
    DOCUMENT_TYPES
  end

  def self.status_label(status)
    STATUS_LABELS.fetch(status)
  end

  def self.status_short_label(status)
    STATUS_SHORT_LABELS.fetch(status)
  end

  def self.defn(doc_type)
    DOCUMENT_TYPES.fetch(doc_type)
  end
end
