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

        def spin
          event = Event.find_by(id: params[:event_id])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless event

          attendees = event.attendees
                           .includes(:ticket)
                           .where.not(payment_status: %i[refunded attendee_cancelled])
                           .where(wheel_winner: false)

          if params[:checked_in].present?
            checked_in = ActiveModel::Type::Boolean.new.cast(params[:checked_in])
            attendees = attendees.where(checked_in: checked_in)
          end

          winner = attendees.order('RANDOM()').first
          unless winner
            return render json: { error: 'No eligible participants remaining' },
                          status: :unprocessable_content
          end

          winner.update_column(:wheel_winner, true) # rubocop:disable Rails/SkipsModelValidations

          payload = {
            action:   'winner',
            attendee: {
              id:          winner.id,
              first_name:  winner.first_name,
              last_name:   winner.last_name,
              ticket_name: winner.ticket&.name
            }
          }

          ActionCable.server.broadcast("wheel_event_#{event.id}", payload)

          render json: payload
        end

        def update_winner
          attendee = Attendee.find_by(id: params[:attendee_id])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

          winner = params.key?(:winner) ? ActiveModel::Type::Boolean.new.cast(params[:winner]) : true
          attendee.update_column(:wheel_winner, winner) # rubocop:disable Rails/SkipsModelValidations

          render json: { id: attendee.id, wheel_winner: attendee.wheel_winner }
        end
      end
    end
  end
end
