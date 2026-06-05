# frozen_string_literal: true

class FixAttendeeTemplateDocUploadsDirectusFields < ActiveRecord::Migration[8.1]
  # directus_fields has no unique constraint on (collection, field), so the
  # configure migration inserted duplicates. Delete the higher-id dupes and
  # add special:'file' to directus_files_id so the download button appears.
  def up
    execute(<<~SQL)
      DELETE FROM directus_fields
      WHERE collection = 'attendee_template_doc_uploads'
        AND id NOT IN (
          SELECT MIN(id) FROM directus_fields
          WHERE collection = 'attendee_template_doc_uploads'
          GROUP BY field
        )
    SQL

    execute(<<~SQL)
      UPDATE directus_fields
      SET special = 'file'
      WHERE collection = 'attendee_template_doc_uploads' AND field = 'directus_files_id'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET special = NULL
      WHERE collection = 'attendee_template_doc_uploads' AND field = 'directus_files_id'
    SQL
  end
end
