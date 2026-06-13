# frozen_string_literal: true

class ConfigureDirectusAttendeeTemplateDocUploads < ActiveRecord::Migration[8.1]
  # Configures attendee_template_doc_uploads in the Directus CMS so staff can
  # see and download the PDFs attendees uploaded during checkout.
  # - Hides system fields (id, attendee_id, timestamps)
  # - Shows event_template_doc_id (which form) and directus_files_id (the file) as read-only
  # - Adds a read-only template_doc_uploads O2M section to the attendees form
  # - Wires the relation one_field so the O2M section populates

  def up
    conn = ActiveRecord::Base.connection

    # Collection metadata
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, icon, display_template)
      VALUES ('attendee_template_doc_uploads', true, 'upload_file', '{{event_template_doc_id.translations.label}}')
      ON CONFLICT (collection) DO UPDATE
        SET hidden           = true,
            icon             = EXCLUDED.icon,
            display_template = EXCLUDED.display_template
    SQL

    # Field interfaces
    fields = [
      { field: 'id',                    hidden: true,  interface: nil,                    readonly: false, options: nil },
      { field: 'attendee_id',           hidden: true,  interface: nil,                    readonly: false, options: nil },
      { field: 'created_at',            hidden: true,  interface: nil,                    readonly: false, options: nil },
      { field: 'updated_at',            hidden: true,  interface: nil,                    readonly: false, options: nil },
      { field: 'event_template_doc_id', hidden: false, interface: 'select-dropdown-m2o', readonly: true, options: '{"template":"{{translations.label}}"}' },
      { field: 'directus_files_id',     hidden: false, interface: 'file', readonly: true, options: nil }
    ]

    fields.each do |f|
      iface = f[:interface] ? conn.quote(f[:interface]) : 'NULL'
      opts  = f[:options]   ? conn.quote(f[:options])   : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, readonly, options, width)
        VALUES ('attendee_template_doc_uploads', #{conn.quote(f[:field])}, #{iface}, #{f[:hidden]}, #{f[:readonly]}, #{opts}::json, 'full')
        ON CONFLICT DO NOTHING
      SQL
      execute(<<~SQL)
        UPDATE directus_fields
        SET interface = #{iface}, hidden = #{f[:hidden]}, readonly = #{f[:readonly]}, options = #{opts}::json
        WHERE collection = 'attendee_template_doc_uploads' AND field = #{conn.quote(f[:field])}
      SQL
    end

    # O2M virtual field on attendees (read-only — staff can see but not modify)
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('attendees', 'template_doc_uploads', 'list-o2m', false, true, 'o2m',
              '{"enableCreate":false,"enableSelect":false,"enableDelete":false}'::json, 'full')
      ON CONFLICT DO NOTHING
    SQL

    # Wire the relation: attendee_template_doc_uploads.attendee_id → attendees (one_field=template_doc_uploads)
    execute(<<~SQL)
      UPDATE directus_relations
      SET one_field = 'template_doc_uploads', one_deselect_action = 'delete'
      WHERE many_collection = 'attendee_template_doc_uploads' AND many_field = 'attendee_id'
    SQL
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'template_doc_uploads'")
    execute("DELETE FROM directus_fields WHERE collection = 'attendee_template_doc_uploads'")
    execute("UPDATE directus_relations SET one_field = NULL, one_deselect_action = NULL WHERE many_collection = 'attendee_template_doc_uploads' AND many_field = 'attendee_id'")
    execute("UPDATE directus_collections SET hidden = false, icon = NULL, display_template = NULL WHERE collection = 'attendee_template_doc_uploads'")
  end
end
