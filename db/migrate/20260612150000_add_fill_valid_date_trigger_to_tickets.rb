# frozen_string_literal: true

class AddFillValidDateTriggerToTickets < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION tickets_fill_valid_date_range()
      RETURNS trigger AS $$
      BEGIN
        IF NEW.valid_from IS NOT NULL AND NEW.valid_to IS NULL THEN
          NEW.valid_to := NEW.valid_from;
        ELSIF NEW.valid_to IS NOT NULL AND NEW.valid_from IS NULL THEN
          NEW.valid_from := NEW.valid_to;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER tickets_fill_valid_date_range_trigger
      BEFORE INSERT OR UPDATE ON tickets
      FOR EACH ROW EXECUTE FUNCTION tickets_fill_valid_date_range();
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS tickets_fill_valid_date_range_trigger ON tickets;
      DROP FUNCTION IF EXISTS tickets_fill_valid_date_range();
    SQL
  end
end
