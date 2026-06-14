# frozen_string_literal: true

class TicketAllowedUser < ApplicationRecord
  self.table_name = 'tickets_allowed_users'

  belongs_to :ticket
  belongs_to :user
end
