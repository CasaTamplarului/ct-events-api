# frozen_string_literal: true

class FixAttendeeTemplateDocUploadsO2mAndFileRelation < ActiveRecord::Migration[8.1]
  def up
    # Remove duplicate attendees.template_doc_uploads O2M field (keep MIN id)
    execute(<<~SQL)
      DELETE FROM directus_fields
      WHERE collection = 'attendees' AND field = 'template_doc_uploads'
        AND id NOT IN (
          SELECT MIN(id) FROM directus_fields
          WHERE collection = 'attendees' AND field = 'template_doc_uploads'
        )
    SQL

    # Register the M2O relation from directus_files_id to directus_files so the
    # file interface can resolve the file and show the download button
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
      VALUES ('attendee_template_doc_uploads', 'directus_files_id', 'directus_files', NULL, NULL, 'nullify')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute("DELETE FROM directus_relations WHERE many_collection = 'attendee_template_doc_uploads' AND many_field = 'directus_files_id'")
  end
end
