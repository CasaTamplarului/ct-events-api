# frozen_string_literal: true

class MakeAttendeeTemplateDocFileDownloadable < ActiveRecord::Migration[8.1]
  # readonly:true on a file interface hides the download button entirely.
  # Staff can't modify uploads anyway (O2M has enableCreate/Select/Delete:false).
  def up
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = false
      WHERE collection = 'attendee_template_doc_uploads' AND field = 'directus_files_id'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = true
      WHERE collection = 'attendee_template_doc_uploads' AND field = 'directus_files_id'
    SQL
  end
end
