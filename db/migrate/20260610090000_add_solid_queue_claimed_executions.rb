# frozen_string_literal: true

class AddSolidQueueClaimedExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_queue_claimed_executions do |t|
      t.references :job, null: false, index: { unique: true },
                         foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.references :process, foreign_key: { to_table: :solid_queue_processes, on_delete: :restrict }
      t.datetime :created_at, null: false
    end
  end
end
