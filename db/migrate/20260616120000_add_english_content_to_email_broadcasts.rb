# frozen_string_literal: true

class AddEnglishContentToEmailBroadcasts < ActiveRecord::Migration[7.1]
  def change
    add_column :email_broadcasts, :subject_en, :text
    add_column :email_broadcasts, :body_en,    :text
  end
end
