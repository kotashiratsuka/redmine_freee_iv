# plugins/redmine_freee/lib/tasks/sync.rake
require "active_support/number_helper"

# ===== コメント投稿ユーザー =====
def freee_update_user
  uid = Setting.plugin_redmine_freee['user_id'].presence || 1
  User.find(uid)
end

# ===== テンプレート適用 =====
def apply_template(template, vars = {})
  return "" if template.blank?
  vars.reduce(template.to_s) do |msg, (key, val)|
    msg.gsub("{#{key}}", val.to_s)
  end
end

# =====================================================================
#  共通ロジック本体（DRY-RUN / SYNC を統合）
# =====================================================================
def run_sync(dry_run:)
  plugin = Setting.plugin_redmine_freee

  # ==== 設定 ====
  sync_quotations = plugin['sync_quotations'] == '1'
  sync_invoices   = plugin['sync_invoices']  == '1'

  # 見積ステータス
  quotation_sent_id   = plugin['quotation_sent_status'].to_i
  quotation_unsent_id = plugin['quotation_unsent_status'].to_i

  # 見積コメントテンプレート
  tpl_q_sent   = plugin['quotation_sent_comment']
  tpl_q_unsent = plugin['quotation_unsent_comment']

  # 請求書ステータス
  inv_sent_id   = plugin['invoice_sent_status'].to_i
  inv_unsent_id = plugin['invoice_unsent_status'].to_i
  inv_paid_id   = plugin['invoice_paid_status'].to_i
  inv_unpaid_id = plugin['invoice_unpaid_status'].to_i

  # 請求書コメントテンプレート
  tpl_i_sent   = plugin['invoice_sent_comment']
  tpl_i_unsent = plugin['invoice_unsent_comment']
  tpl_i_paid   = plugin['invoice_paid_comment']
  tpl_i_unpaid = plugin['invoice_unpaid_comment']

  puts(dry_run ? "[freee] Start DRY-RUN..." : "[freee] Start sync...")

  companies = FreeeApiClient.companies

  companies.each do |comp|
    company_id = comp["id"]

    # =====================================================================
    #  見積
    # =====================================================================
    if sync_quotations
      begin
        quotations = FreeeApiClient.get("/iv/quotations", company_id: company_id)
      rescue OAuth2::Error => e
        puts "[freee][SKIP quotation] company_id=#{company_id} 権限なし (#{e.message})"
        quotations = {}
      end

      (quotations["quotations"] || []).each do |q|
        number = q["quotation_number"]
        status = q["sending_status"]
        amount = q["total_amount"]

        next unless number.to_s =~ /^#?(\d+)$/

        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        amount_fmt    = ActiveSupport::NumberHelper.number_to_delimited(amount)
        quotation_url = "https://invoice.secure.freee.co.jp/reports/quotations/#{q['id']}"

        # === 遷移先判定 ===
        new_status_id =
          case status
          when "sent"   then quotation_sent_id
          when "unsent" then quotation_unsent_id
          else                0
          end

        next_status =
          if new_status_id.zero?
            "変更しない"
          else
            IssueStatus.find_by(id: new_status_id)&.name || "不明"
          end

        # === DRY-RUN ===
        if dry_run
          puts "[freee][DRY quotation] ##{issue_id} sending_status=#{status}, amount=#{amount_fmt} " \
               "(current=#{issue.status.name}, next=#{next_status})"
          next
        end

        # === 本番 ===
        next if new_status_id.zero?
        next if issue.status_id == new_status_id

        template =
          case status
          when "sent"   then tpl_q_sent
          when "unsent" then tpl_q_unsent
          else ""
          end

        message = apply_template(
          template,
          amount: amount_fmt,
          url:    quotation_url,
          status: status
        )

        puts "[freee][UPDATE] ##{issue_id} → #{next_status}"

        issue.init_journal(freee_update_user, message)
        issue.status_id = new_status_id
        issue.save!
      end
    end

    # =====================================================================
    #  請求書
    # =====================================================================
    if sync_invoices
      begin
        invoices = FreeeApiClient.get("/iv/invoices", company_id: company_id)
      rescue OAuth2::Error => e
        puts "[freee][SKIP invoice] company_id=#{company_id} 権限なし (#{e.message})"
        next
      end

      (invoices["invoices"] || []).each do |inv|
        invoice_id = inv['id']
        number     = inv['invoice_number']
        mail       = inv['sending_status']
        payment    = inv['payment_status']
        amount     = inv['total_amount']

        next unless number.to_s =~ /^#?(\d+)$/

        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        amount_fmt  = ActiveSupport::NumberHelper.number_to_delimited(amount)
        invoice_url = "https://invoice.secure.freee.co.jp/reports/invoices/#{invoice_id}"

        # === 遷移先判定 ===
        new_status_id =
          if payment == "settled"
            inv_paid_id
          elsif mail == "sent"
            inv_sent_id
          elsif mail == "unsent"
            inv_unsent_id
          elsif payment == "unsettled"
            inv_unpaid_id
          else
            puts "[freee][WARN] unknown invoice status mail=#{mail}, payment=#{payment} → skip"
            0
          end

        next_status =
          if new_status_id.zero?
            "変更しない"
          else
            IssueStatus.find_by(id: new_status_id)&.name || "不明"
          end

        # === DRY-RUN ===
        if dry_run
          puts "[freee][DRY invoice] ##{issue_id} mail=#{mail}, payment=#{payment}, amount=#{amount_fmt} " \
               "(current=#{issue.status.name}, next=#{next_status})"
          next
        end

        # === 本番 ===
        next if new_status_id.zero?
        next if issue.status_id == new_status_id

        template =
          if payment == "settled"
            tpl_i_paid
          elsif mail == "sent"
            tpl_i_sent
          elsif mail == "unsent"
            tpl_i_unsent
          else
            tpl_i_unpaid
          end

        message = apply_template(
          template,
          amount:  amount_fmt,
          url:     invoice_url,
          mail:    mail,
          payment: payment
        )

        puts "[freee][UPDATE] ##{issue_id} → #{next_status}"

        issue.init_journal(freee_update_user, message)
        issue.status_id = new_status_id
        issue.save!
      end
    end
  end

  puts(dry_run ? "[freee] DRY-RUN finished." : "[freee] sync finished.")
end

# =====================================================================
# TASK 定義（DRY-RUN と sync の呼び出しだけ）
# =====================================================================
namespace :freee do
  desc 'freee 見積・請求ステータス DRY-RUN'
  task dry_run: :environment do
    run_sync(dry_run: true)
  end

  desc 'freee 見積・請求ステータス 同期（本番）'
  task sync: :environment do
    run_sync(dry_run: false)
  end
end
