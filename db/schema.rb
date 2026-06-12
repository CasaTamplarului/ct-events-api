# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_12_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "unaccent"

  create_table "attendee_boolean_field_responses", force: :cascade do |t|
    t.bigint "attendee_id", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "event_boolean_field_id", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.boolean "value", null: false
    t.index ["attendee_id", "event_boolean_field_id"], name: "idx_attendee_boolean_field_responses_unique", unique: true
    t.index ["attendee_id"], name: "index_attendee_boolean_field_responses_on_attendee_id"
    t.index ["event_boolean_field_id"], name: "idx_on_event_boolean_field_id_2bf7aed83e"
  end

  create_table "attendee_template_doc_uploads", force: :cascade do |t|
    t.bigint "attendee_id", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "directus_files_id", null: false
    t.bigint "event_template_doc_id", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["attendee_id", "event_template_doc_id"], name: "idx_attendee_template_doc_uploads_unique", unique: true
    t.index ["attendee_id"], name: "index_attendee_template_doc_uploads_on_attendee_id"
    t.index ["event_template_doc_id"], name: "index_attendee_template_doc_uploads_on_event_template_doc_id"
  end

  create_table "attendees", force: :cascade do |t|
    t.integer "age"
    t.jsonb "allergies", default: [], null: false
    t.boolean "checked_in", default: false, null: false
    t.datetime "checked_in_at"
    t.bigint "checked_in_by_user_id"
    t.string "church_name"
    t.string "city"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.integer "dietary_preference", default: 0
    t.string "email_address"
    t.bigint "event_id", null: false
    t.string "first_name"
    t.string "last_name"
    t.bigint "order_id"
    t.string "participant_key"
    t.integer "payment_status", default: 0, null: false
    t.string "phone_number"
    t.bigint "ticket_id"
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.bigint "user_id"
    t.index ["checked_in_by_user_id"], name: "index_attendees_on_checked_in_by_user_id"
    t.index ["event_id"], name: "index_attendees_on_event_id"
    t.index ["order_id"], name: "index_attendees_on_order_id"
    t.index ["participant_key"], name: "index_attendees_on_participant_key"
    t.index ["ticket_id"], name: "index_attendees_on_ticket_id"
    t.index ["user_id"], name: "index_attendees_on_user_id"
  end

  create_table "bracelets", force: :cascade do |t|
    t.bigint "attendee_id"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["attendee_id"], name: "index_bracelets_on_attendee_id"
    t.index ["code"], name: "index_bracelets_on_code", unique: true
    t.index ["event_id"], name: "index_bracelets_on_event_id"
  end

  create_table "directus_access", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "policy", null: false
    t.uuid "role"
    t.integer "sort"
    t.uuid "user"
  end

  create_table "directus_activity", id: :serial, force: :cascade do |t|
    t.string "action", limit: 45, null: false
    t.string "collection", limit: 64, null: false
    t.string "ip", limit: 50
    t.string "item", limit: 255, null: false
    t.string "origin", limit: 255
    t.timestamptz "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "user"
    t.text "user_agent"
  end

  create_table "directus_collections", primary_key: "collection", id: { type: :string, limit: 64 }, force: :cascade do |t|
    t.string "accountability", limit: 255, default: "all"
    t.boolean "archive_app_filter", default: true, null: false
    t.string "archive_field", limit: 64
    t.string "archive_value", limit: 255
    t.string "collapse", limit: 255, default: "open", null: false
    t.string "color", limit: 255
    t.string "display_template", limit: 255
    t.string "group", limit: 64
    t.boolean "hidden", default: false, null: false
    t.string "icon", limit: 64
    t.json "item_duplication_fields"
    t.text "note"
    t.string "preview_url", limit: 255
    t.boolean "singleton", default: false, null: false
    t.integer "sort"
    t.string "sort_field", limit: 64
    t.json "translations"
    t.string "unarchive_value", limit: 255
    t.boolean "versioning", default: false, null: false
  end

  create_table "directus_comments", id: :uuid, default: nil, force: :cascade do |t|
    t.string "collection", limit: 64, null: false
    t.text "comment", null: false
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.timestamptz "date_updated", default: -> { "CURRENT_TIMESTAMP" }
    t.string "item", limit: 255, null: false
    t.uuid "user_created"
    t.uuid "user_updated"
  end

  create_table "directus_dashboards", id: :uuid, default: nil, force: :cascade do |t|
    t.string "color", limit: 255
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.string "icon", limit: 64, default: "dashboard", null: false
    t.string "name", limit: 255, null: false
    t.text "note"
    t.uuid "user_created"
  end

  create_table "directus_extensions", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "bundle"
    t.boolean "enabled", default: true, null: false
    t.string "folder", limit: 255, null: false
    t.string "source", limit: 255, null: false
  end

  create_table "directus_fields", id: :serial, force: :cascade do |t|
    t.string "collection", limit: 64, null: false
    t.json "conditions"
    t.string "display", limit: 64
    t.json "display_options"
    t.string "field", limit: 64, null: false
    t.string "group", limit: 64
    t.boolean "hidden", default: false, null: false
    t.string "interface", limit: 64
    t.text "note"
    t.json "options"
    t.boolean "readonly", default: false, null: false
    t.boolean "required", default: false
    t.integer "sort"
    t.string "special", limit: 64
    t.json "translations"
    t.json "validation"
    t.text "validation_message"
    t.string "width", limit: 30, default: "full"
  end

  create_table "directus_files", id: :uuid, default: nil, force: :cascade do |t|
    t.string "charset", limit: 50
    t.timestamptz "created_on", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.text "description"
    t.integer "duration"
    t.string "embed", limit: 200
    t.string "filename_disk", limit: 255
    t.string "filename_download", limit: 255, null: false
    t.bigint "filesize"
    t.integer "focal_point_x"
    t.integer "focal_point_y"
    t.uuid "folder"
    t.integer "height"
    t.text "location"
    t.json "metadata"
    t.uuid "modified_by"
    t.timestamptz "modified_on", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "storage", limit: 255, null: false
    t.text "tags"
    t.string "title", limit: 255
    t.json "tus_data"
    t.string "tus_id", limit: 64
    t.string "type", limit: 255
    t.uuid "uploaded_by"
    t.timestamptz "uploaded_on"
    t.integer "width"
  end

  create_table "directus_flows", id: :uuid, default: nil, force: :cascade do |t|
    t.string "accountability", limit: 255, default: "all"
    t.string "color", limit: 255
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.text "description"
    t.string "icon", limit: 64
    t.string "name", limit: 255, null: false
    t.uuid "operation"
    t.json "options"
    t.string "status", limit: 255, default: "active", null: false
    t.string "trigger", limit: 255
    t.uuid "user_created"

    t.unique_constraint ["operation"], name: "directus_flows_operation_unique"
  end

  create_table "directus_folders", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.uuid "parent"
  end

  create_table "directus_migrations", primary_key: "version", id: { type: :string, limit: 255 }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.timestamptz "timestamp", default: -> { "CURRENT_TIMESTAMP" }
  end

  create_table "directus_notifications", id: :serial, force: :cascade do |t|
    t.string "collection", limit: 64
    t.string "item", limit: 255
    t.text "message"
    t.uuid "recipient", null: false
    t.uuid "sender"
    t.string "status", limit: 255, default: "inbox"
    t.string "subject", limit: 255, null: false
    t.timestamptz "timestamp", default: -> { "CURRENT_TIMESTAMP" }
  end

  create_table "directus_operations", id: :uuid, default: nil, force: :cascade do |t|
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.uuid "flow", null: false
    t.string "key", limit: 255, null: false
    t.string "name", limit: 255
    t.json "options"
    t.integer "position_x", null: false
    t.integer "position_y", null: false
    t.uuid "reject"
    t.uuid "resolve"
    t.string "type", limit: 255, null: false
    t.uuid "user_created"

    t.unique_constraint ["reject"], name: "directus_operations_reject_unique"
    t.unique_constraint ["resolve"], name: "directus_operations_resolve_unique"
  end

  create_table "directus_panels", id: :uuid, default: nil, force: :cascade do |t|
    t.string "color", limit: 10
    t.uuid "dashboard", null: false
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.integer "height", null: false
    t.string "icon", limit: 64
    t.string "name", limit: 255
    t.text "note"
    t.json "options"
    t.integer "position_x", null: false
    t.integer "position_y", null: false
    t.boolean "show_header", default: false, null: false
    t.string "type", limit: 255, null: false
    t.uuid "user_created"
    t.integer "width", null: false
  end

  create_table "directus_permissions", id: :serial, force: :cascade do |t|
    t.string "action", limit: 10, null: false
    t.string "collection", limit: 64, null: false
    t.text "fields"
    t.json "permissions"
    t.uuid "policy", null: false
    t.json "presets"
    t.json "validation"
  end

  create_table "directus_policies", id: :uuid, default: nil, force: :cascade do |t|
    t.boolean "admin_access", default: false, null: false
    t.boolean "app_access", default: false, null: false
    t.text "description"
    t.boolean "enforce_tfa", default: false, null: false
    t.string "icon", limit: 64, default: "badge", null: false
    t.text "ip_access"
    t.string "name", limit: 100, null: false
  end

  create_table "directus_presets", id: :serial, force: :cascade do |t|
    t.string "bookmark", limit: 255
    t.string "collection", limit: 64
    t.string "color", limit: 255
    t.json "filter"
    t.string "icon", limit: 64, default: "bookmark"
    t.string "layout", limit: 100, default: "tabular"
    t.json "layout_options"
    t.json "layout_query"
    t.integer "refresh_interval"
    t.uuid "role"
    t.string "search", limit: 100
    t.uuid "user"
  end

  create_table "directus_relations", id: :serial, force: :cascade do |t|
    t.string "junction_field", limit: 64
    t.string "many_collection", limit: 64, null: false
    t.string "many_field", limit: 64, null: false
    t.text "one_allowed_collections"
    t.string "one_collection", limit: 64
    t.string "one_collection_field", limit: 64
    t.string "one_deselect_action", limit: 255, default: "nullify", null: false
    t.string "one_field", limit: 64
    t.string "sort_field", limit: 64
  end

  create_table "directus_revisions", id: :serial, force: :cascade do |t|
    t.integer "activity", null: false
    t.string "collection", limit: 64, null: false
    t.json "data"
    t.json "delta"
    t.string "item", limit: 255, null: false
    t.integer "parent"
    t.uuid "version"
  end

  create_table "directus_roles", id: :uuid, default: nil, force: :cascade do |t|
    t.text "description"
    t.string "icon", limit: 64, default: "supervised_user_circle", null: false
    t.string "name", limit: 100, null: false
    t.uuid "parent"
  end

  create_table "directus_sessions", primary_key: "token", id: { type: :string, limit: 64 }, force: :cascade do |t|
    t.timestamptz "expires", null: false
    t.string "ip", limit: 255
    t.string "next_token", limit: 64
    t.string "origin", limit: 255
    t.uuid "share"
    t.uuid "user"
    t.text "user_agent"
  end

  create_table "directus_settings", id: :serial, force: :cascade do |t|
    t.integer "auth_login_attempts", default: 25
    t.string "auth_password_policy", limit: 100
    t.json "basemaps"
    t.json "custom_aspect_ratios"
    t.text "custom_css"
    t.string "default_appearance", limit: 255, default: "auto", null: false
    t.string "default_language", limit: 255, default: "en-US", null: false
    t.string "default_theme_dark", limit: 255
    t.string "default_theme_light", limit: 255
    t.string "mapbox_key", limit: 255
    t.json "module_bar"
    t.string "project_color", limit: 255, default: "#6644FF", null: false
    t.string "project_descriptor", limit: 100
    t.uuid "project_logo"
    t.string "project_name", limit: 100, default: "Directus", null: false
    t.string "project_url", limit: 255
    t.uuid "public_background"
    t.uuid "public_favicon"
    t.uuid "public_foreground"
    t.text "public_note"
    t.boolean "public_registration", default: false, null: false
    t.json "public_registration_email_filter"
    t.uuid "public_registration_role"
    t.boolean "public_registration_verify_email", default: true, null: false
    t.string "report_bug_url", limit: 255
    t.string "report_error_url", limit: 255
    t.string "report_feature_url", limit: 255
    t.json "storage_asset_presets"
    t.string "storage_asset_transform", limit: 7, default: "all"
    t.uuid "storage_default_folder"
    t.json "theme_dark_overrides"
    t.json "theme_light_overrides"
  end

  create_table "directus_shares", id: :uuid, default: nil, force: :cascade do |t|
    t.string "collection", limit: 64, null: false
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.timestamptz "date_end"
    t.timestamptz "date_start"
    t.string "item", limit: 255, null: false
    t.integer "max_uses"
    t.string "name", limit: 255
    t.string "password", limit: 255
    t.uuid "role"
    t.integer "times_used", default: 0
    t.uuid "user_created"
  end

  create_table "directus_translations", id: :uuid, default: nil, force: :cascade do |t|
    t.string "key", limit: 255, null: false
    t.string "language", limit: 255, null: false
    t.text "value", null: false
  end

  create_table "directus_users", id: :uuid, default: nil, force: :cascade do |t|
    t.string "appearance", limit: 255
    t.json "auth_data"
    t.uuid "avatar"
    t.text "description"
    t.string "email", limit: 128
    t.boolean "email_notifications", default: true
    t.string "external_identifier", limit: 255
    t.string "first_name", limit: 50
    t.string "language", limit: 255
    t.timestamptz "last_access"
    t.string "last_name", limit: 50
    t.string "last_page", limit: 255
    t.string "location", limit: 255
    t.string "password", limit: 255
    t.string "provider", limit: 128, default: "default", null: false
    t.uuid "role"
    t.string "status", limit: 16, default: "active", null: false
    t.json "tags"
    t.string "tfa_secret", limit: 255
    t.string "theme_dark", limit: 255
    t.json "theme_dark_overrides"
    t.string "theme_light", limit: 255
    t.json "theme_light_overrides"
    t.string "title", limit: 50
    t.string "token", limit: 255

    t.unique_constraint ["email"], name: "directus_users_email_unique"
    t.unique_constraint ["external_identifier"], name: "directus_users_external_identifier_unique"
    t.unique_constraint ["token"], name: "directus_users_token_unique"
  end

  create_table "directus_versions", id: :uuid, default: nil, force: :cascade do |t|
    t.string "collection", limit: 64, null: false
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.timestamptz "date_updated", default: -> { "CURRENT_TIMESTAMP" }
    t.json "delta"
    t.string "hash", limit: 255
    t.string "item", limit: 255, null: false
    t.string "key", limit: 64, null: false
    t.string "name", limit: 255
    t.uuid "user_created"
    t.uuid "user_updated"
  end

  create_table "directus_webhooks", id: :serial, force: :cascade do |t|
    t.string "actions", limit: 100, null: false
    t.string "collections", limit: 255, null: false
    t.boolean "data", default: true, null: false
    t.json "headers"
    t.string "method", limit: 10, default: "POST", null: false
    t.uuid "migrated_flow"
    t.string "name", limit: 255, null: false
    t.string "status", limit: 10, default: "active", null: false
    t.string "url", limit: 255, null: false
    t.boolean "was_active_before_deprecation", default: false, null: false
  end

  create_table "event_attendee_fields", force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.bigint "event_id", null: false
    t.string "field_name", null: false
    t.boolean "required", default: true, null: false
    t.integer "sort", default: 0, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["event_id", "field_name"], name: "index_event_attendee_fields_on_event_id_and_field_name"
    t.index ["event_id", "sort"], name: "index_event_attendee_fields_on_event_id_and_sort"
    t.index ["event_id"], name: "index_event_attendee_fields_on_event_id"
  end

  create_table "event_boolean_field_translations", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "event_boolean_field_id", null: false
    t.string "false_label", null: false
    t.string "label", null: false
    t.string "languages_code", null: false
    t.string "true_label", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["event_boolean_field_id", "languages_code"], name: "idx_event_boolean_field_translations_unique", unique: true
    t.index ["event_boolean_field_id"], name: "idx_on_event_boolean_field_id_f232b231a8"
  end

  create_table "event_boolean_fields", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "display_as", null: false
    t.bigint "event_id", null: false
    t.boolean "required", default: false, null: false
    t.integer "sort", default: 0, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["event_id", "sort"], name: "index_event_boolean_fields_on_event_id_and_sort"
    t.index ["event_id"], name: "index_event_boolean_fields_on_event_id"
  end

  create_table "event_gallery", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "directus_files_id", null: false
    t.bigint "event_id", null: false
    t.integer "sort", default: 0, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["event_id", "directus_files_id"], name: "index_event_gallery_on_event_id_and_directus_files_id", unique: true
    t.index ["event_id", "sort"], name: "index_event_gallery_on_event_id_and_sort"
    t.index ["event_id"], name: "index_event_gallery_on_event_id"
  end

  create_table "event_speakers", force: :cascade do |t|
    t.string "action_url"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.uuid "image"
    t.string "name", null: false
    t.integer "sort", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "sort"], name: "index_event_speakers_on_event_id_and_sort"
    t.index ["event_id"], name: "index_event_speakers_on_event_id"
  end

  create_table "event_speakers_translations", force: :cascade do |t|
    t.string "action_label", limit: 255
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "event_speaker_id"
    t.string "languages_code", null: false
    t.datetime "updated_at", null: false
  end

  create_table "event_template_doc_translations", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "event_template_doc_id", null: false
    t.string "label", null: false
    t.string "languages_code", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["event_template_doc_id", "languages_code"], name: "index_event_template_doc_translations_unique", unique: true
    t.index ["event_template_doc_id"], name: "index_event_template_doc_translations_on_event_template_doc_id"
  end

  create_table "event_template_docs", force: :cascade do |t|
    t.integer "age_from"
    t.integer "age_to"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "directus_files_id", null: false
    t.bigint "event_id", null: false
    t.boolean "required", default: false, null: false
    t.integer "sort", default: 0, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.boolean "upload_enabled", default: true, null: false
    t.index ["event_id", "sort"], name: "index_event_template_docs_on_event_id_and_sort"
    t.index ["event_id"], name: "index_event_template_docs_on_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.uuid "access_token", default: -> { "gen_random_uuid()" }, null: false
    t.string "address"
    t.boolean "allow_over_max_age", default: false, null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.string "embed_url"
    t.datetime "end_date", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.boolean "hero", default: false, null: false
    t.uuid "hero_image"
    t.uuid "hero_portrait"
    t.boolean "is_private", default: false, null: false
    t.string "location_name"
    t.integer "max_age"
    t.integer "max_number_of_people"
    t.integer "min_age"
    t.boolean "override_max_people", default: false
    t.string "slug", limit: 255
    t.datetime "start_date", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "status", default: 0
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["slug"], name: "index_events_on_slug", unique: true
  end

  create_table "events_translations", force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.text "description"
    t.integer "event_id"
    t.string "languages_code"
    t.string "name", limit: 255
    t.string "tag_line", null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
  end

  create_table "languages", primary_key: "code", id: :string, force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.string "name", null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
  end

  create_table "meal_stamps", force: :cascade do |t|
    t.bigint "attendee_id", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "stamped_by_user_id", null: false
    t.bigint "ticket_meal_slot_id", null: false
    t.index ["attendee_id", "ticket_meal_slot_id"], name: "index_meal_stamps_on_attendee_id_and_ticket_meal_slot_id"
    t.index ["attendee_id"], name: "index_meal_stamps_on_attendee_id"
    t.index ["ticket_meal_slot_id"], name: "index_meal_stamps_on_ticket_meal_slot_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "booking_token"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.string "order_reference"
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.bigint "user_id"
    t.index ["booking_token"], name: "index_orders_on_booking_token", unique: true
    t.index ["order_reference"], name: "index_orders_on_order_reference", unique: true
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "passkeys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "nickname"
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "push_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.string "directus_file_id"
    t.bigint "event_id"
    t.string "link"
    t.integer "sent_to", default: 0, null: false
    t.jsonb "translations", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_push_notifications_on_created_by_id"
    t.index ["event_id"], name: "index_push_notifications_on_event_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_name"
    t.string "platform", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_push_subscriptions_on_token", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "updated_at", null: false
    t.index ["concurrency_key"], name: "index_solid_queue_blocked_executions_on_concurrency_key"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id"], name: "index_solid_queue_claimed_executions_on_process_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_on_scheduled_at"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.datetime "updated_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.datetime "updated_at", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id"
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "last_run_at"
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "ticket_meal_slots", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "meal_type", null: false
    t.date "occurs_on", null: false
    t.integer "sort"
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["ticket_id", "occurs_on", "meal_type"], name: "idx_on_ticket_id_occurs_on_meal_type_c7e73ddfbf"
    t.index ["ticket_id"], name: "index_ticket_meal_slots_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.bigint "event_id", null: false
    t.boolean "food_included", default: false, null: false
    t.boolean "for_leaders", default: false, null: false
    t.decimal "price"
    t.integer "sort"
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.date "valid_from"
    t.date "valid_to"
    t.index ["event_id", "sort"], name: "index_tickets_on_event_id_and_sort"
    t.index ["event_id"], name: "index_tickets_on_event_id"
  end

  create_table "tickets_translations", force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.text "description"
    t.string "languages_code"
    t.string "name", null: false
    t.integer "tickets_id"
    t.datetime "updated_at", default: -> { "now()" }, null: false
  end

  create_table "user_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_user_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_user_identities_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.string "church_name"
    t.string "city"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "deleted_at"
    t.string "email"
    t.boolean "event_reminder_emails", default: false, null: false
    t.boolean "event_reminder_push", default: true, null: false
    t.boolean "event_update_emails", default: false, null: false
    t.boolean "event_update_push", default: true, null: false
    t.string "first_name", null: false
    t.string "language"
    t.string "last_name"
    t.boolean "marketing_emails", default: false, null: false
    t.boolean "marketing_push", default: true, null: false
    t.string "password_digest"
    t.string "password_reset_token"
    t.datetime "password_reset_token_expires_at"
    t.boolean "payment_reminder_emails", default: false, null: false
    t.boolean "payment_reminder_push", default: true, null: false
    t.string "phone_number"
    t.string "role", default: "attendee", null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["password_reset_token"], name: "index_users_on_password_reset_token", unique: true
  end

  add_foreign_key "attendee_boolean_field_responses", "attendees", on_delete: :cascade
  add_foreign_key "attendee_boolean_field_responses", "event_boolean_fields", on_delete: :cascade
  add_foreign_key "attendee_template_doc_uploads", "attendees", name: "attendee_template_doc_uploads_attendee_id_fk", on_delete: :cascade
  add_foreign_key "attendee_template_doc_uploads", "directus_files", column: "directus_files_id", name: "attendee_template_doc_uploads_directus_files_id_fk"
  add_foreign_key "attendee_template_doc_uploads", "event_template_docs", on_delete: :cascade
  add_foreign_key "attendees", "events", on_delete: :cascade
  add_foreign_key "attendees", "orders"
  add_foreign_key "attendees", "tickets"
  add_foreign_key "attendees", "users"
  add_foreign_key "attendees", "users", column: "checked_in_by_user_id"
  add_foreign_key "bracelets", "attendees", on_delete: :nullify
  add_foreign_key "bracelets", "events", on_delete: :cascade
  add_foreign_key "directus_access", "directus_policies", column: "policy", name: "directus_access_policy_foreign", on_delete: :cascade
  add_foreign_key "directus_access", "directus_roles", column: "role", name: "directus_access_role_foreign", on_delete: :cascade
  add_foreign_key "directus_access", "directus_users", column: "user", name: "directus_access_user_foreign", on_delete: :cascade
  add_foreign_key "directus_collections", "directus_collections", column: "group", primary_key: "collection", name: "directus_collections_group_foreign"
  add_foreign_key "directus_comments", "directus_users", column: "user_created", name: "directus_comments_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_comments", "directus_users", column: "user_updated", name: "directus_comments_user_updated_foreign"
  add_foreign_key "directus_dashboards", "directus_users", column: "user_created", name: "directus_dashboards_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_files", "directus_folders", column: "folder", name: "directus_files_folder_foreign", on_delete: :nullify
  add_foreign_key "directus_files", "directus_users", column: "modified_by", name: "directus_files_modified_by_foreign"
  add_foreign_key "directus_files", "directus_users", column: "uploaded_by", name: "directus_files_uploaded_by_foreign"
  add_foreign_key "directus_flows", "directus_users", column: "user_created", name: "directus_flows_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_folders", "directus_folders", column: "parent", name: "directus_folders_parent_foreign"
  add_foreign_key "directus_notifications", "directus_users", column: "recipient", name: "directus_notifications_recipient_foreign", on_delete: :cascade
  add_foreign_key "directus_notifications", "directus_users", column: "sender", name: "directus_notifications_sender_foreign"
  add_foreign_key "directus_operations", "directus_flows", column: "flow", name: "directus_operations_flow_foreign", on_delete: :cascade
  add_foreign_key "directus_operations", "directus_operations", column: "reject", name: "directus_operations_reject_foreign"
  add_foreign_key "directus_operations", "directus_operations", column: "resolve", name: "directus_operations_resolve_foreign"
  add_foreign_key "directus_operations", "directus_users", column: "user_created", name: "directus_operations_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_panels", "directus_dashboards", column: "dashboard", name: "directus_panels_dashboard_foreign", on_delete: :cascade
  add_foreign_key "directus_panels", "directus_users", column: "user_created", name: "directus_panels_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_permissions", "directus_policies", column: "policy", name: "directus_permissions_policy_foreign", on_delete: :cascade
  add_foreign_key "directus_presets", "directus_roles", column: "role", name: "directus_presets_role_foreign", on_delete: :cascade
  add_foreign_key "directus_presets", "directus_users", column: "user", name: "directus_presets_user_foreign", on_delete: :cascade
  add_foreign_key "directus_revisions", "directus_activity", column: "activity", name: "directus_revisions_activity_foreign", on_delete: :cascade
  add_foreign_key "directus_revisions", "directus_revisions", column: "parent", name: "directus_revisions_parent_foreign"
  add_foreign_key "directus_revisions", "directus_versions", column: "version", name: "directus_revisions_version_foreign", on_delete: :cascade
  add_foreign_key "directus_roles", "directus_roles", column: "parent", name: "directus_roles_parent_foreign"
  add_foreign_key "directus_sessions", "directus_shares", column: "share", name: "directus_sessions_share_foreign", on_delete: :cascade
  add_foreign_key "directus_sessions", "directus_users", column: "user", name: "directus_sessions_user_foreign", on_delete: :cascade
  add_foreign_key "directus_settings", "directus_files", column: "project_logo", name: "directus_settings_project_logo_foreign"
  add_foreign_key "directus_settings", "directus_files", column: "public_background", name: "directus_settings_public_background_foreign"
  add_foreign_key "directus_settings", "directus_files", column: "public_favicon", name: "directus_settings_public_favicon_foreign"
  add_foreign_key "directus_settings", "directus_files", column: "public_foreground", name: "directus_settings_public_foreground_foreign"
  add_foreign_key "directus_settings", "directus_folders", column: "storage_default_folder", name: "directus_settings_storage_default_folder_foreign", on_delete: :nullify
  add_foreign_key "directus_settings", "directus_roles", column: "public_registration_role", name: "directus_settings_public_registration_role_foreign", on_delete: :nullify
  add_foreign_key "directus_shares", "directus_collections", column: "collection", primary_key: "collection", name: "directus_shares_collection_foreign", on_delete: :cascade
  add_foreign_key "directus_shares", "directus_roles", column: "role", name: "directus_shares_role_foreign", on_delete: :cascade
  add_foreign_key "directus_shares", "directus_users", column: "user_created", name: "directus_shares_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_users", "directus_roles", column: "role", name: "directus_users_role_foreign", on_delete: :nullify
  add_foreign_key "directus_versions", "directus_collections", column: "collection", primary_key: "collection", name: "directus_versions_collection_foreign", on_delete: :cascade
  add_foreign_key "directus_versions", "directus_users", column: "user_created", name: "directus_versions_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_versions", "directus_users", column: "user_updated", name: "directus_versions_user_updated_foreign"
  add_foreign_key "directus_webhooks", "directus_flows", column: "migrated_flow", name: "directus_webhooks_migrated_flow_foreign", on_delete: :nullify
  add_foreign_key "event_attendee_fields", "events", on_delete: :cascade
  add_foreign_key "event_boolean_field_translations", "event_boolean_fields", on_delete: :cascade
  add_foreign_key "event_boolean_field_translations", "languages", column: "languages_code", primary_key: "code", name: "event_boolean_field_translations_languages_code_fk"
  add_foreign_key "event_boolean_fields", "events", on_delete: :cascade
  add_foreign_key "event_gallery", "directus_files", column: "directus_files_id", name: "event_gallery_directus_files_id_foreign"
  add_foreign_key "event_gallery", "events", on_delete: :cascade
  add_foreign_key "event_speakers_translations", "event_speakers", name: "fk_rails_event_speakers_translations_speaker", on_delete: :cascade
  add_foreign_key "event_speakers_translations", "languages", column: "languages_code", primary_key: "code", name: "fk_rails_event_speakers_translations_language", on_update: :cascade, on_delete: :restrict
  add_foreign_key "event_template_doc_translations", "event_template_docs", on_delete: :cascade
  add_foreign_key "event_template_doc_translations", "languages", column: "languages_code", primary_key: "code"
  add_foreign_key "event_template_docs", "directus_files", column: "directus_files_id", name: "event_template_docs_directus_files_id_foreign"
  add_foreign_key "event_template_docs", "events", on_delete: :cascade
  add_foreign_key "events", "directus_files", column: "hero_image", name: "events_hero_image_foreign"
  add_foreign_key "events", "directus_files", column: "hero_portrait", name: "events_hero_portrait_foreign", on_delete: :nullify
  add_foreign_key "events_translations", "events", on_delete: :cascade
  add_foreign_key "events_translations", "languages", column: "languages_code", primary_key: "code", on_update: :cascade, on_delete: :restrict
  add_foreign_key "meal_stamps", "attendees", on_delete: :cascade
  add_foreign_key "meal_stamps", "ticket_meal_slots", on_delete: :cascade
  add_foreign_key "meal_stamps", "users", column: "stamped_by_user_id"
  add_foreign_key "orders", "users"
  add_foreign_key "passkeys", "users", on_delete: :cascade
  add_foreign_key "push_notifications", "events"
  add_foreign_key "push_notifications", "users", column: "created_by_id"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_processes", column: "process_id", on_delete: :restrict
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_processes", "solid_queue_processes", column: "supervisor_id", on_delete: :nullify
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "ticket_meal_slots", "tickets"
  add_foreign_key "tickets_translations", "languages", column: "languages_code", primary_key: "code", on_update: :cascade, on_delete: :restrict
  add_foreign_key "tickets_translations", "tickets", column: "tickets_id", on_delete: :cascade
  add_foreign_key "user_identities", "users", on_delete: :cascade
end
