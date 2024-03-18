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

ActiveRecord::Schema[7.0].define(version: 2024_03_14_120544) do
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
    t.integer "dietary_preference", default: 0, null: false
    t.index ["event_id"], name: "index_attendees_on_event_id"
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
    t.boolean "override_max_people", default: false, null: false
  end

  create_table "events_translations", force: :cascade do |t|
    t.integer "events_id"
    t.string "languages_code"
    t.string "name", null: false
    t.string "tag_line", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "languages", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "attendees", "events"
  add_foreign_key "events_translations", "events", column: "events_id", on_delete: :nullify
  add_foreign_key "events_translations", "languages", column: "languages_code", primary_key: "code", on_delete: :nullify
end
