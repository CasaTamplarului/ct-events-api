# frozen_string_literal: true

class AddAllergiesToEventAttendeeFieldChoices < ActiveRecord::Migration[8.1]
  NEW_OPTIONS = JSON.generate({
    choices: [
      { text: 'First Name',          value: 'first_name' },
      { text: 'Last Name',           value: 'last_name' },
      { text: 'Email Address',       value: 'email_address' },
      { text: 'Phone Number',        value: 'phone_number' },
      { text: 'Dietary Preference',  value: 'dietary_preference' },
      { text: 'Allergies',           value: 'allergies', icon: 'warning' },
      { text: 'Church Name',         value: 'church_name', icon: 'church' },
      { text: 'City',                value: 'city', icon: 'location_city' },
      { text: 'Age',                 value: 'age', icon: 'celebration' }
    ]
  }).freeze

  OLD_OPTIONS = JSON.generate({
    choices: [
      { text: 'First Name',          value: 'first_name' },
      { text: 'Last Name',           value: 'last_name' },
      { text: 'Email Address',       value: 'email_address' },
      { text: 'Phone Number',        value: 'phone_number' },
      { text: 'Dietary Preference',  value: 'dietary_preference' },
      { text: 'Church Name',         value: 'church_name', icon: 'church' },
      { text: 'City',                value: 'city', icon: 'location_city' },
      { text: 'Age',                 value: 'age', icon: 'celebration' }
    ]
  }).freeze

  def up
    conn = ActiveRecord::Base.connection
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = #{conn.quote(NEW_OPTIONS)}::json
      WHERE collection = 'event_attendee_fields' AND field = 'field_name'
    SQL
  end

  def down
    conn = ActiveRecord::Base.connection
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = #{conn.quote(OLD_OPTIONS)}::json
      WHERE collection = 'event_attendee_fields' AND field = 'field_name'
    SQL
  end
end
