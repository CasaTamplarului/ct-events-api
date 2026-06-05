class RemovePaymentReceiptEmailsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :payment_receipt_emails, :boolean, null: false, default: false
  end
end
