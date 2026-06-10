# frozen_string_literal: true

class ConfigureDirectusAttendeesRelations < ActiveRecord::Migration[8.1]
  def up
    conn = ActiveRecord::Base.connection

    # ── attendees collection display ──────────────────────────────────────────
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, icon, display_template)
      VALUES ('attendees', false, 'person', '{{first_name}} {{last_name}}')
      ON CONFLICT (collection) DO UPDATE
        SET hidden           = false,
            icon             = EXCLUDED.icon,
            display_template = EXCLUDED.display_template
    SQL

    # ── tickets collection display (used when ticket_id renders in attendee) ──
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, icon, display_template)
      VALUES ('tickets', false, 'confirmation_number', '{{id}} — ${{price}}')
      ON CONFLICT (collection) DO UPDATE
        SET display_template = EXCLUDED.display_template
    SQL

    # ── orders collection display ─────────────────────────────────────────────
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, icon, display_template)
      VALUES ('orders', false, 'receipt_long', '{{order_reference}}')
      ON CONFLICT (collection) DO UPDATE
        SET display_template = EXCLUDED.display_template
    SQL

    # ── scalar fields on attendees ────────────────────────────────────────────
    scalar_fields = [
      { field: 'id',                 hidden: true,  interface: nil,               readonly: true,  special: nil,            options: nil,    width: 'full' },
      { field: 'first_name',         hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'last_name',          hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'email_address',      hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'phone_number',       hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'city',               hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'church_name',        hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'age',                hidden: false, interface: 'input',           readonly: false, special: nil,            options: nil,    width: 'half' },
      { field: 'dietary_preference', hidden: false, interface: 'select-dropdown', readonly: true,  special: nil,
        options: '{"choices":[{"text":"No preference","value":0},{"text":"Vegetarian","value":1},{"text":"Vegan","value":2}]}', width: 'half' },
      { field: 'payment_status',     hidden: false, interface: 'select-dropdown', readonly: true,  special: nil,
        options: '{"choices":[{"text":"Payment pending","value":0},{"text":"Paid","value":1},{"text":"Refunded","value":2},{"text":"Cancelled","value":3}]}', width: 'half' },
      { field: 'checked_in',         hidden: false, interface: 'boolean',         readonly: true,  special: nil,            options: nil,    width: 'half' },
      { field: 'checked_in_at',      hidden: false, interface: 'datetime',        readonly: true,  special: nil,            options: nil,    width: 'half' },
      { field: 'created_at',         hidden: false, interface: 'datetime',        readonly: true,  special: 'date-created', options: nil,    width: 'half' },
      { field: 'updated_at',         hidden: true,  interface: nil,               readonly: true,  special: 'date-updated', options: nil,    width: 'half' }
    ]

    scalar_fields.each do |f|
      execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = #{conn.quote(f[:field])}")
      iface = f[:interface] ? conn.quote(f[:interface]) : 'NULL'
      opts  = f[:options]   ? conn.quote(f[:options])   : 'NULL'
      spec  = f[:special]   ? conn.quote(f[:special])   : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, readonly, options, special, width)
        VALUES ('attendees', #{conn.quote(f[:field])}, #{iface}, #{f[:hidden]}, #{f[:readonly]}, #{opts}::json, #{spec}, #{conn.quote(f[:width])})
      SQL
    end

    # ── M2O fields on attendees ───────────────────────────────────────────────
    m2o_fields = [
      { field: 'event_id',   options: '{"template":"{{slug}}"}' },
      { field: 'ticket_id',  options: '{"template":"{{id}} — ${{price}}"}' },
      { field: 'order_id',   options: '{"template":"{{order_reference}}"}' }
    ]

    m2o_fields.each do |f|
      execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = #{conn.quote(f[:field])}")
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, readonly, options, special, width)
        VALUES ('attendees', #{conn.quote(f[:field])}, 'select-dropdown-m2o', false, true, #{conn.quote(f[:options])}::json, NULL, 'half')
      SQL
    end

    # ── Relations ─────────────────────────────────────────────────────────────
    [
      { many_field: 'event_id',  one_collection: 'events',  one_field: 'attendees' },
      { many_field: 'ticket_id', one_collection: 'tickets', one_field: nil },
      { many_field: 'order_id',  one_collection: 'orders',  one_field: 'attendees' }
    ].each do |r|
      execute("DELETE FROM directus_relations WHERE many_collection = 'attendees' AND many_field = #{conn.quote(r[:many_field])}")
      one_field = r[:one_field] ? conn.quote(r[:one_field]) : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
        VALUES ('attendees', #{conn.quote(r[:many_field])}, #{conn.quote(r[:one_collection])}, #{one_field}, NULL, 'nullify')
      SQL
    end
  end

  def down
    fields = %w[id first_name last_name email_address phone_number city church_name age
                dietary_preference payment_status checked_in checked_in_at created_at updated_at
                event_id ticket_id order_id]
    fields.each do |f|
      execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = '#{f}'")
    end
    execute("DELETE FROM directus_relations WHERE many_collection = 'attendees' AND many_field IN ('event_id','ticket_id','order_id')")
  end
end
