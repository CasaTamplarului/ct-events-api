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

        def index
          return unless valid_search_params?

          orders = case params[:type]
                   when 'order_ref' then search_by_order_ref(params[:query])
                   when 'name'      then search_by_name(params[:query])
                   when 'email'     then search_by_email(params[:query])
                   when 'phone'     then search_by_phone(params[:query])
                   end

          render json: orders.map { |o| serialise_order(o) }
        end

        private

          def valid_search_params?
            if missing_required_params?
              render json: { error: 'type and query are required' }, status: :unprocessable_content
              return false
            end

            unless VALID_TYPES.include?(params[:type].to_s)
              render json: { error: 'Invalid type' }, status: :unprocessable_content
              return false
            end

            if short_query?
              render json: { error: 'query must be at least 2 characters' }, status: :unprocessable_content
              return false
            end

            valid_event_slug?
          end

          def valid_event_slug?
            return true unless REQUIRES_EVENT_SLUG.include?(params[:type].to_s)

            if params[:event_slug].blank?
              render json: { error: 'event_slug is required for this search type' }, status: :unprocessable_content
              return false
            end

            @event = Event.find_by(slug: params[:event_slug])

            unless @event
              render json: { error: 'Not found' }, status: :not_found
              return false
            end

            true
          end

          def missing_required_params?
            params[:type].blank? || params[:query].blank?
          end

          def short_query?
            params[:query].to_s.length < 2
          end

          def search_by_order_ref(query)
            Order.where('order_reference ILIKE ?', "%#{query}%")
                 .order(:order_reference)
                 .limit(20)
          end

          def search_by_name(query)
            Order.joins(attendees: :event)
                 .where(events: { id: @event.id })
                 .where(
                   'attendees.first_name ILIKE :q OR attendees.last_name ILIKE :q OR ' \
                   "CONCAT(attendees.first_name, ' ', attendees.last_name) ILIKE :q",
                   q: "%#{query}%"
                 )
                 .distinct
                 .order(:order_reference)
                 .limit(20)
          end

          def search_by_email(query)
            Order.joins(attendees: :event)
                 .where(events: { id: @event.id })
                 .where('attendees.email_address ILIKE ?', "%#{query}%")
                 .distinct
                 .order(:order_reference)
                 .limit(20)
          end

          def search_by_phone(query)
            Order.joins(attendees: :event)
                 .where(events: { id: @event.id })
                 .where('attendees.phone_number ILIKE ?', "%#{query}%")
                 .distinct
                 .order(:order_reference)
                 .limit(20)
          end
      end
    end
  end
end
