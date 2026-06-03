# frozen_string_literal: true

module Api
  module V1
    module Scan
      class MealStampsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def create
          qr_code   = params[:qr_code]
          meal_type = params[:meal_type]
          occurs_on = params[:occurs_on]

          if qr_code.blank? || meal_type.blank? || occurs_on.blank?
            return render json: { error: 'qr_code, meal_type, and occurs_on are required' },
                          status: :unprocessable_content
          end

          attendee = resolve_attendee(qr_code)
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

          slot = attendee.ticket&.ticket_meal_slots&.find do |s|
            s.meal_type == meal_type && s.occurs_on.to_s == occurs_on.to_s
          end

          return render json: { error: 'Not entitled' }, status: :unprocessable_content unless slot

          stamp = MealStamp.create!(attendee: attendee, ticket_meal_slot: slot,
                                    stamped_by_user_id: current_user.id)
          total = MealStamp.where(attendee: attendee, ticket_meal_slot: slot).count

          render json: {
            stamp: {
              id:         stamp.id,
              stamped_at: stamp.created_at,
              stamped_by: "#{current_user.first_name} #{current_user.last_name}".strip
            },
            already_stamped: total > 1,
            total_stamps:    total,
            attendee: { id: attendee.id, first_name: attendee.first_name, last_name: attendee.last_name }
          }
        end

        private

          def resolve_attendee(qr_code)
            attendee_id = qr_code.split('-').last.to_i
            attendee    = Attendee.includes(ticket: :ticket_meal_slots).find_by(id: attendee_id)
            return nil unless attendee
            return nil unless attendee.qr_code == qr_code

            attendee
          end
      end
    end
  end
end
