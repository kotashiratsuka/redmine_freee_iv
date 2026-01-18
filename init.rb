require_relative "app/services/document_type_definitions"

default_settings = {
  "client_id" => "",
  "client_secret" => "",
  "user_id" => "",
  "apply_final_only" => "1",
  "ignored_status_ids" => [],
  "max_fetch_total" => "100"
}

DocumentTypeDefinitions.document_types.each do |_type, defn|
  default_settings[defn[:ticket_source_key]] = "subject"
  default_settings[defn[:sync_key]] = "0"

  defn[:statuses].each do |status|
    prefix = defn[:settings_prefix]
    default_settings["#{prefix}_#{status}_status"] = "0"
    default_settings["#{prefix}_#{status}_comment"] =
      defn[:default_templates].fetch(status)
  end
end

Redmine::Plugin.register :redmine_freee_iv do
  name        'Redmine freee Iv Plugin'
  author      'Kota Shiratsuka'
  description 'freee Invoice Status Sync'
  version     '0.7.0'
  url         'https://github.com/kotashiratsuka/redmine_freee_iv'
  author_url  'https://github.com/kotashiratsuka/'
  requires_redmine version_or_higher: '6.0.0'

  settings default: default_settings, partial: "settings/freee_settings"
end
