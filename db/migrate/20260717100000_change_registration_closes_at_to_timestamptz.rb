# frozen_string_literal: true

class ChangeRegistrationClosesAtToTimestamptz < ActiveRecord::Migration[7.1]
  def up
    # Directus converts user's local time to UTC before storing in timestamptz columns,
    # so staff picks 16:00 Romanian → stored as 13:00 UTC → read back as 16:00 Bucharest.
    # With timestamp without time zone, Directus was adding the offset instead (storing 19:00).
    change_column :events, :registration_closes_at, :timestamptz
  end

  def down
    change_column :events, :registration_closes_at, :datetime
  end
end
