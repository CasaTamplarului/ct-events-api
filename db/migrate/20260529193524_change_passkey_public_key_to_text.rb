# frozen_string_literal: true

class ChangePasskeyPublicKeyToText < ActiveRecord::Migration[8.1]
  def up
    change_column :passkeys, :public_key, :text
  end

  def down
    change_column :passkeys, :public_key, :string
  end
end
