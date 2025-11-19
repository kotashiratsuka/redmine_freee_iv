# plugins/redmine_freee_iv/lib/tasks/sync.rake
require "active_support/number_helper"

# ===== コメント投稿ユーザー =====
def freee_update_user
  uid = Setting.plugin_redmine_freee_iv['user_id'].presence || 1
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
  plugin = Setting.plugin_redmine_freee_iv

  sync_quotations      = plugin['sync_quotations'] == '1'
  sync_invoices        = plugin['sync_invoices']  == '1'
  sync_delivery_slips  = plugin['sync_delivery_slips']  == '1'
  ignored_status_ids   = Array(plugin['ignored_status_ids']).map(&:to_i)

  apply_final_only     = plugin['apply_final_only'] == '1'

  # === 見積ステータス / テンプレート ===
  quotation_sent_id     = plugin['quotation_sent_status'].to_i
  quotation_unsent_id   = plugin['quotation_unsent_status'].to_i
  tpl_quotation_sent    = plugin['quotation_sent_comment']
  tpl_quotation_unsent  = plugin['quotation_unsent_comment']

  # === 請求書ステータス / テンプレート ===
  invoice_sent_id   = plugin['invoice_sent_status'].to_i
  invoice_unsent_id = plugin['invoice_unsent_status'].to_i
  invoice_paid_id   = plugin['invoice_paid_status'].to_i
  invoice_unpaid_id = plugin['invoice_unpaid_status'].to_i

  tpl_invoice_sent   = plugin['invoice_sent_comment']
  tpl_invoice_unsent = plugin['invoice_unsent_comment']
  tpl_invoice_paid   = plugin['invoice_paid_comment']
  tpl_invoice_unpaid = plugin['invoice_unpaid_comment']

  # === 納品書ステータス / テンプレート ===
  delivery_slip_sent_id   = plugin['delivery_slip_sent_status'].to_i
  delivery_slip_unsent_id = plugin['delivery_slip_unsent_status'].to_i
  delivery_slip_paid_id   = plugin['delivery_slip_paid_status'].to_i
  delivery_slip_unpaid_id = plugin['delivery_slip_unpaid_status'].to_i

  tpl_delivery_slip_sent   = plugin['delivery_slip_sent_comment']
  tpl_delivery_slip_unsent = plugin['delivery_slip_unsent_comment']
  tpl_delivery_slip_paid   = plugin['delivery_slip_paid_comment']
  tpl_delivery_slip_unpaid = plugin['delivery_slip_unpaid_comment']

  # === 設定値（100,200,300,...,unlimited） ===
  raw_total = plugin['max_fetch_total']
  max_total = (raw_total == 'unlimited' ? :unlimited : raw_total.to_i)

  puts dry_run ? "[freee] Start DRY-RUN..." : "[freee] Start sync..."

  # ===============================
  #   会社ループ
  # ===============================
  companies = FreeeApiClient.companies

  # issue_id ごとの最終候補バッファ
  # { issue_id => { score:, new_status_id:, template:, vars:, next_status: } }
  updates = Hash.new { |h, k| h[k] = { score: -1 } }

  companies.each do |comp|
    company_id = comp["id"]

    # ==========================
    #   見積 (quotations)
    # ==========================
    if sync_quotations
      quotations = FreeeApiClient.get_all(
        "/iv/quotations",
        company_id: company_id,
        limit: 100,
        max_total: max_total
      )

      quotations.each do |quotation|
        subject      = quotation["subject"].to_s
        mail         = quotation["sending_status"]
        amount       = quotation["total_amount"]
        quotation_id = quotation["id"]

        # [#1234] → issue_id
        next unless subject =~ /\[#?(\d+)\]/
        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        if quotation["cancel_status"] == "canceled"
          puts dry_run ?
            "[freee][DRY][IGNORE] ##{issue_id} cancel_status=canceled (取り消し済み)" :
            "[freee][IGNORE] ##{issue_id} cancel_status=canceled (取り消し済み)"
          next
        end

        amount_fmt    = ActiveSupport::NumberHelper.number_to_delimited(amount)
        quotation_url = "https://invoice.secure.freee.co.jp/reports/quotations/#{quotation_id}"

        new_status_id =
          if mail == "sent"
            quotation_sent_id
          elsif mail == "unsent"
            quotation_unsent_id
          else
            puts "[freee][WARN] unknown quotations status mail=#{mail} → skip"
            0
          end

        next_status =
          new_status_id.zero? ? "変更しない" :
            (IssueStatus.find_by(id: new_status_id)&.name || "不明")

        current_status_id = issue.status_id

        # --- ignore: 現在ステータスが対象 ---
        if ignored_status_ids.include?(current_status_id)
          label = IssueStatus.find_by(id: current_status_id)&.name || "ID=#{current_status_id}"
          puts(dry_run ?
            "[freee][DRY][IGNORE] ##{issue_id} current=#{label} (保護ステータス)" :
            "[freee][IGNORE] ##{issue_id} current=#{label} (保護ステータス)"
          )
          next
        end

        if new_status_id.zero?
          puts(dry_run ?
            "[freee][DRY][SKIP] ##{issue_id} new_status_id=0 (変更しない)" :
            "[freee][SKIP] ##{issue_id} new_status_id=0 (変更しない)"
          )
          next
        end

        puts "[freee][DRY quotation] ##{issue_id} mail=#{mail}, amount=#{amount_fmt} (current=#{issue.status.name}, next=#{next_status})"
        next if dry_run


        # 0（変更しない）は候補にもしない
        next if new_status_id.zero?

        template =
          case mail
          when "sent"   then tpl_quotation_sent
          when "unsent" then tpl_quotation_unsent
          else ""
          end

        vars = {
          amount: amount_fmt,
          url:    quotation_url,
          mail:   mail
        }

        if apply_final_only
          score = 1  # quotation の優先度
          cand  = updates[issue_id]
          if cand[:score].nil? || score >= cand[:score].to_i
            updates[issue_id] = {
              score:         score,
              new_status_id: new_status_id,
              template:      template,
              vars:          vars,
              next_status:   next_status
            }
          end
        else
          next if issue.status_id == new_status_id

          message = apply_template(template, vars)

          puts "[freee][UPDATE] ##{issue_id} → #{next_status}"

          issue.init_journal(freee_update_user, message)
          issue.status_id = new_status_id
          issue.save!
        end
      end
    end

    # ==========================
    #   請求書 (invoices)
    # ==========================
    if sync_invoices
      invoices = FreeeApiClient.get_all(
        "/iv/invoices",
        company_id: company_id,
        limit: 100,
        max_total: max_total
      )

      invoices.each do |invoice|
        subject    = invoice['subject'].to_s
        mail       = invoice['sending_status']
        payment    = invoice['payment_status']
        amount     = invoice['total_amount']
        invoice_id = invoice['id']

        # subject から [#1234]
        next unless subject =~ /\[#?(\d+)\]/
        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        if invoice["cancel_status"] == "canceled"
          puts dry_run ?
            "[freee][DRY][IGNORE] ##{issue_id} cancel_status=canceled (取り消し済み)" :
            "[freee][IGNORE] ##{issue_id} cancel_status=canceled (取り消し済み)"
          next
        end

        amount_fmt  = ActiveSupport::NumberHelper.number_to_delimited(amount)
        invoice_url = "https://invoice.secure.freee.co.jp/reports/invoices/#{invoice_id}"

        new_status_id =
          if payment == "settled"
            invoice_paid_id
          elsif mail == "sent"
            invoice_sent_id
          elsif mail == "unsent"
            invoice_unsent_id
          elsif payment == "unsettled"
            invoice_unpaid_id
          else
            puts "[freee][WARN] unknown invoice status mail=#{mail}, payment=#{payment} → skip"
            0
          end

        next_status =
          new_status_id.zero? ? "変更しない" :
            (IssueStatus.find_by(id: new_status_id)&.name || "不明")

        current_status_id = issue.status_id

        # --- ignore: 現在ステータスが対象 ---
        if ignored_status_ids.include?(current_status_id)
          label = IssueStatus.find_by(id: current_status_id)&.name || "ID=#{current_status_id}"
          puts(dry_run ?
            "[freee][DRY][IGNORE] ##{issue_id} current=#{label} (無視ステータス)" :
            "[freee][IGNORE] ##{issue_id} current=#{label} (無視ステータス)"
          )
          next
        end

        if new_status_id.zero?
          puts(dry_run ?
            "[freee][DRY][SKIP] ##{issue_id} new_status_id=0 (変更しない)" :
            "[freee][SKIP] ##{issue_id} new_status_id=0 (変更しない)"
          )
          next
        end

        puts "[freee][DRY invoice] ##{issue_id} mail=#{mail}, payment=#{payment}, amount=#{amount_fmt} (current=#{issue.status.name}, next=#{next_status})"
        next if dry_run


        # 0（変更しない）は候補にもしない
        next if new_status_id.zero?

        template =
          if payment == "settled"
            tpl_invoice_paid
          elsif mail == "sent"
            tpl_invoice_sent
          elsif mail == "unsent"
            tpl_invoice_unsent
          else
            tpl_invoice_unpaid
          end

        vars = {
          amount:  amount_fmt,
          url:     invoice_url,
          mail:    mail,
          payment: payment
        }

        if apply_final_only
          score = 0  # invoice の優先度
          cand  = updates[issue_id]
          if cand[:score].nil? || score >= cand[:score].to_i
            updates[issue_id] = {
              score:         score,
              new_status_id: new_status_id,
              template:      template,
              vars:          vars,
              next_status:   next_status
            }
          end
        else
          next if issue.status_id == new_status_id

          message = apply_template(template, vars)

          puts "[freee][UPDATE] ##{issue_id} → #{next_status}"

          issue.init_journal(freee_update_user, message)
          issue.status_id = new_status_id
          issue.save!
        end
      end
    end

    # ==========================
    #   納品書 (delivery_slips)
    # ==========================
    if sync_delivery_slips
      delivery_slips = FreeeApiClient.get_all(
        "/iv/delivery_slips",
        company_id: company_id,
        limit: 100,
        max_total: max_total
      )

      delivery_slips.each do |delivery_slip|
        subject          = delivery_slip['subject'].to_s
        mail             = delivery_slip['sending_status']
        payment          = delivery_slip['payment_status']
        amount           = delivery_slip['total_amount']
        delivery_slip_id = delivery_slip['id']

        # subject から [#1234]
        next unless subject =~ /\[#?(\d+)\]/
        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        if delivery_slip["cancel_status"] == "canceled"
          puts dry_run ?
            "[freee][DRY][IGNORE] ##{issue_id} cancel_status=canceled (取り消し済み)" :
            "[freee][IGNORE] ##{issue_id} cancel_status=canceled (取り消し済み)"
          next
        end

        amount_fmt        = ActiveSupport::NumberHelper.number_to_delimited(amount)
        delivery_slip_url = "https://invoice.secure.freee.co.jp/reports/delivery_slips/#{delivery_slip_id}"

        new_status_id =
          if payment == "settled"
            delivery_slip_paid_id
          elsif mail == "sent"
            delivery_slip_sent_id
          elsif mail == "unsent"
            delivery_slip_unsent_id
          elsif payment == "unsettled"
            delivery_slip_unpaid_id
          else
            puts "[freee][WARN] unknown delivery_slip status mail=#{mail}, payment=#{payment} → skip"
            0
          end

        next_status =
          new_status_id.zero? ? "変更しない" :
            (IssueStatus.find_by(id: new_status_id)&.name || "不明")

        current_status_id = issue.status_id

        # --- ignore: 現在ステータスが対象 ---
        if ignored_status_ids.include?(current_status_id)
          label = IssueStatus.find_by(id: current_status_id)&.name || "ID=#{current_status_id}"
          puts(dry_run ?
            "[freee][DRY][IGNORE] ##{issue_id} current=#{label} (無視ステータス)" :
            "[freee][IGNORE] ##{issue_id} current=#{label} (無視ステータス)"
          )
          next
        end

        if new_status_id.zero?
          puts(dry_run ?
            "[freee][DRY][SKIP] ##{issue_id} new_status_id=0 (変更しない)" :
            "[freee][SKIP] ##{issue_id} new_status_id=0 (変更しない)"
          )
          next
        end

        puts "[freee][DRY delivery_slip] ##{issue_id} mail=#{mail}, payment=#{payment}, amount=#{amount_fmt} (current=#{issue.status.name}, next=#{next_status})"
        next if dry_run

        # 0（変更しない）は候補にもしない
        next if new_status_id.zero?

        template =
          if payment == "settled"
            tpl_delivery_slip_paid
          elsif mail == "sent"
            tpl_delivery_slip_sent
          elsif mail == "unsent"
            tpl_delivery_slip_unsent
          else
            tpl_delivery_slip_unpaid
          end

        vars = {
          amount:  amount_fmt,
          url:     delivery_slip_url,
          mail:    mail,
          payment: payment
        }

        if apply_final_only
          score = 2  # delivery_slip の優先度（最強）
          cand  = updates[issue_id]
          if cand[:score].nil? || score >= cand[:score].to_i
            updates[issue_id] = {
              score:         score,
              new_status_id: new_status_id,
              template:      template,
              vars:          vars,
              next_status:   next_status
            }
          end
        else
          next if issue.status_id == new_status_id

          message = apply_template(template, vars)

          puts "[freee][UPDATE] ##{issue_id} → #{next_status}"

          issue.init_journal(freee_update_user, message)
          issue.status_id = new_status_id
          issue.save!
        end
      end
    end
  end

  # ==========================
  #   最終ステータスのみ反映
  # ==========================
  updates.each do |issue_id, info|
    score = info[:score]
    next if score.nil? || score < 0

    # --- DRY の場合も同じ順番で出す ---
    if dry_run
      next_status = info[:next_status] ||
                    (IssueStatus.find_by(id: info[:new_status_id])&.name || "不明")

      puts "[freee][DRY final] ##{issue_id} → #{next_status}"
      next
    end

    issue = Issue.find_by(id: issue_id)
    next unless issue

    new_status_id = info[:new_status_id].to_i
    next if new_status_id.zero?
    next if issue.status_id == new_status_id

    template    = info[:template]
    vars        = info[:vars] || {}
    next_status = info[:next_status] ||
                  (IssueStatus.find_by(id: new_status_id)&.name || "不明")

    message = apply_template(template, vars)

    puts "[freee][UPDATE final] ##{issue_id} → #{next_status}"

    issue.init_journal(freee_update_user, message)
    issue.status_id = new_status_id
    issue.save!
  end
end

# =====================================================================
# TASK 定義
# =====================================================================
namespace :freee_iv do
  desc 'freee 見積・請求ステータス DRY-RUN'
  task dry_run: :environment do
    run_sync(dry_run: true)
  end

  desc 'freee 見積・請求ステータス 同期 SYNC'
  task sync: :environment do
    run_sync(dry_run: false)
  end
end
