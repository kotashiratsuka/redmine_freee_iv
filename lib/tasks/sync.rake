# plugins/redmine_freee/lib/tasks/sync.rake
require "active_support/number_helper"

namespace :freee do
  desc 'freee請求書の入金状況を Redmine Issue に反映（DRY-RUN）'
  task dry_run_match: :environment do
    puts '[freee] Start DRY-RUN invoice matching...'

    begin
      companies = FreeeApiClient.companies

      companies.each do |comp|
        company_id = comp["id"]

        begin
          invoices = FreeeApiClient.get("/iv/invoices",
                                        company_id: company_id,
                                        payment_status: "settled"
                                       )
        rescue OAuth2::Error => e
          puts "[freee][SKIP] company_id=#{company_id} は権限なし → スキップ (#{e.message})"
          next
        end

        list = invoices["invoices"] || []

        puts "[freee] Invoices count: #{list.size}"

        list.each do |inv|
          invoice_number = inv['invoice_number']              # "#6541"
          partner_name   = inv['partner_name']
          amount         = inv['amount_including_tax']
          status         = inv['payment_status']              # "settled" / "unsettled"

          # --- freee invoice_number → チケット番号変換 ---
          next unless invoice_number.to_s =~ /^#?(\d+)$/
          issue_id = Regexp.last_match(1).to_i

          issue = Issue.find_by(id: issue_id)
          if issue.nil?
            puts "[freee][SKIP] invoice #{invoice_number}: 対応するIssueなし"
            next
          end

          current_status_name = issue.status.name rescue '?'

          if status == 'settled'
            puts "[freee][DRY-RUN] Issue ##{issue_id} '#{issue.subject}'"
            puts "    partner: #{partner_name}"
            puts "    amount:  #{amount}"
            puts '    freee payment: settled'
            puts "    current Redmine status: #{current_status_name}"

            if issue.status.is_closed?
              puts '    → 既に完了済み'
            else
              puts '    → (DRY-RUN) このIssueは完了にする必要があります'
            end
          else
            puts "[freee][INFO] Issue ##{issue_id} は未入金 (#{status})"
          end
        end
      end

      puts '[freee] DRY-RUN Finish.'
    rescue => e
      puts "[freee] ERROR: #{e.class} #{e.message}"
      Rails.logger.error "[freee] ERROR: #{e.class} #{e.message}"
      raise e
    end
  end

  desc 'freee請求書の入金状況を Redmine Issue に反映（本番更新）'
  task sync_invoices: :environment do

    PAID_STATUS_ID = IssueStatus.find_by(name: "入金済")&.id

    puts '[freee] Start REAL invoice sync...'

    begin
      companies = FreeeApiClient.companies

      companies.each do |comp|
        company_id = comp["id"]

        begin
          invoices = FreeeApiClient.get("/iv/invoices",
                                        company_id: company_id,
                                        payment_status: "settled"
                                       )
        rescue OAuth2::Error => e
          puts "[freee][SKIP] company_id=#{company_id} は権限なし → スキップ (#{e.message})"
          next
        end

        list = invoices["invoices"] || []

        puts "[freee] Invoices count: #{list.size}"

        list.each do |inv|
          invoice_id   = inv['id']
          number       = inv['invoice_number']
          payment      = inv['payment_status']        # "settled" / "unsettled"
          amount       = inv['total_amount']
          partner      = inv['partner_name'].to_s
          issue_id     = number.to_s[/\d+/].to_i rescue nil

          # Web から直接開ける請求書URL
          invoice_url = "https://invoice.secure.freee.co.jp/reports/invoices/#{invoice_id}"

          unless issue_id && issue_id > 0
            puts "[freee][SKIP] invoice #{number}: 対応するIssueなし"
            next
          end

          issue = Issue.find_by(id: issue_id)
          unless issue
            puts "[freee][SKIP] Issue ##{issue_id} は存在しません"
            next
          end

          if payment == 'settled'
            # すでに入金済ステータスならスキップ
            if issue.status_id == PAID_STATUS_ID
              puts "[freee][OK] Issue ##{issue_id} はすでに 入金済"
              next
            end

            # ===== コメント作成 =====
            timestamp = Time.current.strftime('%Y-%m-%d %H:%M')
            delimited_amount = ActiveSupport::NumberHelper.number_to_delimited(amount)
            comment = <<~TEXT
              🤖 #{timestamp} に freee で #{delimited_amount}円 の入金が確認されました 💰
              請求書URL: #{invoice_url}
            TEXT

            puts "[freee][UPDATE] Issue ##{issue_id} → 入金済"
            puts "[freee][COMMENT] #{comment.strip}"

            # ===== Redmine 更新（1 save で status & comment → Slack にも載る）=====
            issue.init_journal(User.find(312), comment) # User 312 = あなたのユーザーでOK
            issue.status_id = PAID_STATUS_ID
            issue.save!

            Redmine::Hook.call_hook(
              :controller_issues_edit_after_save,
              controller: nil,
              issue: issue,
              journal: issue.current_journal
            )

          else
            puts "[freee][INFO] Issue ##{issue_id} は未入金 (#{payment})"
          end
        end

      end
      puts '[freee] REAL sync finished.'
    rescue => e
      puts "[freee] ERROR: #{e.class} #{e.message}"
      Rails.logger.error "[freee] ERROR: #{e.class} #{e.message}"
      raise e
    end
  end
end
