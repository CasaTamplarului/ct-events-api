# frozen_string_literal: true

class AddParticipantKeyToAttendees < ActiveRecord::Migration[8.1]
  def up
    add_column :attendees, :participant_key, :string

    Attendee.find_each do |attendee|
      key = [
        attendee.first_name.to_s.downcase.strip,
        attendee.last_name.to_s.downcase.strip,
        attendee.email_address.to_s.downcase.strip
      ].join('|')
      attendee.update_column(:participant_key, key) # rubocop:disable Rails/SkipsModelValidations
    end

    add_index :attendees, :participant_key
  end

  def down
    remove_column :attendees, :participant_key
  end
end
