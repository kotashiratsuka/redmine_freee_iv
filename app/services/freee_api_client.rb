class FreeeApiClient

  AUTHORIZE_URL = "https://accounts.secure.freee.co.jp/public_api/authorize"
  TOKEN_URL     = "https://accounts.secure.freee.co.jp/public_api/token"
  API_BASE      = "https://api.freee.co.jp"

  class << self

    # ======================
    # アクセストークン取得
    # ======================

    def current_access_token(company_id)
      return nil if company_id.blank?
      cred = FreeeIvCredential.find_by(company_id: company_id.to_s)
      return nil unless cred

      if cred.expires_at < 15.minutes.from_now
        cred = refresh!(cred)
      end

      OAuth2::AccessToken.new(
        oauth_client,
        cred.access_token,
        refresh_token: cred.refresh_token,
        expires_at: cred.expires_at.to_i
      )
    end

    # ====== 単発 GET ======
    def get(path, company_id:, params: {})
      token = current_access_token(company_id)
      raise "No freee credentials for company_id=#{company_id}" unless token
      res = token.get("#{API_BASE}#{path}", params: params.merge(company_id: company_id))
      JSON.parse(res.body)
    end

    # どれか1つの事業所で良いのでトークンを取る（会社一覧用）
    def current_access_token_for_any
      cred = FreeeIvCredential.first
      return nil unless cred

      if cred.expires_at < 15.minutes.from_now
        cred = refresh!(cred)
      end

      OAuth2::AccessToken.new(
        oauth_client,
        cred.access_token,
        refresh_token: cred.refresh_token,
        expires_at: cred.expires_at.to_i
      )
    end

    # ====== 会社一覧 ======
    def companies
      token = current_access_token_for_any
      raise "No freee credentials" unless token

      res = token.get("#{API_BASE}/api/1/companies")
      JSON.parse(res.body)["companies"] || []
    rescue OAuth2::Error => e
      Rails.logger.error("[freee] companies fetch error: #{e.message}")
      []
    end

    def active_companies
      FreeeIvCredential.pluck(:company_id).map(&:to_s)
    end


    # ==========================================
    # ★★★ ページング GET（正しい位置）★★★
    # ==========================================
    def get_all(path, company_id:, limit: 20, max_total: 20)
      if max_total == :unlimited
        max_total = Float::INFINITY
      else
        max_total = max_total.to_i
        max_total = 20 if max_total < 20
      end

      offset     = 0
      fetched    = 0
      all_items  = []

      loop do
        break if fetched >= max_total

        begin
          res = get(path, company_id:, params: { limit:, offset: })
        rescue OAuth2::Error => e
          puts "[freee][SKIP] #{path} company_id=#{company_id} 権限なし (#{e.message})"
          break
        end

        items = res.values.first || []
        break if items.empty?

        allowed = max_total - fetched
        batch   = max_total.infinite? ? items : items.first(allowed)

        all_items.concat(batch)
        fetched += batch.size
        offset  += limit
      end

      all_items
    end

    private

    # ====== OAuth クライアント ======
    def oauth_client
      OAuth2::Client.new(
        Setting.plugin_redmine_freee_iv['client_id'],
        Setting.plugin_redmine_freee_iv['client_secret'],
        site: API_BASE,
        authorize_url: AUTHORIZE_URL,
        token_url: TOKEN_URL,
        auth_scheme: :request_body # ← ★freeeの挙動に適合させる
      )
    end

    # ====== リフレッシュ ======
    def refresh!(cred)
      token = OAuth2::AccessToken.new(
        oauth_client,
        cred.access_token,
        refresh_token: cred.refresh_token
      )

      new_token = token.refresh!

      cred.update!(
        access_token:  new_token.token,
        refresh_token: new_token.refresh_token,
        expires_at:    Time.at(new_token.expires_at)
      )

      cred
    end
  end
end
