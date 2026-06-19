# frozen_string_literal: true

module Api
  module V1
    module Scan
      class WheelController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index
          event = Event.find_by(id: params[:event_id])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless event

          attendees = event.attendees
                           .includes(:ticket)
                           .where.not(payment_status: %i[refunded attendee_cancelled])

          if params[:checked_in].present?
            checked_in = ActiveModel::Type::Boolean.new.cast(params[:checked_in])
            attendees = attendees.where(checked_in: checked_in)
          end

          render json: {
            participants: attendees.map do |a|
              {
                id:           a.id,
                first_name:   a.first_name,
                last_name:    a.last_name,
                ticket_name:  a.ticket&.name,
                checked_in:   a.checked_in,
                wheel_winner: a.wheel_winner
              }
            end
          }
        end

        def update_winner
          attendee = Attendee.find_by(id: params[:attendee_id])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

          winner = ActiveModel::Type::Boolean.new.cast(params[:winner])
          attendee.update_column(:wheel_winner, winner) # rubocop:disable Rails/SkipsModelValidations

          render json: { id: attendee.id, wheel_winner: attendee.wheel_winner }
        end
      end
    end
  end
end
