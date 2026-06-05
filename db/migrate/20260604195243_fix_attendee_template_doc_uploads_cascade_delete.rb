# frozen_string_literal: true

class FixAttendeeTemplateDocUploadsCascadeDelete < ActiveRecord::Migration[8.1]
  # Directus replaced the Rails cascade FK on attendee_id with its own NO ACTION FK.
  # This restores ON DELETE CASCADE so attendee deletion doesn't fail.
  def up
    execute("ALTER TABLE attendee_template_doc_uploads DROP CONSTRAINT attendee_template_doc_uploads_attendee_id_foreign")
    add_foreign_key :attendee_template_doc_uploads, :attendees,
                    column: :attendee_id,
                    on_delete: :cascade,
                    name: 'attendee_template_doc_uploads_attendee_id_fk'
  end

  def down
    remove_foreign_key :attendee_template_doc_uploads, name: 'attendee_template_doc_uploads_attendee_id_fk'
    execute("ALTER TABLE attendee_template_doc_uploads ADD CONSTRAINT attendee_template_doc_uploads_attendee_id_foreign FOREIGN KEY (attendee_id) REFERENCES attendees(id)")
  end
end
