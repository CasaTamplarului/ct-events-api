# frozen_string_literal: true

class SendCancellationAlertJob < ApplicationJob
  queue_as :default

  def perform(attendee_id)
    # implemented in Task 3
  end
end
