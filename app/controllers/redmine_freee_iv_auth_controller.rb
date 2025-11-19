class RedmineFreeeIvAuthController < ApplicationController
  require 'oauth2'

  #
  # === プラグイン設定ヘルパー
  #
  def plugin_settings
    Setting.plugin_redmine_freee_iv
  end

  def sync_quotations?
    plugin_settings['sync_quotations'] == '1'
  end

  def sync_invoices?
    plugin_settings['sync_invoices'] == '1'
  end

  def sync_delivery_slips?
    plugin_settings['sync_delivery_slips'] == '1'
  end

  def quotation_sent_status_id
    plugin_settings['quotation_sent_status'].to_i
  end

  def invoice_sent_status_id
    plugin_settings['invoice_sent_status'].to_i
  end

  def invoice_paid_status_id
    plugin_settings['invoice_paid_status'].to_i
  end

  def client_id
    plugin_settings['client_id']
  end

  def client_secret
    plugin_settings['client_secret']
  end

  def scope
    "read"
  end


  #
  # === 動的 REDIRECT_URI
  # https + ドメイン + /redmine_freee_iv/auth/callback
  #
  def redirect_uri
    URI.join(
      "#{request.protocol}#{request.host_with_port}",
      redmine_freee_iv_auth_callback_path
    ).to_s
  end


  #
  # === OAuth2 クライアント
  #
  def oauth_client
    OAuth2::Client.new(
      client_id,
      client_secret,
      site:       "https://api.freee.co.jp",
      authorize_url: "https://accounts.secure.freee.co.jp/public_api/authorize",
      token_url:     "https://accounts.secure.freee.co.jp/public_api/token"
    )
  end


  #
  # === 認証開始（/start）
  #
  def start
    state = SecureRandom.hex(16)
    session[:freee_oauth_state] = state

    redirect_to oauth_client.auth_code.authorize_url(
      redirect_uri: redirect_uri,
      scope: scope,
      state: state,
      prompt: "select_company"
    )
  end


  #
  # === コールバック（/callback）
  #
  def callback
    # CSRF Check
    if params[:state] != session[:freee_oauth_state]
      render plain: "Invalid state", status: 400
      return
    end

    # Token Exchange
    token = oauth_client.auth_code.get_token(
      params[:code],
      redirect_uri: redirect_uri
    )

    # 保存
    FreeeCredential.delete_all
    FreeeCredential.create!(
      access_token:  token.token,
      refresh_token: token.refresh_token,
      expires_at:    Time.at(token.expires_at)
    )
    redirect_to "/settings/plugin/redmine_freee_iv"
  end

  def reset
    FreeeCredential.delete_all
    flash[:notice] = "freee の認証を解除しました。"
    redirect_to "/settings/plugin/redmine_freee_iv"
  end

end
