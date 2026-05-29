# frozen_string_literal: true

class CreateEventSpeakersTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :event_speakers_translations do |t|
      t.references :event_speaker, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.text :description
      t.string :action_label

      t.timestamps
    end

    add_foreign_key :event_speakers_translations, :languages,
                    column: :languages_code, primary_key: :code,
                    on_update: :cascade, on_delete: :restrict
  end
end
