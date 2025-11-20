class FreeeIvCredential < ActiveRecord::Base
  self.table_name = 'freee_iv_credentials' # 念のため明示

  validates :company_id,
            presence: true,
            uniqueness: true
end
