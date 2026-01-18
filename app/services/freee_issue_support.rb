# frozen_string_literal: true

module FreeeIssueSupport
  module_function

  def freee_update_user
    uid = Setting.plugin_redmine_freee_iv["user_id"].presence || 1
    User.find(uid)
  end

  def apply_template(template, vars = {})
    return "" if template.blank?
    vars.reduce(template.to_s) do |msg, (key, val)|
      msg.gsub("{#{key}}", val.to_s)
    end
  end
end
