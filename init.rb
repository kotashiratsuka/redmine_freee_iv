Redmine::Plugin.register :redmine_freee do
  name        'Redmine Freee Plugin'
  author      'Kota Shiratsuka'
  version     '0.0.1'
  description 'freee Invoice Status Sync'
  url         'https://github.com/kotashiratsuka/redmine_freee'

  settings :default => {
    'client_id'     => '',
    'client_secret' => '',
    'user_id'       => ''
  },
  :partial => 'settings/freee_settings'
end
