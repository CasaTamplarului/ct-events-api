# frozen_string_literal: true

class CreateAttendeeBooleanFieldResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :attendee_boolean_field_responses do |t|
      t.references :attendee,            null: false, foreign_key: { on_delete: :cascade }
      t.references :event_boolean_field, null: false, foreign_key: { on_delete: :cascade }
      t.boolean    :value,               null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :attendee_boolean_field_responses,
              %i[attendee_id event_boolean_field_id],
              unique: true,
              name: 'idx_attendee_boolean_field_responses_unique'
  end
end
