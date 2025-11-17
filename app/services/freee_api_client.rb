class FreeeApiClient

  AUTHORIZE_URL = "https://accounts.secure.freee.co.jp/public_api/authorize"
  TOKEN_URL     = "https://accounts.secure.freee.co.jp/public_api/token"
  API_BASE      = "https://api.freee.co.jp"

  class << self

    # ======================
    # アクセストークン取得
    # ======================
    def current_access_token
      cred = FreeeCredential.first
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
    def get(path, params = {})
      token = current_access_token
      raise "No freee credentials" unless token

      res = token.get("#{API_BASE}#{path}", params: params)
      JSON.parse(res.body)
    end

    # ====== 会社一覧 ======
    def companies
      res = get("/api/1/companies")
      res["companies"] || []
    rescue OAuth2::Error => e
      Rails.logger.error("[freee] companies fetch error: #{e.message}")
      []
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
          res = get(
            path,
            company_id: company_id,
            limit: limit,
            offset: offset
          )
        rescue OAuth2::Error => e
          puts "[freee][SKIP] #{path} company_id=#{company_id} 権限なし (#{e.message})"
          break
        end

        items = res.values.first || []
        break if items.empty?

        allowed = max_total - fetched
        batch   = (max_total.infinite? ? items : items.first(allowed))

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
        Setting.plugin_redmine_freee['client_id'],
        Setting.plugin_redmine_freee['client_secret'],
        site: API_BASE,
        authorize_url: AUTHORIZE_URL,
        token_url: TOKEN_URL
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
