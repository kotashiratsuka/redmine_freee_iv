RedmineApp::Application.routes.draw do
  get  'redmine_freee_iv/auth/start',    to: 'redmine_freee_iv_auth#start'
  get  'redmine_freee_iv/auth/callback', to: 'redmine_freee_iv_auth#callback'
  delete 'redmine_freee_iv/auth/revoke', to: 'redmine_freee_iv_auth#revoke'
end
