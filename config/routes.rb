RedmineApp::Application.routes.draw do
  get 'redmine_freee/auth/start',    to: 'redmine_freee_auth#start'
  get 'redmine_freee/auth/callback', to: 'redmine_freee_auth#callback'
end
