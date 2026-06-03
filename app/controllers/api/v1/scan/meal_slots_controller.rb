# frozen_string_literal: true

module Api
  module V1
    module Scan
      class MealSlotsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index
          event = Event.find_by(slug: params[:event_slug])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless event

          if params[:date].blank?
            return render json: { error: 'date is required' }, status: :unprocessable_content
          end

          date = begin
                   Date.parse(params[:date])
                 rescue ArgumentError, TypeError
                   nil
                 end
          return render json: { error: 'invalid date' }, status: :unprocessable_content unless date

          slots = TicketMealSlot
                    .joins(:ticket)
                    .where(tickets: { event_id: event.id })
                    .where(occurs_on: date)
                    .order(:sort, :id)

          seen = {}
          deduplicated = slots.each_with_object([]) do |slot, arr|
            next if seen[slot.meal_type]

            seen[slot.meal_type] = true
            arr << slot
          end

          render json: deduplicated.map { |s|
            { id: s.id, meal_type: s.meal_type, occurs_on: s.occurs_on, sort: s.sort }
          }
        end
      end
    end
  end
end
