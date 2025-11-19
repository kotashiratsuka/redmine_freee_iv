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

  apply_final_only     = plugin['apply_final_only'] == '1'

  # === 見積ステータス / テンプレート ===
  quotation_sent_id   = plugin['quotation_sent_status'].to_i
  quotation_unsent_id = plugin['quotation_unsent_status'].to_i
  tpl_q_sent          = plugin['quotation_sent_comment']
  tpl_q_unsent        = plugin['quotation_unsent_comment']

  # === 請求書ステータス / テンプレート ===
  inv_sent_id   = plugin['invoice_sent_status'].to_i
  inv_unsent_id = plugin['invoice_unsent_status'].to_i
  inv_paid_id   = plugin['invoice_paid_status'].to_i
  inv_unpaid_id = plugin['invoice_unpaid_status'].to_i

  tpl_i_sent   = plugin['invoice_sent_comment']
  tpl_i_unsent = plugin['invoice_unsent_comment']
  tpl_i_paid   = plugin['invoice_paid_comment']
  tpl_i_unpaid = plugin['invoice_unpaid_comment']

  # === 納品書ステータス / テンプレート ===
  del_sent_id   = plugin['delivery_slip_sent_status'].to_i
  del_unsent_id = plugin['delivery_slip_unsent_status'].to_i
  del_paid_id   = plugin['delivery_slip_paid_status'].to_i
  del_unpaid_id = plugin['delivery_slip_unpaid_status'].to_i

  tpl_d_sent   = plugin['delivery_slip_sent_comment']
  tpl_d_unsent = plugin['delivery_slip_unsent_comment']
  tpl_d_paid   = plugin['delivery_slip_paid_comment']
  tpl_d_unpaid = plugin['delivery_slip_unpaid_comment']

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

      quotations.each do |q|
        subject = q["subject"].to_s
        status  = q["sending_status"]
        amount  = q["total_amount"]

        # [#1234] → issue_id
        next unless subject =~ /\[#?(\d+)\]/
        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        amount_fmt    = ActiveSupport::NumberHelper.number_to_delimited(amount)
        quotation_url = "https://invoice.secure.freee.co.jp/reports/quotations/#{q['id']}"

        new_status_id =
          case status
          when "sent"   then quotation_sent_id
          when "unsent" then quotation_unsent_id
          else                0
          end

        next_status =
          new_status_id.zero? ? "変更しない" :
            (IssueStatus.find_by(id: new_status_id)&.name || "不明")

        if dry_run
          puts "[freee][DRY quotation] ##{issue_id} status=#{status}, amount=#{amount_fmt} (current=#{issue.status.name}, next=#{next_status})"
          next
        end

        # 0（変更しない）は候補にもしない
        next if new_status_id.zero?

        template =
          case status
          when "sent"   then tpl_q_sent
          when "unsent" then tpl_q_unsent
          else ""
          end

        vars = {
          amount: amount_fmt,
          url:    quotation_url,
          status: status
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

      invoices.each do |inv|
        subject    = inv['subject'].to_s
        mail       = inv['sending_status']
        payment    = inv['payment_status']
        amount     = inv['total_amount']
        invoice_id = inv['id']

        # subject から [#1234]
        next unless subject =~ /\[#?(\d+)\]/
        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        amount_fmt  = ActiveSupport::NumberHelper.number_to_delimited(amount)
        invoice_url = "https://invoice.secure.freee.co.jp/reports/invoices/#{invoice_id}"

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
          new_status_id.zero? ? "変更しない" :
            (IssueStatus.find_by(id: new_status_id)&.name || "不明")

        if dry_run
          puts "[freee][DRY invoice] ##{issue_id} mail=#{mail}, payment=#{payment}, amount=#{amount_fmt} (current=#{issue.status.name}, next=#{next_status})"
          next
        end

        # 0（変更しない）は候補にもしない
        next if new_status_id.zero?

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

      delivery_slips.each do |del|
        subject          = del['subject'].to_s
        mail             = del['sending_status']
        payment          = del['payment_status']
        amount           = del['total_amount']
        delivery_slip_id = del['id']

        # subject から [#1234]
        next unless subject =~ /\[#?(\d+)\]/
        issue_id = Regexp.last_match(1).to_i
        issue    = Issue.find_by(id: issue_id)
        next unless issue

        amount_fmt        = ActiveSupport::NumberHelper.number_to_delimited(amount)
        delivery_slip_url = "https://invoice.secure.freee.co.jp/reports/delivery_slips/#{delivery_slip_id}"

        new_status_id =
          if payment == "settled"
            del_paid_id
          elsif mail == "sent"
            del_sent_id
          elsif mail == "unsent"
            del_unsent_id
          elsif payment == "unsettled"
            del_unpaid_id
          else
            puts "[freee][WARN] unknown delivery_slip status mail=#{mail}, payment=#{payment} → skip"
            0
          end

        next_status =
          new_status_id.zero? ? "変更しない" :
            (IssueStatus.find_by(id: new_status_id)&.name || "不明")

        if dry_run
          puts "[freee][DRY delivery_slip] ##{issue_id} mail=#{mail}, payment=#{payment}, amount=#{amount_fmt} (current=#{issue.status.name}, next=#{next_status})"
          next
        end

        # 0（変更しない）は候補にもしない
        next if new_status_id.zero?

        template =
          if payment == "settled"
            tpl_d_paid
          elsif mail == "sent"
            tpl_d_sent
          elsif mail == "unsent"
            tpl_d_unsent
          else
            tpl_d_unpaid
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
  if apply_final_only && !dry_run
    updates.each do |issue_id, info|
      score = info[:score]
      next if score.nil? || score < 0

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
