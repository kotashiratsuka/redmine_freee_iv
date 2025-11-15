class RedmineFreeeAuthController < ApplicationController
  require 'oauth2'

  #
  # === 固定設定（プラグイン設定画面なし）
  #
  CLIENT_ID     = ""
  CLIENT_SECRET = ""
  REDIRECT_URI  = ""

  AUTHORIZE_URL = "https://accounts.secure.freee.co.jp/public_api/authorize"
  TOKEN_URL     = "https://accounts.secure.freee.co.jp/public_api/token"
  API_BASE      = "https://api.freee.co.jp"
  SCOPE         = "read"


  # OAuth2 クライアント
  def oauth_client
    OAuth2::Client.new(
      CLIENT_ID,
      CLIENT_SECRET,
      authorize_url: AUTHORIZE_URL,
      token_url: TOKEN_URL
    )
  end


  #
  # === 認証開始
  #
  def start
    state = SecureRandom.hex(16)
    session[:freee_oauth_state] = state

    redirect_to oauth_client.auth_code.authorize_url(
      redirect_uri: REDIRECT_URI,
      scope: SCOPE,
      state: state,
      prompt: "select_company"
    )
  end


  #
  # === コールバック
  #
  def callback
    if params[:state] != session[:freee_oauth_state]
      render plain: "Invalid state", status: 400
      return
    end

    token = oauth_client.auth_code.get_token(
      params[:code],
      redirect_uri: REDIRECT_URI
    )

    # 保存（company_id は保存しない）
    FreeeCredential.delete_all
    FreeeCredential.create!(
      access_token:  token.token,
      refresh_token: token.refresh_token,
      expires_at:    Time.at(token.expires_at)
    )

    render plain: <<~TEXT
      freee OAuth 認証成功しました。

      Access Token:  #{token.token}
      Refresh Token: #{token.refresh_token}
      Expires At:    #{Time.at(token.expires_at)}
    TEXT
  end
end
