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

ActiveRecord::Schema[7.1].define(version: 2024_04_09_125721) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "attendees", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email_address"
    t.string "phone_number"
    t.bigint "event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "payment_status", default: 0
    t.integer "dietary_preference", default: 0
    t.index ["event_id"], name: "index_attendees_on_event_id"
  end

  create_table "directus_activity", id: :serial, force: :cascade do |t|
    t.string "action", limit: 45, null: false
    t.uuid "user"
    t.timestamptz "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "ip", limit: 50
    t.string "user_agent", limit: 255
    t.string "collection", limit: 64, null: false
    t.string "item", limit: 255, null: false
    t.text "comment"
    t.string "origin", limit: 255
  end

  create_table "directus_collections", primary_key: "collection", id: { type: :string, limit: 64 }, force: :cascade do |t|
    t.string "icon", limit: 30
    t.text "note"
    t.string "display_template", limit: 255
    t.boolean "hidden", default: false, null: false
    t.boolean "singleton", default: false, null: false
    t.json "translations"
    t.string "archive_field", limit: 64
    t.boolean "archive_app_filter", default: true, null: false
    t.string "archive_value", limit: 255
    t.string "unarchive_value", limit: 255
    t.string "sort_field", limit: 64
    t.string "accountability", limit: 255, default: "all"
    t.string "color", limit: 255
    t.json "item_duplication_fields"
    t.integer "sort"
    t.string "group", limit: 64
    t.string "collapse", limit: 255, default: "open", null: false
    t.string "preview_url", limit: 255
    t.boolean "versioning", default: false, null: false
  end

  create_table "directus_dashboards", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "icon", limit: 30, default: "dashboard", null: false
    t.text "note"
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.uuid "user_created"
    t.string "color", limit: 255
  end

  create_table "directus_extensions", id: :uuid, default: nil, force: :cascade do |t|
    t.boolean "enabled", default: true, null: false
    t.string "folder", limit: 255, null: false
    t.string "source", limit: 255, null: false
    t.uuid "bundle"
  end

  create_table "directus_fields", id: :serial, force: :cascade do |t|
    t.string "collection", limit: 64, null: false
    t.string "field", limit: 64, null: false
    t.string "special", limit: 64
    t.string "interface", limit: 64
    t.json "options"
    t.string "display", limit: 64
    t.json "display_options"
    t.boolean "readonly", default: false, null: false
    t.boolean "hidden", default: false, null: false
    t.integer "sort"
    t.string "width", limit: 30, default: "full"
    t.json "translations"
    t.text "note"
    t.json "conditions"
    t.boolean "required", default: false
    t.string "group", limit: 64
    t.json "validation"
    t.text "validation_message"
  end

  create_table "directus_files", id: :uuid, default: nil, force: :cascade do |t|
    t.string "storage", limit: 255, null: false
    t.string "filename_disk", limit: 255
    t.string "filename_download", limit: 255, null: false
    t.string "title", limit: 255
    t.string "type", limit: 255
    t.uuid "folder"
    t.uuid "uploaded_by"
    t.timestamptz "uploaded_on", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "modified_by"
    t.timestamptz "modified_on", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "charset", limit: 50
    t.bigint "filesize"
    t.integer "width"
    t.integer "height"
    t.integer "duration"
    t.string "embed", limit: 200
    t.text "description"
    t.text "location"
    t.text "tags"
    t.json "metadata"
    t.integer "focal_point_x"
    t.integer "focal_point_y"
  end

  create_table "directus_flows", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "icon", limit: 30
    t.string "color", limit: 255
    t.text "description"
    t.string "status", limit: 255, default: "active", null: false
    t.string "trigger", limit: 255
    t.string "accountability", limit: 255, default: "all"
    t.json "options"
    t.uuid "operation"
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
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
    t.timestamptz "timestamp", default: -> { "CURRENT_TIMESTAMP" }
    t.string "status", limit: 255, default: "inbox"
    t.uuid "recipient", null: false
    t.uuid "sender"
    t.string "subject", limit: 255, null: false
    t.text "message"
    t.string "collection", limit: 64
    t.string "item", limit: 255
  end

  create_table "directus_operations", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", limit: 255
    t.string "key", limit: 255, null: false
    t.string "type", limit: 255, null: false
    t.integer "position_x", null: false
    t.integer "position_y", null: false
    t.json "options"
    t.uuid "resolve"
    t.uuid "reject"
    t.uuid "flow", null: false
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.uuid "user_created"

    t.unique_constraint ["reject"], name: "directus_operations_reject_unique"
    t.unique_constraint ["resolve"], name: "directus_operations_resolve_unique"
  end

  create_table "directus_panels", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "dashboard", null: false
    t.string "name", limit: 255
    t.string "icon", limit: 30
    t.string "color", limit: 10
    t.boolean "show_header", default: false, null: false
    t.text "note"
    t.string "type", limit: 255, null: false
    t.integer "position_x", null: false
    t.integer "position_y", null: false
    t.integer "width", null: false
    t.integer "height", null: false
    t.json "options"
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.uuid "user_created"
  end

  create_table "directus_permissions", id: :serial, force: :cascade do |t|
    t.uuid "role"
    t.string "collection", limit: 64, null: false
    t.string "action", limit: 10, null: false
    t.json "permissions"
    t.json "validation"
    t.json "presets"
    t.text "fields"
  end

  create_table "directus_presets", id: :serial, force: :cascade do |t|
    t.string "bookmark", limit: 255
    t.uuid "user"
    t.uuid "role"
    t.string "collection", limit: 64
    t.string "search", limit: 100
    t.string "layout", limit: 100, default: "tabular"
    t.json "layout_query"
    t.json "layout_options"
    t.integer "refresh_interval"
    t.json "filter"
    t.string "icon", limit: 30, default: "bookmark"
    t.string "color", limit: 255
  end

  create_table "directus_relations", id: :serial, force: :cascade do |t|
    t.string "many_collection", limit: 64, null: false
    t.string "many_field", limit: 64, null: false
    t.string "one_collection", limit: 64
    t.string "one_field", limit: 64
    t.string "one_collection_field", limit: 64
    t.text "one_allowed_collections"
    t.string "junction_field", limit: 64
    t.string "sort_field", limit: 64
    t.string "one_deselect_action", limit: 255, default: "nullify", null: false
  end

  create_table "directus_revisions", id: :serial, force: :cascade do |t|
    t.integer "activity", null: false
    t.string "collection", limit: 64, null: false
    t.string "item", limit: 255, null: false
    t.json "data"
    t.json "delta"
    t.integer "parent"
    t.uuid "version"
  end

  create_table "directus_roles", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "icon", limit: 30, default: "supervised_user_circle", null: false
    t.text "description"
    t.text "ip_access"
    t.boolean "enforce_tfa", default: false, null: false
    t.boolean "admin_access", default: false, null: false
    t.boolean "app_access", default: true, null: false
  end

  create_table "directus_sessions", primary_key: "token", id: { type: :string, limit: 64 }, force: :cascade do |t|
    t.uuid "user"
    t.timestamptz "expires", null: false
    t.string "ip", limit: 255
    t.string "user_agent", limit: 255
    t.uuid "share"
    t.string "origin", limit: 255
  end

  create_table "directus_settings", id: :serial, force: :cascade do |t|
    t.string "project_name", limit: 100, default: "Directus", null: false
    t.string "project_url", limit: 255
    t.string "project_color", limit: 255, default: "#6644FF", null: false
    t.uuid "project_logo"
    t.uuid "public_foreground"
    t.uuid "public_background"
    t.text "public_note"
    t.integer "auth_login_attempts", default: 25
    t.string "auth_password_policy", limit: 100
    t.string "storage_asset_transform", limit: 7, default: "all"
    t.json "storage_asset_presets"
    t.text "custom_css"
    t.uuid "storage_default_folder"
    t.json "basemaps"
    t.string "mapbox_key", limit: 255
    t.json "module_bar"
    t.string "project_descriptor", limit: 100
    t.string "default_language", limit: 255, default: "en-US", null: false
    t.json "custom_aspect_ratios"
    t.uuid "public_favicon"
    t.string "default_appearance", limit: 255, default: "auto", null: false
    t.string "default_theme_light", limit: 255
    t.json "theme_light_overrides"
    t.string "default_theme_dark", limit: 255
    t.json "theme_dark_overrides"
  end

  create_table "directus_shares", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", limit: 255
    t.string "collection", limit: 64, null: false
    t.string "item", limit: 255, null: false
    t.uuid "role"
    t.string "password", limit: 255
    t.uuid "user_created"
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.timestamptz "date_start"
    t.timestamptz "date_end"
    t.integer "times_used", default: 0
    t.integer "max_uses"
  end

  create_table "directus_translations", id: :uuid, default: nil, force: :cascade do |t|
    t.string "language", limit: 255, null: false
    t.string "key", limit: 255, null: false
    t.text "value", null: false
  end

  create_table "directus_users", id: :uuid, default: nil, force: :cascade do |t|
    t.string "first_name", limit: 50
    t.string "last_name", limit: 50
    t.string "email", limit: 128
    t.string "password", limit: 255
    t.string "location", limit: 255
    t.string "title", limit: 50
    t.text "description"
    t.json "tags"
    t.uuid "avatar"
    t.string "language", limit: 255
    t.string "tfa_secret", limit: 255
    t.string "status", limit: 16, default: "active", null: false
    t.uuid "role"
    t.string "token", limit: 255
    t.timestamptz "last_access"
    t.string "last_page", limit: 255
    t.string "provider", limit: 128, default: "default", null: false
    t.string "external_identifier", limit: 255
    t.json "auth_data"
    t.boolean "email_notifications", default: true
    t.string "appearance", limit: 255
    t.string "theme_dark", limit: 255
    t.string "theme_light", limit: 255
    t.json "theme_light_overrides"
    t.json "theme_dark_overrides"

    t.unique_constraint ["email"], name: "directus_users_email_unique"
    t.unique_constraint ["external_identifier"], name: "directus_users_external_identifier_unique"
    t.unique_constraint ["token"], name: "directus_users_token_unique"
  end

  create_table "directus_versions", id: :uuid, default: nil, force: :cascade do |t|
    t.string "key", limit: 64, null: false
    t.string "name", limit: 255
    t.string "collection", limit: 64, null: false
    t.string "item", limit: 255, null: false
    t.string "hash", limit: 255
    t.timestamptz "date_created", default: -> { "CURRENT_TIMESTAMP" }
    t.timestamptz "date_updated", default: -> { "CURRENT_TIMESTAMP" }
    t.uuid "user_created"
    t.uuid "user_updated"
  end

  create_table "directus_webhooks", id: :serial, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "method", limit: 10, default: "POST", null: false
    t.string "url", limit: 255, null: false
    t.string "status", limit: 10, default: "active", null: false
    t.boolean "data", default: true, null: false
    t.string "actions", limit: 100, null: false
    t.string "collections", limit: 255, null: false
    t.json "headers"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "start_date", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "end_date", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "status", default: 0
    t.integer "max_number_of_people"
    t.integer "min_age"
    t.integer "max_age"
    t.boolean "override_max_people", default: false
    t.boolean "hero", default: false, null: false
  end

  create_table "events_translations", force: :cascade do |t|
    t.integer "event_id"
    t.string "languages_code"
    t.string "name", limit: 255
    t.string "tag_line", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug", limit: 255
    t.index ["name"], name: "index_events_translations_on_name", unique: true
    t.index ["slug"], name: "index_events_translations_on_slug", unique: true
    t.unique_constraint ["name"], name: "events_translations_name_unique"
  end

  create_table "languages", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tickets", force: :cascade do |t|
    t.decimal "price"
    t.bigint "event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_tickets_on_event_id"
  end

  create_table "tickets_translations", force: :cascade do |t|
    t.integer "tickets_id"
    t.string "languages_code"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "attendees", "events"
  add_foreign_key "directus_collections", "directus_collections", column: "group", primary_key: "collection", name: "directus_collections_group_foreign"
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
  add_foreign_key "directus_permissions", "directus_roles", column: "role", name: "directus_permissions_role_foreign", on_delete: :cascade
  add_foreign_key "directus_presets", "directus_roles", column: "role", name: "directus_presets_role_foreign", on_delete: :cascade
  add_foreign_key "directus_presets", "directus_users", column: "user", name: "directus_presets_user_foreign", on_delete: :cascade
  add_foreign_key "directus_revisions", "directus_activity", column: "activity", name: "directus_revisions_activity_foreign", on_delete: :cascade
  add_foreign_key "directus_revisions", "directus_revisions", column: "parent", name: "directus_revisions_parent_foreign"
  add_foreign_key "directus_revisions", "directus_versions", column: "version", name: "directus_revisions_version_foreign", on_delete: :cascade
  add_foreign_key "directus_sessions", "directus_shares", column: "share", name: "directus_sessions_share_foreign", on_delete: :cascade
  add_foreign_key "directus_sessions", "directus_users", column: "user", name: "directus_sessions_user_foreign", on_delete: :cascade
  add_foreign_key "directus_settings", "directus_files", column: "project_logo", name: "directus_settings_project_logo_foreign"
  add_foreign_key "directus_settings", "directus_files", column: "public_background", name: "directus_settings_public_background_foreign"
  add_foreign_key "directus_settings", "directus_files", column: "public_favicon", name: "directus_settings_public_favicon_foreign"
  add_foreign_key "directus_settings", "directus_files", column: "public_foreground", name: "directus_settings_public_foreground_foreign"
  add_foreign_key "directus_settings", "directus_folders", column: "storage_default_folder", name: "directus_settings_storage_default_folder_foreign", on_delete: :nullify
  add_foreign_key "directus_shares", "directus_collections", column: "collection", primary_key: "collection", name: "directus_shares_collection_foreign", on_delete: :cascade
  add_foreign_key "directus_shares", "directus_roles", column: "role", name: "directus_shares_role_foreign", on_delete: :cascade
  add_foreign_key "directus_shares", "directus_users", column: "user_created", name: "directus_shares_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_users", "directus_roles", column: "role", name: "directus_users_role_foreign", on_delete: :nullify
  add_foreign_key "directus_versions", "directus_collections", column: "collection", primary_key: "collection", name: "directus_versions_collection_foreign", on_delete: :cascade
  add_foreign_key "directus_versions", "directus_users", column: "user_created", name: "directus_versions_user_created_foreign", on_delete: :nullify
  add_foreign_key "directus_versions", "directus_users", column: "user_updated", name: "directus_versions_user_updated_foreign"
  add_foreign_key "events_translations", "languages", column: "languages_code", primary_key: "code"
  add_foreign_key "tickets", "events", on_delete: :cascade
  add_foreign_key "tickets_translations", "languages", column: "languages_code", primary_key: "code"
  add_foreign_key "tickets_translations", "tickets", column: "tickets_id", on_delete: :cascade
end
