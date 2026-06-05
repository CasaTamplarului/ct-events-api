# frozen_string_literal: true

class AllowClickingAttendeeTemplateDocUploadsRows < ActiveRecord::Migration[8.1]
  # readonly:true on an O2M field blocks row clicking entirely — staff can't
  # open the item detail to see the download button. readonly:false keeps rows
  # clickable; enableCreate/Select/Delete:false already prevent modifications.
  def up
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = false
      WHERE collection = 'attendees' AND field = 'template_doc_uploads'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = true
      WHERE collection = 'attendees' AND field = 'template_doc_uploads'
    SQL
  end
end
