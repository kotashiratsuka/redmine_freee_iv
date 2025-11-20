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
    redirect_to oauth_client.auth_code.authorize_url(
      redirect_uri: "#{request.base_url}/redmine_freee_iv/auth/callback",
      prompt: "select_company"
    )
  end

  #
  # === コールバック（/callback）
  #
  def callback
    redirect_uri = "#{request.base_url}/redmine_freee_iv/auth/callback"

    # 認可コードからアクセストークンを取得
    token = oauth_client.auth_code.get_token(
      params[:code],
      redirect_uri: redirect_uri
    )

    # ★ freee の仕様上、ここにユーザーが選んだ事業所IDが入る
    company_id = token.params["company_id"] || token.params[:company_id]
    Rails.logger.info("[freee_iv] token.params = #{token.params.inspect}")

    raise "no company_id in token" if company_id.blank?
    company_id = company_id.to_s

    cred = FreeeIvCredential.find_or_initialize_by(company_id: company_id)
    cred.update!(
      access_token:  token.token,
      refresh_token: token.refresh_token,
      expires_at:    Time.at(token.expires_at)
    )

    redirect_to "/settings/plugin/redmine_freee_iv"
  end

  def revoke
    company_id = params[:company_id].to_s
    cred = FreeeIvCredential.find_by(company_id: company_id)
    cred&.destroy

    flash[:notice] = "事業所（ID: #{company_id}）の認証を解除しました"
    redirect_to "/settings/plugin/redmine_freee_iv"
  end

end
