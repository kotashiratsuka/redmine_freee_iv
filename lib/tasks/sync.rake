# plugins/redmine_freee_iv/lib/tasks/sync.rake
require "active_support/number_helper"
require_relative "../../app/services/document_type_definitions"
require_relative "../../app/services/freee_issue_support"

# ===== 書類タイプごとの設定を構築 =====
def build_document_config(doc_type, plugin)
  defn = DocumentTypeDefinitions.document_types.fetch(doc_type)
  config = {
    ticket_source: plugin[defn[:ticket_source_key]] || "subject",
    priority_score: defn[:priority_score]
  }

  defn[:statuses].each do |status|
    prefix = defn[:settings_prefix]
    config[:"#{status}_status_id"] = plugin["#{prefix}_#{status}_status"].to_i
    config[:"#{status}_template"] = plugin["#{prefix}_#{status}_comment"]
  end

  config
end

# =====================================================================
#  共通ロジック本体（DRY-RUN / SYNC を統合）
# =====================================================================
def run_sync(dry_run:)
  plugin = Setting.plugin_redmine_freee_iv

  ignored_status_ids   = Array(plugin['ignored_status_ids']).map(&:to_i)
  apply_final_only     = plugin['apply_final_only'] == '1'

  # === 設定値（100,200,300,...,unlimited） ===
  raw_total = plugin['max_fetch_total']
  max_total = (raw_total == 'unlimited' ? :unlimited : raw_total.to_i)

  tag = dry_run ? "DRY" : "SYNC"
  max_total_label = (max_total == :unlimited ? "unlimited" : max_total)
  puts "#{log_prefix(tag, 'START')} apply_final_only=#{apply_final_only} max_total=#{max_total_label}"

  # ===============================
  #   会社ループ
  # ===============================
  company_ids = FreeeApiClient.active_companies

  if company_ids.empty?
    puts "#{log_prefix(tag, 'ABORT')} reason=no_authenticated_companies"
    return
  end

  # issue_id ごとの最終候補バッファ
  # { issue_id => { score:, new_status_id:, template:, vars:, next_status: } }
  updates = Hash.new { |h, k| h[k] = { score: -1 } }

  # 書類タイプごとの処理定義
  document_types = DocumentTypeDefinitions.document_types.map do |type, defn|
    {
      type: type,
      enabled: plugin[defn[:sync_key]] == "1",
      endpoint: defn[:endpoint]
    }
  end

  company_ids.each do |company_id|
    document_types.each do |doc_def|
      next unless doc_def[:enabled]

      # 書類を取得
      documents = FreeeApiClient.get_all(
        doc_def[:endpoint],
        company_id: company_id,
        limit: 100,
        max_total: max_total
      )

      # 設定を構築
      config = build_document_config(doc_def[:type], plugin)
      options = {
        dry_run: dry_run,
        ignored_status_ids: ignored_status_ids,
        apply_final_only: apply_final_only
      }

      # プロセッサーを作成して各書類を処理
      processor = DocumentSyncProcessor.new(doc_def[:type], config, options)
      documents.each do |document|
        processor.process_document(document, updates)
      end
    end
  end

  # ==========================
  #   最終ステータスのみ反映
  # ==========================
  updates.each do |issue_id, info|
    score = info[:score]
    next if score.nil? || score < 0

    new_status_id = info[:new_status_id].to_i
    next if new_status_id.zero?

    issue = Issue.find_by(id: issue_id)
    current_name =
      issue&.status&.name || "不明"

    next_status =
      info[:next_status] ||
      (IssueStatus.find_by(id: new_status_id)&.name || "不明")

    will_change = issue && issue.status_id != new_status_id

    # --- DRY / SYNC 共通で必ず final ログを出す ---
    puts "#{log_prefix(tag, 'FINAL')} ##{issue_id} current=#{current_name} next=#{next_status}"
    next if dry_run

    # 実際の更新は変化があるときだけ
    next unless will_change

    template = info[:template]
    vars     = info[:vars] || {}
    message  = FreeeIssueSupport.apply_template(template, vars)

    issue.init_journal(FreeeIssueSupport.freee_update_user, message)
    issue.status_id = new_status_id
    issue.save!
  end
end

def log_prefix(tag, action)
  "[freee][#{tag}][#{action}]"
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
