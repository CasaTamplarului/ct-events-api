# frozen_string_literal: true

module Api
  module V1
    module Scan
      class SearchController < ActionController::API
        include Authenticatable
        include ScanSerialisable

        VALID_TYPES = %w[order_ref name email phone].freeze
        REQUIRES_EVENT_SLUG = %w[name email phone].freeze

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index; end
      end
    end
  end
end
