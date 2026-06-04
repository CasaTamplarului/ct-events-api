# frozen_string_literal: true

class CreateAttendeeTemplateDocUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :attendee_template_doc_uploads do |t|
      t.references :attendee, null: false, foreign_key: { on_delete: :cascade }
      t.references :event_template_doc, null: false, foreign_key: { on_delete: :cascade }
      t.uuid :directus_files_id, null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :attendee_template_doc_uploads,
              %i[attendee_id event_template_doc_id],
              unique: true,
              name: 'idx_attendee_template_doc_uploads_unique'

    add_foreign_key :attendee_template_doc_uploads, :directus_files,
                    column: :directus_files_id,
                    name: 'attendee_template_doc_uploads_directus_files_id_fk'
  end
end
