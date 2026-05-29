# frozen_string_literal: true

class ChangePasskeySignCountToBigint < ActiveRecord::Migration[8.1]
  def up
    change_column :passkeys, :sign_count, :bigint, null: false, default: 0
  end

  def down
    change_column :passkeys, :sign_count, :integer, null: false, default: 0
  end
end
