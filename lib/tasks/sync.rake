# plugins/redmine_freee/lib/tasks/sync.rake
require "active_support/number_helper"

# ===== コメント投稿ユーザー =====
def freee_update_user
  uid = Setting.plugin_redmine_freee['user_id'].presence || 1
  User.find(uid)
end

# ===== ステータスID共通取得 =====
def freee_status_ids
  {
    estimate: IssueStatus.find_by(name: "見積発行")&.id,
    invoice:  IssueStatus.find_by(name: "請求中")&.id,
    paid:     IssueStatus.find_by(name: "入金済")&.id
  }
end

namespace :freee do
  # =========================================================
  # DRY-RUN
  # =========================================================
  desc 'freee請求書の入金状況を Redmine Issue に反映（DRY-RUN）'
  task dry_run: :environment do
    puts '[freee] Start DRY-RUN invoice/quotation matching...'

    begin
      companies = FreeeApiClient.companies

      companies.each do |comp|
        company_id = comp["id"]

        # === 見積 ===
        begin
          quotations = FreeeApiClient.get("/iv/quotations", company_id: company_id)
        rescue OAuth2::Error => e
          puts "[freee][SKIP quotation] company_id=#{company_id} 権限なし (#{e.message})"
          quotations = {}
        end

        (quotations["quotations"] || []).each do |q|
          number = q["quotation_number"]
          status = q["sending_status"]

          next unless number.to_s =~ /^#?(\d+)$/
          issue_id = Regexp.last_match(1).to_i

          issue = Issue.find_by(id: issue_id)
          next unless issue

          puts "[freee][DRY quotation] ##{issue_id} sending_status=#{status} (current=#{issue.status.name})"
        end

        # === 請求 ===
        begin
          invoices = FreeeApiClient.get("/iv/invoices", company_id: company_id)
        rescue OAuth2::Error => e
          puts "[freee][SKIP invoice] company_id=#{company_id} 権限なし (#{e.message})"
          next
        end

        (invoices["invoices"] || []).each do |inv|
          number  = inv["invoice_number"]
          mail    = inv["sending_status"]
          payment = inv["payment_status"]

          next unless number.to_s =~ /^#?(\d+)$/
          issue_id = Regexp.last_match(1).to_i

          issue = Issue.find_by(id: issue_id)
          next unless issue

          puts "[freee][DRY invoice] ##{issue_id} mail=#{mail}, payment=#{payment} (current=#{issue.status.name})"
        end
      end

      puts "[freee] DRY-RUN finished."
    rescue => e
      puts "[freee] ERROR: #{e.class} #{e.message}"
      Rails.logger.error "[freee] ERROR: #{e.class} #{e.message}"
      raise e
    end
  end

  # =========================================================
  # SYNC
  # =========================================================
  desc 'freee 見積・請求・入金を Redmine Issue に自動反映（本番更新）'
  task sync: :environment do
    puts '[freee] Start sync...'

    ids = freee_status_ids
    ESTIMATE_STATUS_ID = ids[:estimate]
    INVOICE_STATUS_ID  = ids[:invoice]
    PAID_STATUS_ID     = ids[:paid]

    begin
      companies = FreeeApiClient.companies

      companies.each do |comp|
        company_id = comp["id"]

        # =============================
        #  見積チェック
        # =============================
        begin
          quotations = FreeeApiClient.get("/iv/quotations",
                                          company_id: company_id)
        rescue OAuth2::Error => e
          puts "[freee][SKIP quotation] company_id=#{company_id} 権限なし (#{e.message})"
          quotations = {}
        end

        (quotations["quotations"] || []).each do |q|
          number = q["quotation_number"]
          mail   = q["sending_status"]
          amount = q["total_amount"]

          next unless number.to_s =~ /^#?(\d+)$/
          issue_id = Regexp.last_match(1).to_i
          issue = Issue.find_by(id: issue_id)
          next unless issue

          next if [ESTIMATE_STATUS_ID, INVOICE_STATUS_ID, PAID_STATUS_ID].include?(issue.status_id)

          if mail == "sent"
            quotation_url = "https://invoice.secure.freee.co.jp/reports/quotations/#{q['id']}"
            delimited_amount = ActiveSupport::NumberHelper.number_to_delimited(amount)

            puts "[freee][UPDATE] ##{issue_id} → 見積発行"

            message = <<~TEXT
              🤖 freee で #{delimited_amount} 円の見積書が送信されました 📨
              URL: #{quotation_url}
            TEXT

            issue.init_journal(freee_update_user, message)
            issue.status_id = ESTIMATE_STATUS_ID
            issue.save!
          end
        end

        # =============================
        #  請求チェック
        # =============================
        begin
          invoices = FreeeApiClient.get("/iv/invoices",
                                        company_id: company_id)
        rescue OAuth2::Error => e
          puts "[freee][SKIP invoice] company_id=#{company_id} 権限なし (#{e.message})"
          next
        end

        (invoices["invoices"] || []).each do |inv|
          invoice_id  = inv['id']
          number      = inv['invoice_number']
          mail_status = inv['sending_status']
          payment     = inv['payment_status']
          amount      = inv['total_amount']

          next unless number.to_s =~ /^#?(\d+)$/
          issue_id = Regexp.last_match(1).to_i
          issue = Issue.find_by(id: issue_id)
          next unless issue

          invoice_url = "https://invoice.secure.freee.co.jp/reports/invoices/#{invoice_id}"
          delimited_amount = ActiveSupport::NumberHelper.number_to_delimited(amount)

          # ----------------------------------------
          # (1) 請求が送信 → 請求中
          # ----------------------------------------
          if mail_status == "sent" && payment != "settled"
            next if [INVOICE_STATUS_ID, PAID_STATUS_ID].include?(issue.status_id)

            puts "[freee][UPDATE] ##{issue_id} → 請求中"

            message = <<~TEXT
              🤖 freee で #{delimited_amount} 円の請求書が送信されました 📤
              URL: #{invoice_url}
            TEXT

            issue.init_journal(freee_update_user, message)
            issue.status_id = INVOICE_STATUS_ID
            issue.save!
            next
          end

          # ----------------------------------------
          # (2) 入金済 → 入金済
          # ----------------------------------------
          if payment == "settled"
            if issue.status_id == PAID_STATUS_ID
              puts "[freee][OK] ##{issue_id} は既に 入金済"
              next
            end

            message = <<~TEXT
              🤖 freee で #{delimited_amount} 円の入金が確認されました 💰
              URL: #{invoice_url}
            TEXT

            puts "[freee][UPDATE] ##{issue_id} → 入金済"

            issue.init_journal(freee_update_user, message)
            issue.status_id = PAID_STATUS_ID
            issue.save!
          end
        end
      end

      puts '[freee] sync finished.'

    rescue => e
      puts "[freee] ERROR: #{e.class} #{e.message}"
      Rails.logger.error "[freee] ERROR: #{e.class} #{e.message}"
      raise e
    end
  end
end
