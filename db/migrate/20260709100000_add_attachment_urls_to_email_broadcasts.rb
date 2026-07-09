# frozen_string_literal: true

class AddAttachmentUrlsToEmailBroadcasts < ActiveRecord::Migration[7.1]
  def change
    add_column :email_broadcasts, :attachment_urls, :jsonb, default: [], null: false
  end
end
