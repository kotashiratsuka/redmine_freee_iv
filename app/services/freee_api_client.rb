class FreeeApiClient
  TOKEN_URL = 'https://accounts.secure.freee.co.jp/public_api/token'
  API_BASE  = 'https://api.freee.co.jp'

  class << self

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


    def get(path, params = {})
      token = current_access_token
      raise "No freee credentials" unless token

      res = token.get("#{API_BASE}#{path}", params: params)
      JSON.parse(res.body)
    end

    def companies
      res = get("/api/1/companies")
      res["companies"] || []
    rescue OAuth2::Error => e
      Rails.logger.error("[freee] companies fetch error: #{e.message}")
      []
    end

    private

    def oauth_client
      OAuth2::Client.new(
        RedmineFreeeAuthController::CLIENT_ID,
        RedmineFreeeAuthController::CLIENT_SECRET,
        token_url: TOKEN_URL
      )
    end

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
