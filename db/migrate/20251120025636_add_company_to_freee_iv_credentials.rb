class AddCompanyToFreeeIvCredentials < ActiveRecord::Migration[7.2]
  def change
    add_column :freee_iv_credentials, :company_id, :string
    add_index :freee_iv_credentials, :company_id
  end
end
