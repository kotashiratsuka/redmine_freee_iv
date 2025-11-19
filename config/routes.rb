RedmineApp::Application.routes.draw do
  get  'redmine_freee_iv/auth/start',    to: 'redmine_freee_iv_auth#start'
  get  'redmine_freee_iv/auth/callback', to: 'redmine_freee_iv_auth#callback'
  post 'redmine_freee_iv/auth/reset',    to: 'redmine_freee_iv_auth#reset'
end
