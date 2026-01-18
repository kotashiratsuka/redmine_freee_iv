# frozen_string_literal: true

# 見積書・請求書・納品書の同期処理を共通化するクラス
class DocumentSyncProcessor
  include FreeeIssueSupport

  attr_reader :doc_type, :config, :dry_run, :ignored_status_ids, :apply_final_only

  # doc_type: :quotation, :invoice, :delivery_slip
  # config: ステータスID、テンプレート、チケット抽出元などの設定
  # options: dry_run, ignored_status_ids, apply_final_only
  def initialize(doc_type, config, options = {})
    @doc_type = doc_type
    @config = config
    @dry_run = options[:dry_run] || false
    @ignored_status_ids = options[:ignored_status_ids] || []
    @apply_final_only = options[:apply_final_only] || false
    @definition = DocumentTypeDefinitions.defn(doc_type)
  end

  # 単一の書類を処理し、updatesバッファに結果を格納
  # updates: { issue_id => { score:, new_status_id:, template:, vars:, next_status: } }
  def process_document(document, updates)
    issue_id = extract_issue_id(document)
    return unless issue_id

    issue = Issue.find_by(id: issue_id)
    return unless issue

    # 書類の状態を判定
    status_key = determine_status_key(document)
    new_status_id = status_key ? config[:"#{status_key}_status_id"].to_i : 0
    next_status = status_name(new_status_id)
    current_status_id = issue.status_id

    # 無視ステータスのチェック
    if should_ignore?(current_status_id)
      log_ignore(issue_id, current_status_id)
      return
    end

    # 変更しないステータス（0）のチェック
    if new_status_id.zero?
      log_skip(issue_id)
      return
    end

    # テンプレートと変数
    template = status_key ? config[:"#{status_key}_template"] : ""
    vars = build_template_vars(document)

    # 最終ステータスのみモード: 候補を積む
    if apply_final_only
      store_candidate(updates, issue_id, new_status_id, template, vars, next_status)
    end

    # ログ出力
    log_process(issue_id, document, issue, next_status)

    # DRY-RUN または apply_final_only の場合はここまで
    return if dry_run || apply_final_only

    # 即時更新
    update_issue(issue, new_status_id, template, vars, next_status)
  end

  private

  # チケット番号を抽出
  def extract_issue_id(document)
    field = config[:ticket_source].to_s
    value = field == "subject" ? document["subject"].to_s : document[field].to_s

    return nil unless value =~ /\[#?(\d+)\]/
    Regexp.last_match(1).to_i
  end

  # 書類の状態からステータスキーを判定
  def determine_status_key(document)
    @definition[:status_rules].each do |rule|
      return rule[:status] if document[rule[:field]] == rule[:value]
    end

    warn_unknown_status(document)
    nil
  end

  # テンプレート変数を構築
  def build_template_vars(document)
    amount = document["total_amount"]
    amount_fmt = ActiveSupport::NumberHelper.number_to_delimited(amount)
    doc_id = document["id"]
    url = "https://invoice.secure.freee.co.jp#{@definition[:report_path]}/#{doc_id}"

    vars = {
      amount: amount_fmt,
      url: url,
      mail: document["sending_status"]
    }

    # 請求書と納品書はpayment情報も含む
    vars[:payment] = document["payment_status"] if @definition[:include_payment]

    vars
  end

  # 無視ステータスかチェック
  def should_ignore?(current_status_id)
    ignored_status_ids.include?(current_status_id)
  end

  # 最終候補をバッファに格納
  def store_candidate(updates, issue_id, new_status_id, template, vars, next_status)
    score = config[:priority_score]
    cand = updates[issue_id]
    if cand[:score].nil? || score >= cand[:score].to_i
      updates[issue_id] = {
        score: score,
        new_status_id: new_status_id,
        template: template,
        vars: vars,
        next_status: next_status
      }
    end
  end

  # Issueを更新
  def update_issue(issue, new_status_id, template, vars, next_status)
    return if issue.status_id == new_status_id

    message = apply_template(template, vars)
    puts "#{log_prefix('UPDATE')} ##{issue.id} next=#{next_status}"

    issue.init_journal(freee_update_user, message)
    issue.status_id = new_status_id
    issue.save!
  end

  # ヘルパーメソッド

  def status_name(status_id)
    status_id.zero? ? "変更しない" : (IssueStatus.find_by(id: status_id)&.name || "不明")
  end

  def log_ignore(issue_id, current_status_id)
    label = IssueStatus.find_by(id: current_status_id)&.name || "ID=#{current_status_id}"
    puts "#{log_prefix('IGNORE')} ##{issue_id} current=#{label} reason=protected_status"
  end

  def log_skip(issue_id)
    puts "#{log_prefix('SKIP')} ##{issue_id} reason=new_status_id=0"
  end

  def log_process(issue_id, document, issue, next_status)
    doc_type_str = doc_type.to_s
    mail = document["sending_status"]
    amount_fmt = ActiveSupport::NumberHelper.number_to_delimited(document["total_amount"])

    parts = ["mail=#{mail}"]
    parts << "payment=#{document["payment_status"]}" if @definition[:include_payment]
    parts << "amount=#{amount_fmt}"

    puts "#{log_prefix('PROCESS', doc_type: doc_type_str)} ##{issue_id} #{parts.join(', ')} current=#{issue.status.name} next=#{next_status}"
  end

  def warn_unknown_status(document)
    mail = document["sending_status"]
    payment = document["payment_status"]
    detail = @definition[:include_payment] ? "mail=#{mail}, payment=#{payment}" : "mail=#{mail}"
    puts "#{log_prefix('WARN', doc_type: doc_type)} unknown_status #{detail} action=skip"
  end

  def log_prefix(action, doc_type: nil)
    tag = dry_run ? "DRY" : "SYNC"
    parts = ["[freee]", "[#{tag}]"]
    parts << "[#{doc_type}]" if doc_type
    parts << "[#{action}]"
    parts.join
  end
end
